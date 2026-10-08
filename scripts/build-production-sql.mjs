// Generates an offline, one-time cutover script. Does not connect to production.
import {readFileSync,readdirSync,mkdirSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {priceFor} from './import-sofifa-local.mjs';
import {readEnv} from './db-production.mjs';
const root=new URL('../',import.meta.url);
const snapshot=JSON.parse(readFileSync(new URL('.local-db/sofifa/saved-validated.json',root),'utf8'));
const assets=JSON.parse(readFileSync(new URL('.local-db/sofifa/assets-uploaded.json',root),'utf8'));
const endpoint=new URL(readEnv(new URL('.env.local',root)).NEXT_PUBLIC_SUPABASE_URL);
if(endpoint.protocol!=='https:'||!endpoint.hostname.endsWith('.supabase.co'))throw new Error('Expected hosted production endpoint');
const literal=v=>"'"+String(v).replaceAll("'","''")+"'";
const asset=(kind,id)=>{
 const a=assets.assets.find(a=>a.kind===kind&&a.id===id);
 if(!a)throw new Error(`Missing asset ${kind}/${id}`);
 return `${endpoint.origin}/storage/v1/object/public/sofifa-assets/${a.key}`;
};
const baseline=readFileSync(new URL('supabase/migrations/00000000000000_schema.sql',root),'utf8');
const tables=[...baseline.matchAll(/create table if not exists (\w+)/gi)].map(m=>m[1]);
const files=readdirSync(new URL('supabase/migrations/',root)).filter(f=>/^20261005\d+_.*\.sql$/.test(f)).sort();
if(files.length!==28||snapshot.teams.length!==16||snapshot.teams.reduce((n,t)=>n+t.players.length,0)!==437)throw new Error('Unexpected release contents');
let sql=`-- MERCATTO: REINICIO REMOTO AUTORIZADO, VERSION 270004.
-- Proyecto previsto: ${endpoint.hostname}
-- Ejecutar COMPLETO en Supabase SQL Editor con el rol postgres.
-- ANTES: respaldo externo verificado y ventana de mantenimiento.
-- DESTRUYE torneos, participantes, mercado, resultados, catalogo y dependencias.
-- No elimina usuarios de Auth, buckets ni objetos de Storage.
-- La app antigua dejara de funcionar: desplegar el backend nuevo coordinadamente.
-- SQL NO SUBE IMAGENES: los 453 objetos deben cargarse aparte a Storage remoto.
-- Primera instalacion del esquema game solamente. Una repeticion aborta SIN borrar.
BEGIN;
SET LOCAL search_path=public,extensions;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(173812905);
DO $preflight$ DECLARE tab text; BEGIN
 IF to_regnamespace('game') IS NOT NULL OR to_regclass('public.sofifa_imports') IS NOT NULL THEN
  RAISE EXCEPTION 'El modelo nuevo ya existe. No repetir este reinicio; revisar migraciones pendientes.';
 END IF;
 FOREACH tab IN ARRAY ARRAY[${tables.map(literal).join(',')}] LOOP
  IF to_regclass('public.'||tab) IS NULL THEN RAISE EXCEPTION 'Falta tabla heredada %. No se ha borrado nada.',tab; END IF;
 END LOOP;
END $preflight$;
-- Lista cerrada: sin CASCADE para rechazar dependencias imprevistas.
DO $wipe$ DECLARE targets text := ${literal(tables.map(t=>'public.'+t).join(','))}; tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['club_expenses','season_archive_assignments','season_archive_fixtures','season_archives','slot_machine_pool','slot_machine_spins','team_budgets'] LOOP
  IF to_regclass('public.'||tab) IS NOT NULL THEN targets := targets || ',public.' || quote_ident(tab); END IF;
 END LOOP;
 EXECUTE 'TRUNCATE ' || targets;
END $wipe$;
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations(version text PRIMARY KEY,statements text[],name text);
`;
for(const file of files){
 const source=readFileSync(new URL(`supabase/migrations/${file}`,root),'utf8');
 if(source.includes('$mercatto_source$'))throw new Error('Delimiter collision');
 const version=file.split('_')[0];
 sql+=`\n-- Migration ${file}\n${source}\nINSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES(${literal(version)},${literal(file.slice(version.length+1,-4))},ARRAY[$mercatto_source$${source}$mercatto_source$]);\n`;
}
for(const team of snapshot.teams){
 sql+=`\nINSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(${team.id},${literal(team.name)},${literal(asset('teams',team.id))},${snapshot.revision},now());\n`;
 for(const p of team.players){
  const price=priceFor(p.ovr),clause=Math.ceil(price*1.5/500000)*500000;
  sql+=`INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(${p.id},${literal(p.name)},${p.ovr},${literal(p.position)},${p.country?literal(p.country):'NULL'},${literal(asset('players',p.id))},${price},${clause},false,${snapshot.revision},now());\n`;
  sql+=`INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=${team.id} AND p.sofifa_id=${p.id};\n`;
 }
}
const digest=createHash('sha256').update(JSON.stringify(snapshot)).digest('hex');
sql+=`INSERT INTO public.sofifa_imports(revision,digest,team_count,player_count) VALUES(${snapshot.revision},${literal(digest)},16,437);
DO $verify$ BEGIN
 IF (SELECT count(*) FROM public.teams)<>16 OR (SELECT count(*) FROM public.players)<>437 OR (SELECT count(*) FROM public.team_players)<>437 OR (SELECT count(*) FROM public.tournaments)<>0 THEN RAISE EXCEPTION 'Verificacion final fallo'; END IF;
 IF EXISTS(SELECT player_id FROM public.team_players GROUP BY player_id HAVING count(*)<>1) THEN RAISE EXCEPTION 'Jugador duplicado'; END IF;
END $verify$;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'OK' AS resultado,16 AS equipos,437 AS jugadores,437 AS relaciones,${snapshot.revision} AS revision;
-- Copiar el resultado como variable MERCATTO_GAME_TEAM_IDS en Vercel:
SELECT string_agg(id::text,',' ORDER BY sofifa_id) AS "MERCATTO_GAME_TEAM_IDS" FROM public.teams;
SELECT t.name,count(tp.player_id) AS jugadores FROM public.teams t JOIN public.team_players tp ON tp.team_id=t.id GROUP BY t.id,t.name ORDER BY t.name;
`;
mkdirSync(new URL('supabase/deploy/',root),{recursive:true});
writeFileSync(new URL('supabase/deploy/reset-production.sql',root),sql);
console.log(`Generated reset-production.sql: ${files.length} migrations, 16 teams, 437 players. No remote connection made.`);
