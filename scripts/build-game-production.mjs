import {spawnSync} from 'node:child_process';
import {readEnv} from './db-production.mjs';

const settings=readEnv(new URL('../.env.vercel.production',import.meta.url));
if(settings.MERCATTO_GAME_MODEL!=='clubs'||settings.NEXT_PUBLIC_MERCATTO_GAME_MODEL!=='clubs'||!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(settings.NEXT_PUBLIC_SUPABASE_URL))throw new Error('Expected hosted club configuration');
const env={...process.env,...settings,MERCATTO_GAME_TEAM_IDS:'',MERCATTO_GAME_FREE_PLAYER_IDS:''};
const child=spawnSync(process.execPath,['node_modules/next/dist/bin/next','build'],{stdio:'inherit',env});
if(child.error)throw child.error;
process.exitCode=child.status??1;
