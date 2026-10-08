import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';import {createHash} from 'node:crypto';
import {assertLocal,sql} from './db-local.mjs';import {readEnv} from './db-production.mjs';
assertLocal();const env=readEnv('.env.development.local'),base='http://127.0.0.1:54321';
if(env.NEXT_PUBLIC_SUPABASE_URL!==base)throw Error('Local Storage only');
const icons=JSON.parse(readFileSync('.local-db/icons/original-icons.json','utf8')),headers={apikey:env.SUPABASE_SERVICE_ROLE_KEY,Authorization:'Bearer '+env.SUPABASE_SERVICE_ROLE_KEY};
mkdirSync('.local-db/icons/images',{recursive:true});const assets=[];let cursor=0;
await Promise.all(Array.from({length:4},async()=>{while(cursor<icons.length){
 const p=icons[cursor++],u=new URL(p.headshot_url);
 if(u.protocol!=='https:'||!['cmtracker.fra1.cdn.digitaloceanspaces.com','cdn3.futbin.com'].includes(u.hostname))throw Error('Unexpected original image host');
 let bytes;
 for(let attempt=0;;attempt++){try{const r=await fetch(u,{signal:AbortSignal.timeout(30000)});if(!r.ok)throw Error('Original icon image HTTP '+r.status);bytes=Buffer.from(await r.arrayBuffer());break;}catch(e){if(attempt===2)throw e;}}
 if(!bytes.subarray(0,8).equals(Buffer.from([137,80,78,71,13,10,26,10]))||bytes.length>5000000)throw Error('Invalid icon PNG');
 const hash=createHash('sha256').update(bytes).digest('hex'),key='icons/'+p.id+'/'+hash+'.png',url=base+'/storage/v1/object/public/sofifa-assets/'+key;
 writeFileSync('.local-db/icons/images/'+p.id+'.png',bytes);
 const upload=await fetch(base+'/storage/v1/object/sofifa-assets/'+key,{method:'POST',headers:{...headers,'Content-Type':'image/png','x-upsert':'true'},body:bytes});if(!upload.ok)throw Error('Local upload HTTP '+upload.status);
 const publicImage=await fetch(url);if(!publicImage.ok||createHash('sha256').update(Buffer.from(await publicImage.arrayBuffer())).digest('hex')!==hash)throw Error('Image verification failed');
 assets.push({id:p.id,name:p.name,url,key,hash}); 
}}));
const lit=s=>"'"+s.replaceAll("'","''")+"'";
sql('BEGIN;'+assets.map(a=>`UPDATE public.players SET headshot_url=${lit(a.url)} WHERE id=${lit(a.id)} AND is_icon;`).join('\n')+'COMMIT;');
writeFileSync('.local-db/icons/assets.json',JSON.stringify(assets,null,2));console.log('52 original icon images restored and verified in local Storage. Remote unchanged.');
