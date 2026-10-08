import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { sql } from './db-local.mjs';
export async function testAuctionConcurrency() {
 const database='mercatto_foundation_test',query=source=>sql(source,database),value=source=>query(source).trim().split('\n').at(-1);
 assert.equal(value('SELECT count(*) FROM public.tournaments;'),'0');
 function connection(source,ready) {
  return new Promise((resolve,reject)=>{
   const child=spawn('docker',['exec','-i','supabase_db_mercatto','psql','-X','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-At']);let output='';
   child.stdout.on('data',chunk=>{output+=chunk;if(output.includes('LOCK_READY')) ready?.();});child.stderr.on('data',chunk=>{output+=chunk;});
   child.on('error',reject);child.on('close',code=>resolve({code,output}));child.stdin.end(source);
  });
 }
 let seeded=false;
 try {
  query(readFileSync(new URL('../supabase/local/game_catalog.sql',import.meta.url),'utf8'));seeded=true;
  query("INSERT INTO public.players(id,name,ovr,position,price,clause,is_icon) VALUES('f3000000-0000-0000-0000-000000000003','Concurrency icon',90,'ST',20000000,26000000,true);");
  const admin=randomUUID(),northToken=randomUUID(),southToken=randomUUID(),rivalToken=randomUUID();
  const created=JSON.parse(value(`SELECT public.game_create_tournament('${randomUUID()}','Auction races','North','${admin}','${northToken}',ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],ARRAY['f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002','f3000000-0000-0000-0000-000000000003']::uuid[]);`));
  const clubs=[1,2,3].map(n=>value(`SELECT id FROM game.clubs WHERE tournament_id='${created.id}' AND team_id='f1000000-0000-0000-0000-${String(n).padStart(12,'0')}';`));
  query(`SELECT public.game_join_tournament('${created.code}','South','${southToken}','${randomUUID()}');SELECT public.game_join_tournament('${created.code}','Rival','${rivalToken}','${randomUUID()}');`);
  [northToken,southToken,rivalToken].forEach((token,i)=>query(`SELECT public.game_choose_club('${created.code}','${token}','${clubs[i]}','${randomUUID()}');`));
  const market=action=>`SELECT public.game_market_command('${created.code}','${admin}','${randomUUID()}','${action}',NULL,NULL,NULL,${action==='open'?"'summer',60":'NULL,NULL'});`;
  const start=n=>JSON.parse(value(`SELECT public.game_auction_command('${created.code}','${admin}','${randomUUID()}','auction_open','f3000000-0000-0000-0000-${String(n).padStart(12,'0')}',NULL,NULL,10);`)).auctionId;
  const bid=(token,key,auction,amount)=>`SELECT public.game_auction_command('${created.code}','${token}','${key}','auction_bid',NULL,'${auction}',${amount});`;
  query(market('open'));const first=start(1);
  const firstRace=await Promise.all([northToken,rivalToken].map(token=>connection(bid(token,randomUUID(),first,30000000))));
  assert.equal(firstRace.filter(r=>r.code===0).length,1,JSON.stringify(firstRace));
  assert(firstRace.some(r=>r.output.includes('Auction bid below minimum')));
  assert.equal(value('SELECT sum(reserved) FROM game.accounts;'),'30000000');
  const retryKey=randomUUID(),same=bid(southToken,retryKey,first,35000000);
  const retries=await Promise.all([connection(same),connection(same)]);assert(retries.every(r=>r.code===0),JSON.stringify(retries));
  assert.equal(value(`SELECT count(*) FROM game.auction_bids WHERE auction_id='${first}';`),'2');
  assert.equal(value('SELECT sum(reserved) FROM game.accounts;'),'35000000');
  query(`UPDATE game.auctions SET starts_at=clock_timestamp()-interval '2 minutes',ends_at=clock_timestamp()-interval '1 second' WHERE id='${first}';`);
  const workers=await Promise.all([connection('SET ROLE service_role;SELECT public.game_expire_markets();'),connection('SET ROLE service_role;SELECT public.game_expire_markets();')]);
  assert(workers.every(r=>r.code===0),JSON.stringify(workers));assert.equal(workers.filter(r=>r.output.includes('"settled": 1')).length,1);
  assert.equal(value("SELECT count(*) FROM game.transfers WHERE kind='icon_auction';"),'1');
  assert.equal(value('SELECT sum(reserved) FROM game.accounts;'),'0');
  query(market('close'));query(market('open'));const second=start(2);
  query(bid(southToken,randomUUID(),second,35000000));
  const closingRace=await Promise.all([connection(bid(rivalToken,randomUUID(),second,40000000)),connection(market('close'))]);
  assert.equal(closingRace[1].code,0,closingRace[1].output);
  assert.equal(value(`SELECT (a.highest_club_id=c.club_id AND a.highest_bid=c.acquired_price)::text FROM game.auctions a JOIN game.contracts c ON c.tournament_id=a.tournament_id AND c.player_id=a.player_id AND c.ended_at IS NULL WHERE a.id='${second}';`),'true');
  assert.equal(value("SELECT count(*) FROM game.transfers WHERE kind='icon_auction';"),'2');assert.equal(value('SELECT sum(reserved) FROM game.accounts;'),'0');
  query(market('open'));const third=start(3);
  let ready;const locked=new Promise(resolve=>{ready=resolve;});
  const holder=connection(`BEGIN;SELECT 1 FROM game.tournaments WHERE id='${created.id}' FOR UPDATE;UPDATE game.auctions SET ends_at=clock_timestamp()+interval '0.25 seconds' WHERE id='${third}';SELECT 'LOCK_READY';SELECT pg_sleep(0.6);COMMIT;`,ready);
  await Promise.race([locked,holder.then(()=>{throw new Error('Lock holder ended before readiness');})]);
  const late=await connection(bid(northToken,randomUUID(),third,20000000));await holder;
  assert.notEqual(late.code,0);assert(late.output.includes('Auction deadline passed'));
  query('SELECT public.game_expire_markets();');query(market('close'));query(market('open'));const fourth=start(3);
  const spendingRace=await Promise.all([
   connection(bid(northToken,randomUUID(),fourth,100000000)),
   connection(`SELECT public.game_market_command('${created.code}','${northToken}','${randomUUID()}','offer','f2000000-0000-0000-0000-000000000003',NULL,100000000);`),
  ]);
  assert.equal(spendingRace.filter(r=>r.code===0).length,1,JSON.stringify(spendingRace));
  assert(spendingRace.some(r=>r.output.includes('Insufficient available balance')));assert.equal(value(`SELECT reserved FROM game.accounts WHERE club_id='${clubs[0]}';`),'100000000');
  query(market('close'));
  assert.equal(value('SELECT sum(reserved) FROM game.accounts;'),'0');
  assert.equal(value('SELECT count(*) FROM (SELECT a.id FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)) x;'),'0');
  console.log('Auction concurrency passed: competing bids, retries, workers, bid/close race, deadline after lock and shared-budget protection.');
 } finally {if(seeded) query('TRUNCATE game.tournaments,public.tournaments,public.teams,public.players CASCADE;');}
}
