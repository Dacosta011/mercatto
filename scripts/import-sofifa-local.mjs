import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
import {assertLocal,sql} from './db-local.mjs';

const configured=JSON.parse(readFileSync(new URL('./sofifa-teams.json',import.meta.url),'utf8'));
const literal=value=>"'"+String(value).replaceAll("'","''")+"'";
const positive=value=>Number.isSafeInteger(value)&&value>0;
const validText=value=>typeof value==='string'&&value.trim().length>0&&value.length<=200;
const asset=value=>value===null||value===undefined||(typeof value==='string'&&/^https:\/\/(cdn\.sofifa\.net|sofifa\.com)\//.test(value));

// Same OVR always produces the same initial price. Rerunning does not reroll prices.
export function priceFor(ovr){
 const tiers=[[91,120,20],[88,70,15],[85,40,10],[82,20,6],[79,10,3],[76,5,1.5],[73,2,.8]];
 const tier=tiers.find(([floor])=>ovr>=floor);
 return Math.round((tier?tier[1]+(ovr-tier[0])*tier[2]:.5+Math.max(0,ovr-65)*.15)*2)*500000;
}

export function validateSnapshot(data,{allowSavedHtml=false}={}){
 const saved=allowSavedHtml&&data.source==='sofifa-saved-html';
 if((data.source!=='sofifa'&&!saved)||!Number.isInteger(data.revision)||data.revision<200000||data.revision>999999)throw new Error('Invalid source or edition');
 const age=Date.now()-Date.parse(saved?data.validatedAt:data.fetchedAt);
 if(!Number.isFinite(age)||age< -60000||age>24*3600000)throw new Error('Snapshot expired; download the latest edition again');
 if(!Array.isArray(data.teams)||data.teams.length!==configured.length)throw new Error('All 16 configured teams must succeed before importing');
 const teams=new Set(),players=new Set();
 for(const team of data.teams){
  if(!configured.some(c=>c.id===team.id)||teams.has(team.id)||!validText(team.name)||!asset(team.crestUrl))throw new Error('Invalid or duplicate team identity');
  teams.add(team.id);
  if(!Array.isArray(team.players)||team.players.length<18||team.players.length>80)throw new Error(`Incomplete roster: ${team.id}`);
  for(const p of team.players){
   if(!positive(p.id)||players.has(p.id))throw new Error(`Duplicate or invalid player identity: ${p.id}`);
   if(!validText(p.name)||!validText(p.position)||!Number.isInteger(p.ovr)||p.ovr<1||p.ovr>99||!asset(p.headshotUrl)||(p.country!=null&&!validText(p.country)))throw new Error(`Invalid player: ${p.id}`);
   players.add(p.id);
  }
 }
 return {teams:teams.size,players:players.size};
}

export function importSnapshot(data,{database='postgres',apply=false,allowSavedHtml=false}={}){
 assertLocal();
 const counts=validateSnapshot(data,{allowSavedHtml});
 const payload=data.teams.map(t=>({...t,players:t.players.map(p=>({...p,price:priceFor(p.ovr),clause:Math.ceil(priceFor(p.ovr)*1.5/500000)*500000}))}));
 const digest=createHash('sha256').update(JSON.stringify({revision:data.revision,teams:payload})).digest('hex');
 const query=`BEGIN;
SELECT pg_advisory_xact_lock(173812905);
LOCK TABLE public.teams,public.players,public.team_players IN EXCLUSIVE MODE;
CREATE TEMP TABLE sofifa_batch AS SELECT ${literal(JSON.stringify(payload))}::jsonb AS data;
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM public.sofifa_imports WHERE revision>${data.revision}) THEN RAISE EXCEPTION 'Refusing an older edition'; END IF;
 IF EXISTS(SELECT 1 FROM public.teams WHERE sofifa_id IS NULL) OR EXISTS(SELECT 1 FROM public.players WHERE sofifa_id IS NULL AND NOT coalesce(is_icon,false)) THEN RAISE EXCEPTION 'Unmapped legacy catalogue: reset or explicitly reconcile it first'; END IF;
END $guard$;
CREATE TEMP TABLE incoming_teams AS SELECT (t->>'id')::bigint sid,t->>'name' name,t->>'crestUrl' crest FROM sofifa_batch,jsonb_array_elements(data) t;
CREATE TEMP TABLE incoming_players AS SELECT (t->>'id')::bigint team_sid,(p->>'id')::bigint sid,p->>'name' name,(p->>'ovr')::integer ovr,p->>'position' position,p->>'country' country,p->>'headshotUrl' headshot,(p->>'price')::integer price,(p->>'clause')::integer clause FROM sofifa_batch,jsonb_array_elements(data) t,jsonb_array_elements(t->'players') p;
ALTER TABLE incoming_teams ADD PRIMARY KEY(sid);
ALTER TABLE incoming_players ADD PRIMARY KEY(sid);
INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at)
 SELECT sid,name,crest,${data.revision},clock_timestamp() FROM incoming_teams
 ON CONFLICT(sofifa_id) DO UPDATE SET name=excluded.name,crest_url=CASE WHEN teams.crest_url LIKE 'http://127.0.0.1:54321/storage/v1/object/public/sofifa-assets/%' THEN teams.crest_url ELSE coalesce(excluded.crest_url,teams.crest_url) END,sofifa_revision=excluded.sofifa_revision,sofifa_updated_at=excluded.sofifa_updated_at
 WHERE (teams.name,teams.crest_url,teams.sofifa_revision) IS DISTINCT FROM (excluded.name,CASE WHEN teams.crest_url LIKE 'http://127.0.0.1:54321/storage/v1/object/public/sofifa-assets/%' THEN teams.crest_url ELSE coalesce(excluded.crest_url,teams.crest_url) END,excluded.sofifa_revision);
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at)
 SELECT sid,name,ovr,position,country,headshot,price,clause,false,${data.revision},clock_timestamp() FROM incoming_players
 ON CONFLICT(sofifa_id) DO UPDATE SET name=excluded.name,ovr=excluded.ovr,position=excluded.position,country_name=excluded.country_name,headshot_url=CASE WHEN players.headshot_url LIKE 'http://127.0.0.1:54321/storage/v1/object/public/sofifa-assets/%' THEN players.headshot_url ELSE coalesce(excluded.headshot_url,players.headshot_url) END,price=excluded.price,clause=excluded.clause,sofifa_revision=excluded.sofifa_revision,sofifa_updated_at=excluded.sofifa_updated_at
 WHERE (players.name,players.ovr,players.position,players.country_name,players.headshot_url,players.price,players.clause,players.sofifa_revision) IS DISTINCT FROM (excluded.name,excluded.ovr,excluded.position,excluded.country_name,CASE WHEN players.headshot_url LIKE 'http://127.0.0.1:54321/storage/v1/object/public/sofifa-assets/%' THEN players.headshot_url ELSE coalesce(excluded.headshot_url,players.headshot_url) END,excluded.price,excluded.clause,excluded.sofifa_revision);
-- Clear only roster memberships superseded by this complete batch. Keep player UUIDs and game snapshots.
DELETE FROM public.team_players tp USING public.teams t,public.players p
 WHERE tp.team_id=t.id AND tp.player_id=p.id
 AND (t.sofifa_id IN(SELECT sid FROM incoming_teams) OR p.sofifa_id IN(SELECT sid FROM incoming_players))
 AND NOT EXISTS(SELECT 1 FROM incoming_players i WHERE i.sid=p.sofifa_id AND i.team_sid=t.sofifa_id);
INSERT INTO public.team_players(team_id,player_id)
 SELECT t.id,p.id FROM incoming_players i JOIN public.teams t ON t.sofifa_id=i.team_sid JOIN public.players p ON p.sofifa_id=i.sid
 ON CONFLICT(team_id,player_id) DO NOTHING;
DO $guard$ BEGIN
 IF EXISTS(SELECT player_id FROM public.team_players GROUP BY player_id HAVING count(*)>1) THEN RAISE EXCEPTION 'Duplicate base roster owner'; END IF;
END $guard$;
INSERT INTO public.sofifa_imports(revision,digest,team_count,player_count) VALUES(${data.revision},${literal(digest)},${counts.teams},${counts.players}) ON CONFLICT(digest) DO NOTHING;
SELECT jsonb_build_object('edition',${data.revision},'teams',${counts.teams},'players',${counts.players},'applied',${apply});
${apply?'COMMIT':'ROLLBACK'};`;
 return sql(query,database);
}

export function configureLocalCatalogue(){
 assertLocal();
 const ids=JSON.parse(sql(`SELECT jsonb_agg(id ORDER BY sofifa_id) FROM public.teams WHERE sofifa_id IN(${configured.map(t=>t.id).join(',')});`).trim());
 if(!Array.isArray(ids)||ids.length!==configured.length)throw new Error('Import saved, but local game configuration requires all 16 teams');
 const path=new URL('../.env.development.local',import.meta.url);
 const content=readFileSync(path,'utf8').split(/\r?\n/).filter(line=>!/^MERCATTO_GAME_(TEAM_IDS|FREE_PLAYER_IDS)=/.test(line)).join('\n').trim();
 writeFileSync(path,`${content}\nMERCATTO_GAME_TEAM_IDS=${ids.join(',')}\nMERCATTO_GAME_FREE_PLAYER_IDS=\n`);
 console.log('Local new-game team selection updated. Restart the local dev server if it is running.');
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 const args=process.argv.slice(2),input=args[0];
 if(!input||args.slice(1).some(a=>!['--apply','--allow-saved-html'].includes(a)))throw new Error('Usage: node scripts/import-sofifa-local.mjs SNAPSHOT.json [--apply] [--allow-saved-html]');
 console.log(importSnapshot(JSON.parse(readFileSync(input,'utf8')),{apply:args.includes('--apply'),allowSavedHtml:args.includes('--allow-saved-html')}));
 if(args.includes('--apply'))configureLocalCatalogue();
}
