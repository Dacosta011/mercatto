import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {assertLocal,sql} from './db-local.mjs';
import {readEnv} from './db-production.mjs';

const production=process.argv.includes('--production');
if(!production)assertLocal();
const input=process.argv[2];
if(!input||process.argv.slice(3).some(a=>a!=='--production'))throw new Error('Usage: node scripts/upload-sofifa-assets-local.mjs MANIFEST.json [--production]');
const manifest=JSON.parse(readFileSync(input,'utf8'));
const env={};
for(const line of readFileSync(new URL('../.env.development.local',import.meta.url),'utf8').split(/\r?\n/)){
 const m=line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);if(m)env[m[1]]=m[2].replace(/^['"]|['"]$/g,'');
}
let base='http://127.0.0.1:54321';
const bucket='sofifa-assets';
if(production){
 const hosted=readEnv(new URL('../.env.local',import.meta.url));
 const secrets=readEnv(new URL('../.env.production.local',import.meta.url));
 base=hosted.NEXT_PUBLIC_SUPABASE_URL;
 if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(base))throw new Error('Expected existing hosted Supabase project');
 env.SUPABASE_SERVICE_ROLE_KEY=secrets.SUPABASE_SERVICE_ROLE_KEY;
 console.log('Target: hosted Supabase Storage. Catalogue SQL is not executed by this mode.');
}else if(env.NEXT_PUBLIC_SUPABASE_URL!==base)throw new Error('Requires local configuration');
if(!env.SUPABASE_SERVICE_ROLE_KEY)throw new Error('Missing service key');
if(env.SUPABASE_SERVICE_ROLE_KEY.startsWith('sb_publishable_'))throw new Error('A publishable key cannot upload assets. Configure a secret key or legacy service_role key.');
const headers={Authorization:`Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,apikey:env.SUPABASE_SERVICE_ROLE_KEY};
async function api(path,options={}){
 const r=await fetch(`${base}/storage/v1/${path}`,{...options,headers:{...headers,...options.headers},redirect:'error',signal:AbortSignal.timeout(30000)});
 if(!r.ok)throw new Error(`Storage ${path}: HTTP ${r.status}`);
 return r;
}
const identities=new Set();
const prepared=manifest.assets.map(a=>{
 if(!['teams','players'].includes(a.kind)||!Number.isSafeInteger(a.id)||a.id<=0||identities.has(`${a.kind}/${a.id}`))throw new Error('Invalid/duplicate identity');
 identities.add(`${a.kind}/${a.id}`);
 const data=readFileSync(a.path);
 if(data.length>5_000_000||data.length<24)throw new Error('Invalid image size');
 const png=data.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]));
 if(!png)throw new Error(`Expected PNG: ${a.kind}/${a.id}`);
 if(data.readUInt32BE(16)<16||data.readUInt32BE(20)<16)throw new Error('Image is an unloaded tracking pixel');
 const hash=createHash('sha256').update(data).digest('hex');
 const key=`${a.kind}/${a.id}/${hash}.png`;
 return {...a,data,hash,key,url:`${base}/storage/v1/object/public/${bucket}/${key}`};
});
if(prepared.filter(a=>a.kind==='teams').length!==16||prepared.filter(a=>a.kind==='players').length!==437)throw new Error('Expected the complete imported batch');
const existing=(await (await api('bucket')).json()).find(b=>b.id===bucket);
if(!existing)await api('bucket',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({id:bucket,name:bucket,public:true,file_size_limit:5000000,allowed_mime_types:['image/png']})});
else if(!existing.public)throw new Error('Existing bucket is not public');
for(let i=0;i<prepared.length;i++){
 const a=prepared[i];
 await api(`object/${bucket}/${a.key}`,{method:'POST',headers:{'Content-Type':'image/png','x-upsert':'true','cache-control':'31536000'},body:a.data});
 const response=await fetch(a.url,{redirect:'error',signal:AbortSignal.timeout(30000)});
 if(!response.ok||!response.headers.get('content-type')?.includes('image/png'))throw new Error(`Public image unavailable: ${a.key}`);
 const hash=createHash('sha256').update(Buffer.from(await response.arrayBuffer())).digest('hex');
 if(hash!==a.hash)throw new Error('Uploaded image bytes differ');
 if((i+1)%100===0)console.log(`${i+1}/${prepared.length} uploaded and verified`);
}
const literal=s=>"'"+String(s).replaceAll("'","''")+"'";
const payload=prepared.map(({kind,id,url})=>({kind,id,url}));
if(!production)console.log(sql(`BEGIN;
SELECT pg_advisory_xact_lock(173812905);
CREATE TEMP TABLE image_batch AS SELECT * FROM jsonb_to_recordset(${literal(JSON.stringify(payload))}::jsonb) AS x(kind text,id bigint,url text);
DO $$ BEGIN
 IF (SELECT count(*) FROM public.teams t JOIN image_batch a ON a.kind='teams' AND a.id=t.sofifa_id)<>16 OR
 (SELECT count(*) FROM public.players p JOIN image_batch a ON a.kind='players' AND a.id=p.sofifa_id)<>437 THEN RAISE EXCEPTION 'Catalogue mismatch'; END IF;
END $$;
UPDATE public.teams t SET crest_url=a.url FROM image_batch a WHERE a.kind='teams' AND t.sofifa_id=a.id;
UPDATE public.players p SET headshot_url=a.url FROM image_batch a WHERE a.kind='players' AND p.sofifa_id=a.id;
UPDATE game.clubs c SET crest_url=t.crest_url FROM public.teams t WHERE c.team_id=t.id AND t.sofifa_id IN(SELECT id FROM image_batch WHERE kind='teams');
COMMIT;`));
writeFileSync(new URL(`../.local-db/sofifa/assets-uploaded${production?'-production':''}.json`,import.meta.url),JSON.stringify({bucket,verifiedAt:new Date().toISOString(),assets:prepared.map(({data,...a})=>a)},null,2));
console.log(`Verified ${prepared.length} public images. ${production?'Remote Storage ready; database unchanged.':'Local catalogue and existing club crests updated.'}`);
