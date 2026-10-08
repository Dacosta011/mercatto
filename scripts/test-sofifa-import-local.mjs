import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {assertLocal,sql,migrate} from './db-local.mjs';
import {importSnapshot,validateSnapshot} from './import-sofifa-local.mjs';

assertLocal();
const db='mercatto_foundation_test';
migrate(db);
const q=s=>sql(s,db).trim();
assert.equal(q('SELECT (SELECT count(*) FROM public.players)+(SELECT count(*) FROM public.teams)+(SELECT count(*) FROM public.tournaments);'),'0','Dedicated DB must be empty');
const teams=JSON.parse(readFileSync(new URL('./sofifa-teams.json',import.meta.url),'utf8'));
const data={source:'sofifa',revision:270003,fetchedAt:new Date().toISOString(),teams:teams.map((t,i)=>({...t,players:Array.from({length:18},(_,j)=>({id:100000+i*100+j,name:`Synthetic ${i}-${j}`,ovr:80,position:'ST',country:'Spain',headshotUrl:null}))}))};
data.teams[0].players[1].name=data.teams[0].players[0].name; // Homonyms are distinct people.
try{
 importSnapshot(data,{database:db});
 assert.equal(q('SELECT count(*) FROM public.players;'),'0','Dry-run rolls back');
 importSnapshot(data,{database:db,apply:true});
 const before=q('SELECT jsonb_object_agg(sofifa_id,id) FROM public.players;');
 importSnapshot(data,{database:db,apply:true});
 assert.equal(q('SELECT jsonb_object_agg(sofifa_id,id) FROM public.players;'),before,'UUIDs stable on replay');
 assert.equal(q('SELECT count(*) FROM public.sofifa_imports;'),'1','Replay does not duplicate audit');
 assert.equal(q('SELECT count(*) FROM public.players;'),'288');
 assert.throws(()=>q("INSERT INTO public.players(name,ovr,price,sofifa_id) VALUES('Duplicate external ID',80,1,100000);"),/unique/);
 assert.throws(()=>q(`INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=${teams[1].id} AND p.sofifa_id=100000;`),/unique/);
 const teamIds=JSON.parse(q('SELECT jsonb_agg(id) FROM public.teams;'));
 const game=JSON.parse(q(`SELECT public.game_create_competition('${randomUUID()}','Import snapshot test','Manager','${randomUUID()}','${randomUUID()}',ARRAY[${teamIds.map(id=>`'${id}'`).join(',')}]::uuid[],'{}'::uuid[]);`));
 const frozen=q(`SELECT jsonb_agg(to_jsonb(p) ORDER BY player_id) FROM game.players p WHERE tournament_id='${game.id}';`);
 const changed=structuredClone(data);changed.revision++;
 changed.teams[0].players[0].ovr=87;changed.teams[0].players[0].position='CM';changed.teams[0].players[0].name='Updated name';
 const transferred=changed.teams[0].players.shift();changed.teams[1].players.push(transferred);
 changed.teams[0].players.push({id:999001,name:'New player',ovr:75,position:'GK',country:null,headshotUrl:null});
 importSnapshot(changed,{database:db,apply:true});
 const player=JSON.parse(q('SELECT jsonb_build_object(\'id\',id,\'ovr\',ovr,\'position\',position) FROM public.players WHERE sofifa_id=100000;'));
 assert.equal(player.id,JSON.parse(before)['100000']);assert.equal(player.ovr,87);assert.equal(player.position,'CM');
 assert.equal(q('SELECT t.sofifa_id FROM public.team_players tp JOIN public.players p ON p.id=tp.player_id JOIN public.teams t ON t.id=tp.team_id WHERE p.sofifa_id=100000;'),String(teams[1].id));
 assert.equal(q(`SELECT jsonb_agg(to_jsonb(p) ORDER BY player_id) FROM game.players p WHERE tournament_id='${game.id}';`),frozen,'Existing game snapshot unchanged');
 assert.throws(()=>importSnapshot(data,{database:db,apply:true}),/older edition/);
 const duplicate=structuredClone(changed);duplicate.teams[0].players.push(duplicate.teams[1].players[0]);
 assert.throws(()=>validateSnapshot(duplicate),/Duplicate/);
 const partial=structuredClone(changed);partial.teams.pop();assert.throws(()=>validateSnapshot(partial),/16/);
 const removed=structuredClone(changed);removed.revision++;removed.teams[1].players.pop();
 importSnapshot(removed,{database:db,apply:true});
 assert.equal(q('SELECT count(*) FROM public.team_players tp JOIN public.players p ON p.id=tp.player_id WHERE p.sofifa_id=100000;'),'0','Departure removes membership');
 assert.equal(q('SELECT count(*) FROM public.players WHERE sofifa_id=100000;'),'1','Historical player identity retained');
 const bad=structuredClone(removed);bad.revision++;bad.teams[1].name=bad.teams[0].name;
 const unchanged=q('SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.players p;');
 assert.throws(()=>importSnapshot(bad,{database:db,apply:true}),/unique/);
 assert.equal(q('SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM public.players p;'),unchanged,'SQL failure rolls back complete batch');
 console.log('PASS: preview, repeat import, stable IDs, OVR/name/position updates, transfer, departure, immutable game snapshot, stale edition, duplicates, incomplete batch and atomic rollback.');
}finally{
 // Fixed, dedicated test DB was required empty above; production/postgres is never cleaned here.
 q('TRUNCATE public.tournaments,public.players,public.teams,public.sofifa_imports CASCADE;');
}
