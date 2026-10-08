import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { sql } from './db-local.mjs';

// Called only by test-db-local after its dedicated database emptiness check.
export async function testMarketConcurrency() {
  const database = 'mercatto_foundation_test';
  if (sql('SELECT count(*) FROM public.tournaments;',database).trim()!=='0') throw new Error('Test database is not empty');
  function query(source) { return sql(source,database); }
  function value(source) { return query(source).trim().split('\n').at(-1); }
  function connection(source, ready) {
    return new Promise((resolve,reject)=>{
      const child=spawn('docker',['exec','-i','supabase_db_mercatto','psql','-X','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-At']);
      let output='';
      child.stdout.on('data',chunk=>{ output+=chunk; if(output.includes('LOCK_READY')) ready?.(); });
      child.stderr.on('data',chunk=>{output+=chunk;});
      child.on('error',reject); child.on('close',code=>resolve({code,output}));
      child.stdin.end(source);
    });
  }
  const admin=randomUUID(), buyer=randomUUID(), seller=randomUUID();
  let seeded=false;
  try {
    query(readFileSync(new URL('../supabase/local/game_catalog.sql',import.meta.url),'utf8')); seeded=true;
    query(`INSERT INTO public.players(id,name,ovr,position,price,clause) VALUES
('f2000000-0000-0000-0000-000000000006','Budget race one',80,'CM',100000000,200000000),
('f2000000-0000-0000-0000-000000000007','Budget race two',80,'CM',100000000,200000000);`);
    const created=JSON.parse(value(`SELECT public.game_create_tournament('${randomUUID()}','Concurrency market','Buyer','${admin}','${buyer}',
ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002']::uuid[],ARRAY['f2000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000006','f2000000-0000-0000-0000-000000000007']::uuid[]);`));
    const clubA=value(`SELECT id FROM game.clubs WHERE tournament_id='${created.id}' AND team_id='f1000000-0000-0000-0000-000000000001';`);
    const clubB=value(`SELECT id FROM game.clubs WHERE tournament_id='${created.id}' AND team_id='f1000000-0000-0000-0000-000000000002';`);
    query(`SELECT public.game_join_tournament('${created.code}','Seller','${seller}','${randomUUID()}');
SELECT public.game_choose_club('${created.code}','${buyer}','${clubA}','${randomUUID()}');
SELECT public.game_choose_club('${created.code}','${seller}','${clubB}','${randomUUID()}');`);
    const command=(token,key,action,player='NULL',offer='NULL',amount='NULL',kind='NULL',minutes='NULL')=>
      `SELECT public.game_market_command('${created.code}','${token}','${key}','${action}',${player},${offer},${amount},${kind},${minutes});`;
    query(command(admin,randomUUID(),'open','NULL','NULL','NULL',"'summer'",'60'));
    const race=await Promise.all([buyer,seller].map(token=>connection(`SET ROLE service_role; BEGIN; ${command(token,randomUUID(),'sign',"'f2000000-0000-0000-0000-000000000005'")} SELECT pg_sleep(0.1); COMMIT;`)));
    assert.equal(race.filter(r=>r.code===0).length,1,'Exactly one concurrent free-agent purchase must succeed');
    assert(race.some(r=>r.output.includes('Player is no longer free')));
    assert.equal(value('SELECT count(*) FROM game.transfers;'),'1');
    const purchases=await Promise.all([6,7].map(n=>connection(`SET ROLE service_role; BEGIN; ${command(buyer,randomUUID(),'sign',`'f2000000-0000-0000-0000-${String(n).padStart(12,'0')}'`)} SELECT pg_sleep(0.1); COMMIT;`)));
    assert.equal(purchases.filter(r=>r.code===0).length,1,'Only one of two 100M purchases can fit');
    assert(purchases.some(r=>r.output.includes('Insufficient available balance')));
    assert.equal(value('SELECT count(*) FROM game.transfers;'),'2');
    const offers=await Promise.all([3,4].map(n=>connection(`SET ROLE service_role; BEGIN; ${command(buyer,randomUUID(),'offer',`'f2000000-0000-0000-0000-${String(n).padStart(12,'0')}'`,'NULL','40000000')} SELECT pg_sleep(0.1); COMMIT;`)));
    assert.equal(offers.filter(r=>r.code===0).length,1,'Only one 40M hold can fit in the available balance');
    assert(offers.some(r=>r.output.includes('Insufficient available balance')));
    assert.equal(value(`SELECT reserved FROM game.accounts WHERE club_id='${clubA}';`),'40000000');
    query(command(admin,randomUUID(),'close'));
    query(command(admin,randomUUID(),'open','NULL','NULL','NULL',"'winter'",'60'));
    const retryKey=randomUUID();
    const sameOffer=command(buyer,retryKey,'offer',"'f2000000-0000-0000-0000-000000000003'",'NULL','1000000');
    const retries=await Promise.all([connection(sameOffer),connection(sameOffer)]);
    assert(retries.every(r=>r.code===0),JSON.stringify(retries));
    assert.equal(value("SELECT count(*) FROM game.offers WHERE status='pending';"),'1','Concurrent retries produce one offer');
    assert.equal(value(`SELECT reserved FROM game.accounts WHERE club_id='${clubA}';`),'1000000');
    let ready;
    const locked=new Promise(resolve=>{ready=resolve;});
    const holder=connection(`BEGIN; SELECT 1 FROM game.tournaments WHERE id='${created.id}' FOR UPDATE;
UPDATE game.market_windows SET closes_at=clock_timestamp()+interval '0.25 seconds' WHERE tournament_id='${created.id}' AND status='open';
SELECT 'LOCK_READY'; SELECT pg_sleep(0.6); COMMIT;`,ready);
    // A broken lock holder must reject the test rather than leave a pending wait forever.
    await Promise.race([locked,holder.then(()=>{throw new Error('Lock holder ended before announcing readiness');})]);
    const delayed=await connection(command(buyer,randomUUID(),'offer',"'f2000000-0000-0000-0000-000000000004'",'NULL','1000000'));
    await holder;
    assert.notEqual(delayed.code,0);
    assert(delayed.output.includes('Market deadline passed'),'Deadline must be read after waiting for the tournament lock');
    let workerReady;
    const workerLocked=new Promise(resolve=>{workerReady=resolve;});
    const workerHolder=connection(`BEGIN; SELECT 1 FROM game.tournaments WHERE id='${created.id}' FOR UPDATE;
SELECT 'LOCK_READY'; SELECT pg_sleep(0.6); COMMIT;`,workerReady);
    await Promise.race([workerLocked,workerHolder.then(()=>{throw new Error('Worker lock holder ended before readiness');})]);
    const skipped=await connection('SET ROLE service_role; SET statement_timeout=300; SELECT public.game_expire_markets();');
    assert.equal(skipped.code,0,skipped.output);
    assert(skipped.output.includes('"closed": 0'),'Worker must skip a locked expired tournament');
    await workerHolder;
    const workers=await Promise.all([connection('SET ROLE service_role; SELECT public.game_expire_markets();'),connection('SET ROLE service_role; SELECT public.game_expire_markets();')]);
    assert(workers.every(r=>r.code===0),JSON.stringify(workers));
    assert.equal(workers.filter(r=>r.output.includes('"closed": 1')).length,1,'Exactly one worker settles the window');
    assert.equal(value("SELECT count(*) FROM game.operations WHERE kind='market_auto_close';"),'1');
    assert.equal(value('SELECT sum(reserved) FROM game.accounts;'),'0');
    assert.equal(value('SELECT count(*) FROM (SELECT a.id FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)) x;'),'0');
    console.log('Market concurrency tests passed: ownership, holds, retries, deadline after lock, busy worker skip and simultaneous closure.');
  } finally {
    // Only the allowlisted disposable test database is used here.
    if(seeded) query('TRUNCATE game.tournaments,public.tournaments,public.teams,public.players CASCADE;');
  }
}

