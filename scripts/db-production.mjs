import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

export function readEnv(path){
 const result={};
 for(const line of readFileSync(path,'utf8').replace(/^\uFEFF/,'').split(/\r?\n/)){
  const m=line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);if(m)result[m[1]]=m[2].trim().replace(/^['"]|['"]$/g,'');
 }
 return result;
}
export function productionConfig(){
 const env=readEnv(new URL('../.env.production.local',import.meta.url));
 const original=readEnv(new URL('../.env.local',import.meta.url));
 const endpoint=new URL(original.NEXT_PUBLIC_SUPABASE_URL);
 if(endpoint.protocol!=='https:'||!endpoint.hostname.endsWith('.supabase.co'))throw new Error('Expected hosted Supabase endpoint');
 const ref=endpoint.hostname.split('.')[0];
 let db;try{db=new URL(env.SUPABASE_DB_URL);}catch{throw new Error('Invalid SUPABASE_DB_URL; expected PostgreSQL connection URI');}
 const user=decodeURIComponent(db.username);
 if(decodeURIComponent(db.password).includes('YOUR-PASSWORD'))throw new Error('Replace [YOUR-PASSWORD] in SUPABASE_DB_URL with the actual database password');
 const direct=db.hostname===`db.${ref}.supabase.co`;
 const pooler=db.hostname.endsWith('.pooler.supabase.com')&&user===`postgres.${ref}`;
 if(!['postgres:','postgresql:'].includes(db.protocol)||(!direct&&!pooler)||!db.password||db.pathname!=='/postgres')throw new Error('Database must match the existing Supabase project and postgres database');
 if(pooler&&db.port==='6543')throw new Error('Use the session pooler on port 5432, not transaction pooler 6543');
 if(!env.SUPABASE_SERVICE_ROLE_KEY)throw new Error('Missing remote service key');
 return {env,endpoint:endpoint.origin,ref,db,user};
}
export function remoteCommand(program,args,input=''){
 const {db,user}=productionConfig();
 const password=decodeURIComponent(db.password);
 if(/[\r\n]/.test(password))throw new Error('Invalid password format');
 const result=spawnSync('docker',['exec','-i','supabase_db_mercatto','sh','-c',
  'IFS= read -r PGPASSWORD; export PGPASSWORD; export PGSSLMODE=require; export PGCONNECT_TIMEOUT=15; exec "$@"',
  'sh',program,'-h',db.hostname,'-p',db.port||'5432','-U',user,'-d','postgres',...args],
  {input:password+'\n'+input,encoding:'utf8',maxBuffer:256*1024*1024});
 if(result.error)throw new Error(`Could not run PostgreSQL client: ${result.error.code}`);
 if(result.status!==0)throw new Error((result.stderr||'PostgreSQL failed').split(password).join('[redacted]'));
 return result.stdout;
}
export const remoteSql=query=>remoteCommand('psql',['-X','-v','ON_ERROR_STOP=1','-At'],query);
export function remoteBackup(){
 const directory=new URL('../.local-db/production/',import.meta.url);mkdirSync(directory,{recursive:true});
 const path=new URL(`backup-${Date.now()}.sql`,directory);
 const dump=remoteCommand('pg_dump',['--no-owner','--no-privileges']);
 if(!dump.includes('PostgreSQL database dump complete'))throw new Error('Incomplete backup');
 writeFileSync(path,dump);
 console.log(`Remote backup saved: ${fileURLToPath(path)}`);
 return path;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
 if(process.argv[2]==='inspect')console.log(remoteSql(`SELECT jsonb_build_object('database',current_database(),'version',current_setting('server_version'),'gameSchema',to_regnamespace('game') IS NOT NULL,'migrationTable',to_regclass('supabase_migrations.schema_migrations') IS NOT NULL,'teams',(SELECT count(*) FROM public.teams),'players',(SELECT count(*) FROM public.players),'tournaments',(SELECT count(*) FROM public.tournaments));`));
 else if(process.argv[2]==='backup')remoteBackup();
 else throw new Error('Usage: node scripts/db-production.mjs inspect|backup');
}
