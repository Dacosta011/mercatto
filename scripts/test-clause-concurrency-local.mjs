import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { sql } from './db-local.mjs';

export async function testClauseConcurrency() {
  const database='mercatto_foundation_test';
  const query=source=>sql(source,database);
  const value=source=>query(source).trim().split('\n').at(-1);
  assert.equal(value('SELECT count(*) FROM public.tournaments;'),'0','Disposable test database must be empty');
  function connection(source,ready) {
    return new Promise((resolve,reject)=>{
      const child=spawn('docker',['exec','-i','supabase_db_mercatto','psql','-X','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-At']);
      let output='';
      child.stdout.on('data',chunk=>{output+=chunk;if(output.includes('LOCK_READY')) ready?.();});
      child.stderr.on('data',chunk=>{output+=chunk;});
      child.on('error',reject);child.on('close',code=>resolve({code,output}));child.stdin.end(source);
    });
  }
  let seeded=false;
  try {
    query(readFileSync(new URL('../supabase/local/game_catalog.sql',import.meta.url),'utf8'));seeded=true;
    const admin=randomUUID(),northToken=randomUUID(),southToken=randomUUID(),rivalToken=randomUUID();
    const created=JSON.parse(value(`SELECT public.game_create_tournament('${randomUUID()}','Clause concurrency','North','${admin}','${northToken}',ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],ARRAY[]::uuid[]);`));
    const clubs=[1,2,3].map(n=>value(`SELECT id FROM game.clubs WHERE tournament_id='${created.id}' AND team_id='f1000000-0000-0000-0000-${String(n).padStart(12,'0')}';`));
    query(`SELECT public.game_join_tournament('${created.code}','South','${southToken}','${randomUUID()}');SELECT public.game_join_tournament('${created.code}','Rival','${rivalToken}','${randomUUID()}');`);
    [northToken,southToken,rivalToken].forEach((token,i)=>query(`SELECT public.game_choose_club('${created.code}','${token}','${clubs[i]}','${randomUUID()}');`));
    const player=n=>`'f2000000-0000-0000-0000-${String(n).padStart(12,'0')}'`;
    const command=(token,key,action,player='NULL',offer='NULL',amount='NULL',kind='NULL',minutes='NULL')=>`SELECT public.game_market_command('${created.code}','${token}','${key}','${action}',${player},${offer},${amount},${kind},${minutes});`;
    const clause=(token,key,n)=>`SELECT public.game_pay_clause('${created.code}','${token}','${key}',${player(n)});`;
    // Seeding is available only on this trusted direct SQL test connection, never through HTTP.
    assert.equal(value('SELECT setseed(0);SELECT random()>=0.25;'),'t');
    const attempt=source=>connection(`SET ROLE service_role;SELECT setseed(0);BEGIN;${source}SELECT pg_sleep(0.1);COMMIT;`);
    const open=()=>query(command(admin,randomUUID(),'open','NULL','NULL','NULL',"'summer'",'60'));
    const close=()=>query(command(admin,randomUUID(),'close'));
    open();
    const competing=await Promise.all([northToken,rivalToken].map(token=>attempt(clause(token,randomUUID(),4))));
    assert.equal(competing.filter(r=>r.code===0).length,1,JSON.stringify(competing));
    assert(competing.some(r=>r.output.includes('Player already transferred in this window')));
    assert.equal(value('SELECT count(*) FROM game.clause_attempts;'),'1');
    close();open();
    const key=randomUUID(),same=clause(northToken,key,3);
    const retries=await Promise.all([attempt(same),attempt(same)]);
    assert(retries.every(r=>r.code===0),JSON.stringify(retries));
    assert.equal(value(`SELECT count(*) FROM game.clause_attempts WHERE player_id=${player(3)};`),'1');
    assert.equal(value('SELECT count(*) FROM game.transfers;'),'2');
    close();open();
    const offered=JSON.parse(value(command(southToken,randomUUID(),'offer',player(2),'NULL','10000000')));
    const mixed=await Promise.all([attempt(clause(rivalToken,randomUUID(),2)),attempt(command(northToken,randomUUID(),'accept','NULL',`'${offered.offerId}'`))]);
    assert.equal(mixed.filter(r=>r.code===0).length,1,JSON.stringify(mixed));
    assert.equal(value(`SELECT count(*) FROM game.transfers WHERE player_id=${player(2)};`),'1');
    assert.equal(value('SELECT sum(reserved) FROM game.accounts;'),'0');
    close();open();
    const protection=await Promise.all([1,3].map(n=>attempt(clause(southToken,randomUUID(),n))));
    assert.equal(protection.filter(r=>r.code===0).length,1,JSON.stringify(protection));
    assert(protection.some(r=>r.output.includes('Seller clause protection reached')));
    close();open();
    let ready;const locked=new Promise(resolve=>{ready=resolve;});
    const holder=connection(`BEGIN;SELECT 1 FROM game.tournaments WHERE id='${created.id}' FOR UPDATE;UPDATE game.market_windows SET closes_at=clock_timestamp()+interval '0.25 seconds' WHERE tournament_id='${created.id}' AND status='open';SELECT 'LOCK_READY';SELECT pg_sleep(0.6);COMMIT;`,ready);
    await Promise.race([locked,holder.then(()=>{throw new Error('Lock holder ended before readiness');})]);
    const delayed=await connection(clause(northToken,randomUUID(),4));await holder;
    assert.notEqual(delayed.code,0);assert(delayed.output.includes('Market deadline passed'));
    close();
    assert.equal(value('SELECT count(*) FROM (SELECT a.id FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)) x;'),'0');
    console.log('Clause concurrency passed: competing buyers, same-key retries, clause/offer race, seller protection and deadline after a lock wait.');
  } finally {
    if(seeded) query('TRUNCATE game.tournaments,public.tournaments,public.teams,public.players CASCADE;');
  }
}
