import {mkdirSync,writeFileSync} from 'node:fs';
import {assertLocal,sql,docker} from './db-local.mjs';

if(process.argv.slice(2).join(' ')!=='--confirm-reset-local-games')throw new Error('Requires --confirm-reset-local-games. Deletes the LOCAL catalogue and dependent games.');
assertLocal();
mkdirSync(new URL('../.local-db/',import.meta.url),{recursive:true});
const backup=new URL(`../.local-db/before-catalog-reset-${Date.now()}.sql`,import.meta.url);
writeFileSync(backup,docker(['pg_dump','-U','postgres','-d','postgres']));
console.log(`Full local backup: ${backup.pathname}`);
console.log(sql(`BEGIN;
SELECT pg_advisory_xact_lock(173812905);
TRUNCATE public.tournaments,public.team_players,public.players,public.teams CASCADE;
DO $reset$ BEGIN IF to_regclass('public.sofifa_imports') IS NOT NULL THEN EXECUTE 'TRUNCATE public.sofifa_imports'; END IF; END $reset$;
SELECT 'players='||count(*) FROM public.players;
SELECT 'teams='||count(*) FROM public.teams;
SELECT 'team_players='||count(*) FROM public.team_players;
SELECT 'tournaments='||count(*) FROM public.tournaments;
COMMIT;`));
