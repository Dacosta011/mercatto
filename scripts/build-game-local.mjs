import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const env={...process.env};
for(const line of readFileSync(new URL('../.env.development.local',import.meta.url),'utf8').split(/\r?\n/)){
 const match=line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);if(match)env[match[1]]=match[2].replace(/^['"]|['"]$/g,'');
}
if(env.NEXT_PUBLIC_SUPABASE_URL!=='http://127.0.0.1:54321'||env.MERCATTO_GAME_MODEL!=='local')throw new Error('Local build requires exact local configuration');
const child=spawnSync(process.execPath,['node_modules/next/dist/bin/next','build'],{stdio:'inherit',env});
if(child.error)throw child.error;process.exitCode=child.status??1;
