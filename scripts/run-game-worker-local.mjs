import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

export async function expireLocalMarkets() {
  const lines=readFileSync(new URL('../.env.development.local',import.meta.url),'utf8').split(/\r?\n/);
  const env=Object.fromEntries(lines.filter(line=>/^[A-Z_]+=/.test(line)).map(line=>{
    const index=line.indexOf('='); return [line.slice(0,index),line.slice(index+1).trim()];
  }));
  if(env.MERCATTO_GAME_MODEL!=='local' || env.NEXT_PUBLIC_SUPABASE_URL!=='http://127.0.0.1:54321' || !env.SUPABASE_SERVICE_ROLE_KEY) {
    throw new Error('Worker requires the exact local Supabase configuration');
  }
  const response=await fetch('http://127.0.0.1:54321/rest/v1/rpc/game_expire_markets',{
    method:'POST',headers:{'Content-Type':'application/json',apikey:env.SUPABASE_SERVICE_ROLE_KEY,Authorization:`Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`},
    body:JSON.stringify({p_limit:100}),signal:AbortSignal.timeout(10000),
  });
  if(!response.ok) throw new Error(`Local worker RPC failed with HTTP ${response.status}`);
  const result=await response.json();
  if(!Number.isInteger(result.closed) || result.closed<0) throw new Error('Unexpected worker result');
  return result;
}
if(process.argv[1] && resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  if(process.argv.length>3 || (process.argv[2] && process.argv[2]!=='--once')) throw new Error('Use: node scripts/run-game-worker-local.mjs [--once]');
  let busy=false;
  async function tick() {
    if(busy) return;
    busy=true;
    try { const result=await expireLocalMarkets(); if(result.closed || result.settled || result.votesClosed || result.forfeits || process.argv[2]==='--once') console.log(`Local worker: ${result.closed} markets closed; ${result.settled ?? 0} auctions settled; ${result.votesClosed ?? 0} votes closed; ${result.forfeits ?? 0} forfeits.`); }
    catch(error){ console.error(error.message); if(process.argv[2]==='--once') process.exitCode=1; }
    finally { busy=false; }
  }
  await tick();
  if(process.argv[2]!=='--once') {
    console.log('Local market worker running every 15 seconds. Ctrl+C stops it.');
    const timer=setInterval(tick,15000);
    for(const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>{clearInterval(timer);});
  }
}
