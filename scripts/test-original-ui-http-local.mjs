import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const base='http://127.0.0.1:3100';
async function post(path,body,key=randomUUID(),expected=201){
 const response=await fetch(base+path,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify(body),signal:AbortSignal.timeout(30000)});
 const result=await response.json();assert.equal(response.status,expected,JSON.stringify(result));return result;
}
const key=randomUUID(),body={name:'Opciones UI original',displayName:'UI',rerolls:3,maxTransfers:7,clauseProtection:2};
const game=await post('/api/game/tournaments',body,key);
assert.deepEqual(await post('/api/game/tournaments',body,key),game);
const joined=await post(`/api/game/tournaments/${game.code}/join`,{displayName:'Invitado UI'});
assert.equal(joined.tournamentName,body.name);assert.equal(joined.displayName,'Invitado UI');
await post('/api/game/tournaments',{...body,rerolls:4},key,409);
await post('/api/game/tournaments',{...body,maxTransfers:0},randomUUID(),400);
const options={headers:{Authorization:`Bearer ${game.memberToken}`}};
const competition=await (await fetch(`${base}/api/game/tournaments/${game.code}/competition`,options)).json();
assert.equal(competition.rules.rerolls,3);
const response=await fetch(`${base}/api/game/tournaments/${game.code}/market`,{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':randomUUID(),Authorization:`Bearer ${game.adminToken}`},body:JSON.stringify({action:'open',kind:'summer',minutes:60})});
assert.equal(response.status,200,await response.text());
const market=await (await fetch(`${base}/api/game/tournaments/${game.code}/market`,options)).json();
assert.equal(market.window.purchaseLimit,7);assert.equal(market.window.clauseProtectionLimit,2);
for(const path of ['/','/create','/join','/rejoin','/roulette/'+game.code,'/lobby/'+game.code,'/squad','/calendar','/table','/market','/subastas','/feed','/market-history','/magic-link','/tragaperras']){
 const response=await fetch(base+path,{redirect:'manual',signal:AbortSignal.timeout(30000)});
 assert.equal(response.status,200,`${path} must serve the original UI, not redirect to /game`);
 const html=await response.text();assert(!html.includes('Clubes · prueba local'),`${path} must not mount the laboratory`);
}
assert.equal((await fetch(base+'/api/tournaments')).status,410);
console.log('Original UI routes and atomic creation settings passed: local only, retry consistent, configured market limits, legacy writes blocked.');
