import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {assertLocal,sql} from './db-local.mjs';
assertLocal();
const backup=process.argv[2];if(!backup)throw Error('Usage: node scripts/restore-icons-local.mjs BACKUP.sql');
const dump=readFileSync(backup,'utf8');
const block=dump.match(/COPY public\.players \(([^\n]+)\) FROM stdin;\r?\n([\s\S]*?)\r?\n\\\./);
if(!block)throw Error('Player COPY data missing');
const cols=block[1].split(', ').map(c=>c.replaceAll('"',''));
function decode(s){if(s==='\\N')return null;return s.replace(/\\([\\tnr])/g,(_,c)=>({t:'\t',n:'\n',r:'\r','\\':'\\'}[c]));}
const icons=block[2].split(/\r?\n/).map(l=>Object.fromEntries(l.split('\t').map((v,i)=>[cols[i],decode(v)]))).filter(p=>p.is_icon==='t');
if(icons.length!==52||new Set(icons.map(p=>p.id)).size!==52)throw Error('Expected 52 distinct original icons');
const lit=v=>v===null?'NULL':"'"+String(v).replaceAll("'","''")+"'";
const fields=['id','name','ovr','position','price','clause','created_at','country_name','country_code','card_image_url','headshot_url','is_icon','salary'];
let query='BEGIN; SELECT pg_advisory_xact_lock(173812905);\n';
for(const p of icons){
 query+=`DO $$ BEGIN IF EXISTS(SELECT 1 FROM public.players WHERE (id=${lit(p.id)} OR lower(name)=lower(${lit(p.name)})) AND (id<>${lit(p.id)} OR NOT is_icon)) THEN RAISE EXCEPTION 'Conflicting original icon identity'; END IF; END $$;\n`;
 const updates=fields.filter(f=>!['id','created_at'].includes(f)).map(f=>f==='headshot_url'
  ? `headshot_url=CASE WHEN public.players.headshot_url LIKE 'http://127.0.0.1:54321/storage/v1/object/public/sofifa-assets/icons/%' THEN public.players.headshot_url ELSE EXCLUDED.headshot_url END`
  : '"'+f+'"=EXCLUDED."'+f+'"');
 query+=`INSERT INTO public.players(${fields.map(f=>'"'+f+'"').join(',')}) VALUES(${fields.map(f=>lit(p[f])).join(',')}) ON CONFLICT(id) DO UPDATE SET ${updates.join(',')};\n`;
}
query+='COMMIT;';
mkdirSync('.local-db/icons',{recursive:true});writeFileSync('.local-db/icons/original-icons.json',JSON.stringify(icons,null,2));writeFileSync('.local-db/icons/restore-original-icons.sql',query);
sql(query);
console.log(sql("SELECT count(*) FILTER(WHERE is_icon) AS icons,count(*) FILTER(WHERE NOT is_icon) AS regular FROM public.players;"));
console.log('Restored 52 original icons locally; IDs preserved. Remote untouched.');
