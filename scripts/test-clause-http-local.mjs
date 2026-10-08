import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const base='http://127.0.0.1:3100';
async function request(path,{body,token,key,expected=200}={}) {
  if(path==='/api/game/tournaments' && body)body={...body,complete:false};
  const response=await fetch(`${base}${path}`,{
    method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{'Content-Type':'application/json','Idempotency-Key':key||randomUUID()}),...(token?{Authorization:`Bearer ${token}`}:{})},
    ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(30000),
  });
  const result=await response.json();assert.equal(response.status,expected,JSON.stringify(result));return result;
}
const a=await request('/api/game/tournaments',{body:{name:'Prueba HTTP cláusulas',displayName:'Comprador'},expected:201});
const b=await request('/api/game/tournaments',{body:{name:'Aislamiento HTTP cláusulas',displayName:'Otro'},expected:201});
const prefix=`/api/game/tournaments/${a.code}`;
let state=await request(prefix,{token:a.memberToken});
const north=state.clubs.find(c=>c.name==='Prueba Norte'),south=state.clubs.find(c=>c.name==='Prueba Sur');
const otherBefore=await request(`/api/game/tournaments/${b.code}`,{token:b.memberToken});
const seller=await request(`${prefix}/join`,{body:{displayName:'Vendedor'},expected:201});
await request(`${prefix}/club`,{body:{clubId:north.id},token:a.memberToken});
await request(`${prefix}/club`,{body:{clubId:south.id},token:seller.memberToken});
const player=south.squad.find(p=>p.name==='Defensa Sur');
await request(`${prefix}/market`,{body:{action:'clause',playerId:player.id},token:a.memberToken,expected:409});
await request(`${prefix}/market`,{body:{action:'open',kind:'summer',minutes:60},token:a.adminToken});
await request(`${prefix}/market`,{body:{action:'clause',playerId:player.id},token:b.memberToken,expected:403});
await request(`${prefix}/market`,{body:{action:'clause',playerId:player.id},token:a.adminToken,expected:403});
await request(`${prefix}/market`,{body:{action:'clause',playerId:'bad'},token:a.memberToken,expected:400});
const key=randomUUID(),body={action:'clause',playerId:player.id,amount:1,rejected:false};
const result=await request(`${prefix}/market`,{body,token:a.memberToken,key});
assert.equal(result.amount,player.clause,'Only the current contract determines the clause price');
assert.equal(typeof result.rejected,'boolean');
assert.deepEqual(await request(`${prefix}/market`,{body,token:a.memberToken,key}),result);
await request(`${prefix}/market`,{body:{action:'offer',playerId:player.id,amount:1000000},token:a.memberToken,key,expected:409});
await request(`${prefix}/market`,{body:{...body,playerId:south.squad.find(p=>p.id!==player.id).id},token:a.memberToken,key,expected:409});
state=await request(prefix,{token:a.memberToken});
assert.equal(state.clubs.find(c=>c.id===north.id).budget,result.rejected?160000000:130000000);
assert.equal(state.clubs.find(c=>c.id===south.id).budget,result.rejected?260000000:290000000);
assert.equal(state.clubs.find(c=>c.id===north.id).squad.some(p=>p.id===player.id),!result.rejected);
const market=await request(`${prefix}/market`,{token:a.memberToken});
assert.equal(market.window.clauseProtectionLimit,1);
assert.equal(market.clauseAttempts.length,1);
assert.equal(market.clauseAttempts[0].outcome,result.rejected?'rejected':'accepted');
assert.equal(market.limits.find(l=>l.clubId===north.id).used,result.rejected?0:1);
await request(`${prefix}/market`,{body,token:a.memberToken,expected:409});
await request(`${prefix}/market`,{body:{action:'close'},token:a.adminToken});
assert.deepEqual(await request(`${prefix}/market`,{body,token:a.memberToken,key}),result,'Closed-window replay preserves outcome');
assert.deepEqual(await request(`/api/game/tournaments/${b.code}`,{token:b.memberToken}),otherBefore);
console.log(`Clause HTTP test passed: ${result.rejected?'rejection without charge':'atomic purchase'}, replay, server price, authentication, quota and tournament isolation.`);
console.log('Two local test tournaments retained; no credentials printed.');
