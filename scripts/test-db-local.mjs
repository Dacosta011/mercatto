import { readFileSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { assertLocal, sql, docker, migrate } from './db-local.mjs';
import { testMarketConcurrency } from './test-market-concurrency-local.mjs';
import { testClauseConcurrency } from './test-clause-concurrency-local.mjs';
import { testAuctionConcurrency } from './test-auction-concurrency-local.mjs';
assertLocal();
const database = 'mercatto_foundation_test';
if (sql("SELECT count(*) FROM pg_database WHERE datname='mercatto_foundation_test';").trim() === '0') {
  docker(['createdb', '-U', 'postgres', database]);
}
sql("DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_publication WHERE pubname='supabase_realtime') THEN CREATE PUBLICATION supabase_realtime; END IF; END $$;", database);
migrate(database);
if (sql('SELECT (SELECT count(*) FROM public.tournaments) + (SELECT count(*) FROM public.teams);', database).trim() !== '0') {
  throw new Error('Dedicated test database contains existing data; refusing to run cleanup-capable tests.');
}
console.log(sql(readFileSync(new URL('../supabase/tests/game_foundation.sql', import.meta.url), 'utf8'), database));
const catalogue = readFileSync(new URL('../supabase/local/game_catalog.sql', import.meta.url), 'utf8').replace(/^BEGIN;$/m,'').replace(/^COMMIT;$/m,'');
const flowTests = readFileSync(new URL('../supabase/tests/game_local_flow.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue);
console.log(sql(flowTests, database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_market.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_counter.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_clause.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_auction.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_competition.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_ballot_candidates.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_competition_edges.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_pool_social.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_ui_mutations.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));
console.log(sql(readFileSync(new URL('../supabase/tests/game_postponements.sql', import.meta.url), 'utf8').replace('-- CATALOG_FIXTURES', catalogue), database));

// Two independent PostgreSQL connections compete for the same club.
const tournament = randomUUID();
const members = [randomUUID(), randomUUID()];
let initialized = false;
try {
  sql(`BEGIN;
INSERT INTO public.tournaments(id,name,code,admin_token_hash) VALUES('${tournament}','concurrency','${tournament}','test');
INSERT INTO public.teams(name) VALUES('__concurrency_club') ON CONFLICT(name) DO NOTHING;
INSERT INTO public.members(id,tournament_id,display_name,member_token_hash) VALUES
('${members[0]}','${tournament}','one','test'),('${members[1]}','${tournament}','two','test');
SELECT game.initialize('${tournament}',1000); COMMIT;`, database);
  initialized = true;
  const club = sql(`SELECT id FROM game.clubs WHERE tournament_id='${tournament}' LIMIT 1;`, database).trim();
  function compete(member) {
    return new Promise((resolve, reject) => {
      const child = spawn('docker', ['exec', '-i', 'supabase_db_mercatto', 'psql', '-X', '-U', 'postgres', '-d', database, '-v', 'ON_ERROR_STOP=1', '-At']);
      let output = '';
      child.stdout.on('data', chunk => { output += chunk; });
      child.stderr.on('data', chunk => { output += chunk; });
      child.on('error', reject);
      child.on('close', code => resolve({ code, output }));
      child.stdin.end(`BEGIN; SELECT game.assign_club('${tournament}','${member}','${club}','${member}'); SELECT pg_sleep(0.5); COMMIT;`);
    });
  }
  const results = await Promise.all(members.map(compete));
  if (results.filter(r => r.code === 0).length !== 1 || !results.some(r => r.output.includes('Club already assigned'))) {
    throw new Error(`Expected one winner and one occupied-club rejection: ${JSON.stringify(results)}`);
  }
  if (sql(`SELECT count(*) FROM game.assignments WHERE tournament_id='${tournament}' AND ended_at IS NULL;`, database).trim() !== '1') {
    throw new Error('Concurrent assignment produced multiple owners');
  }
  console.log('Concurrent assignment test passed: exactly one owner.');
} finally {
  // This fixed, dedicated test database contains no real data; never runs against postgres.
  if (initialized) sql(`TRUNCATE game.tournaments CASCADE;
DELETE FROM public.tournaments WHERE id='${tournament}';
DELETE FROM public.teams WHERE name='__concurrency_club';`, database);
}
await testMarketConcurrency();
await testClauseConcurrency();
await testAuctionConcurrency();
