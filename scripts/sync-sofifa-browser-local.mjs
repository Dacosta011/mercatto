import {spawnSync} from 'node:child_process';
import {existsSync,mkdirSync,readFileSync,writeFileSync,renameSync} from 'node:fs';
import {homedir} from 'node:os';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {assertLocal} from './db-local.mjs';
import {validateSnapshot,importSnapshot,configureLocalCatalogue} from './import-sofifa-local.mjs';

if(process.argv.slice(2).some(a=>a!=='--apply'))throw new Error('Usage: node scripts/sync-sofifa-browser-local.mjs [--apply]');
assertLocal();
const root=fileURLToPath(new URL('../',import.meta.url));
const runtime=resolve(homedir(),'.cache/codex-runtimes/codex-primary-runtime/dependencies');
const require=createRequire(import.meta.url);
let chromium;
try { ({chromium}=require('playwright')); }
catch { ({chromium}=require(resolve(runtime,'node/node_modules/playwright'))); }
const bundled=resolve(runtime,'python/python.exe');
const python=process.env.MERCATTO_PYTHON||(existsSync(bundled)?bundled:process.platform==='win32'?'py':'python3');
const directory=resolve(root,`.local-db/sofifa/browser-${Date.now()}`);
mkdirSync(directory,{recursive:true});
const teams=JSON.parse(readFileSync(resolve(root,'scripts/sofifa-teams.json'),'utf8'));
function status(message) {
  console.log(message);
  writeFileSync(resolve(directory,'status.json'),JSON.stringify({at:new Date().toISOString(),message},null,2));
}
function parse(path,team,revision) {
  const args=[resolve(root,'scripts/sofifa-browser-parse.py'),path];
  if(team)args.push(String(team.id),String(revision),team.name);
  const run=spawnSync(python,args,{encoding:'utf8',maxBuffer:8_000_000});
  if(run.error)throw run.error;
  if(run.status!==0)throw new Error(run.stderr||run.stdout||'Capture validation failed');
  return JSON.parse(run.stdout);
}
const channel=process.env.MERCATTO_BROWSER_CHANNEL||'chrome';
if(!['chrome','msedge'].includes(channel))throw new Error('MERCATTO_BROWSER_CHANNEL must be chrome or msedge');
const browser=await chromium.launch({channel,headless:false,chromiumSandbox:true});
const context=await browser.newContext({locale:'en-US',viewport:null});
const page=await context.newPage();
let written=false;
async function capture(url,name) {
  status(`Abriendo ${url}`);
  await page.goto(url,{waitUntil:'domcontentloaded',timeout:60_000});
  const deadline=Date.now()+10*60_000;
  let announced=false;
  while(Date.now()<deadline) {
    if(page.isClosed())throw new Error('Browser window closed before completing the batch.');
    if(!['sofifa.com','www.sofifa.com'].includes(new URL(page.url()).hostname))throw new Error('Unexpected navigation destination.');
    const ready=await page.locator('select#select-roster, select#select-version').count();
    const rows=await page.locator('tr a[href*="/player/"]').count();
    if(ready && rows>=18) {
      const html=await page.content();
      if(Buffer.byteLength(html)>8_000_000)throw new Error('Page too large.');
      const path=resolve(directory,`${name}.html`);
      writeFileSync(path,html);
      return {path,receipt:{url:page.url(),sha256:createHash('sha256').update(html).digest('hex')}};
    }
    if(!announced) {
      status('Esperando la plantilla. Si Chrome muestra una verificación, complétala manualmente; el script continuará solo (máximo 10 minutos).');
      announced=true;
    }
    await delay(2000);
  }
  throw new Error('Verification/page readiness timed out after 10 minutes.');
}
try {
  const entry=`https://sofifa.com/team/${teams[0].id}/?hl=en-US`;
  const initial=await capture(entry,'latest-start');
  const revision=parse(initial.path).latest;
  status(`Última edición detectada: ${revision}`);
  const snapshot={source:'sofifa',revision,teams:[],receipts:[]};
  for(const team of teams) {
    await delay(2000);
    const captured=await capture(`https://sofifa.com/team/${team.id}/${revision}/?hl=en-US`,`team-${team.id}`);
    const parsed=parse(captured.path,team,revision);
    snapshot.teams.push(parsed.team);
    snapshot.receipts.push(captured.receipt);
    status(`${snapshot.teams.length}/16: ${team.name}, ${parsed.team.players.length} jugadores validados.`);
  }
  const final=await capture(entry,'latest-end');
  if(parse(final.path).latest!==revision)throw new Error('Latest edition changed during download; run again.');
  snapshot.fetchedAt=new Date().toISOString();
  validateSnapshot(snapshot);
  const output=resolve(directory,'snapshot.json');
  writeFileSync(`${output}.tmp`,JSON.stringify(snapshot,null,2));
  renameSync(`${output}.tmp`,output);
  console.log(importSnapshot(snapshot,{apply:process.argv.includes('--apply')}));
  written=process.argv.includes('--apply');
  if(written)configureLocalCatalogue();
  status(written?'Importación local completada: 16 clubes.':'Vista previa validada; base sin cambios.');
} catch(error) {
  status(`${written?'Importación realizada; falló un paso posterior':'Importación cancelada; base sin cambios'}: ${error.message}`);
  process.exitCode=1;
} finally {
  await browser.close();
}
