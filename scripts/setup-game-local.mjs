import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { assertLocal, sql } from './db-local.mjs';
assertLocal();
const variables = {};
for (const container of ['supabase_kong_mercatto','supabase_studio_mercatto']) {
  const result = spawnSync('docker', ['inspect', '--format', '{{json .Config.Env}}', container], { encoding: 'utf8' });
  if (result.status !== 0) throw new Error('Cannot read local Supabase configuration');
  Object.assign(variables,Object.fromEntries(JSON.parse(result.stdout).map(entry => {
    const index = entry.indexOf('='); return [entry.slice(0, index), entry.slice(index + 1)];
  })));
}
const serviceKey = variables.SUPABASE_SERVICE_KEY || variables.SUPABASE_SERVICE_ROLE_KEY;
const anonKey = variables.SUPABASE_ANON_KEY;
if (!serviceKey || !anonKey) throw new Error('Local gateway keys not found');
// Secrets are written only to the ignored local development file, never to stdout.
const path = new URL('../.env.development.local', import.meta.url);
let config = '';
try { config = readFileSync(path, 'utf8'); } catch { /* fresh environment */ }
const updates = {
  NEXT_PUBLIC_SUPABASE_URL: 'http://127.0.0.1:54321',
  NEXT_PUBLIC_SUPABASE_ANON_KEY: anonKey,
  SUPABASE_SERVICE_ROLE_KEY: serviceKey,
  MERCATTO_GAME_MODEL: 'local',
  MERCATTO_GAME_TEAM_IDS: [1, 2, 3].map(n => `f1000000-0000-0000-0000-${String(n).padStart(12,'0')}`).join(','),
  MERCATTO_GAME_FREE_PLAYER_IDS: ['f2000000-0000-0000-0000-000000000005','f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002'].join(','),
};
config = config.split(/\r?\n/).filter(line => !Object.keys(updates).some(key => line.startsWith(`${key}=`))).join('\n').trim();
writeFileSync(path, `${config}\n${Object.entries(updates).map(([key,value])=>`${key}=${value}`).join('\n')}\n`);
sql(readFileSync(new URL('../supabase/local/game_catalog.sql', import.meta.url), 'utf8'));
console.log('Local test catalogue and development configuration ready. Restart next dev to load it.');
