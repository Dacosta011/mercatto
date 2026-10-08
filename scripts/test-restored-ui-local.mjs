import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const base='http://127.0.0.1:3100';
const g=await (await fetch(base+'/api/game/tournaments',{method:'POST',headers:{'Content-Type':'application/json','Idempotency-Key':randomUUID()},body:JSON.stringify({name:'Restauración UI',displayName:'Prueba',rerolls:2})})).json();
async function call(path='',method='GET',body,admin=false){const r=await fetch(`${base}/api/tournaments/${g.code}${path}`,{method,headers:{Authorization:`Bearer ${admin?g.adminToken:g.memberToken}`,'X-Mercatto-Member':g.memberToken,'X-Mercatto-Admin':g.adminToken,'Idempotency-Key':randomUUID(),'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,200,`${method} ${path}: ${JSON.stringify(d)}`);return d;}
for(const p of ['','/teams','/spin','/league','/market','/auctions','/seasons','/social/profile','/social/posts'])await call(p);
const spin=await call('/spin','PATCH');assert(spin.team);
await call('/spin','POST',{teamId:spin.team.id});
const squad=await call('/squad');assert(Array.isArray(squad.players));
await call('/squad/lineup','PUT',{formation:'4-3-3',slots:{GK:squad.players[0]?.id??null}});
assert.equal((await call('/squad/lineup')).slots.GK,squad.players[0]?.id??null);
await call('/market/start','POST',{durationHours:1},true);
assert.equal((await call('/market')).status,'active');
for(const p of ['/expenses','/market/history','/icons'])await call(p);
console.log('Original UI compatibility passed: authenticated views, server draw, squad draft, market opening and finances.');

