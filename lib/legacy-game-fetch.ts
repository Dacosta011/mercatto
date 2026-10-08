import { localGameUI } from './game-local-mode';
import { getMemberToken, getAdminToken } from './tokenStorage';

// Keep the original screens' request contracts. Only the local transport changes.
export async function legacyGameFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const path=typeof input==='string'?input:input instanceof URL?input.href:input.url;
  if(!localGameUI||!path.startsWith('/api/tournaments/'))return globalThis.fetch(input,init);
  const code=decodeURIComponent(path.split('/')[3]);
  const headers=new Headers(init?.headers);
  const member=getMemberToken(code),admin=getAdminToken(code);
  if(member){headers.set('X-Mercatto-Member',member);if(!headers.has('Authorization'))headers.set('Authorization',`Bearer ${member}`);}
  if(admin)headers.set('X-Mercatto-Admin',admin);
  const method=(init?.method||'GET').toUpperCase(),mutates=!['GET','HEAD'].includes(method);
  const storageKey=`mercatto:legacy-request:${method}:${path}:${typeof init?.body==='string'?init.body:''}`;
  if(mutates){const key=sessionStorage.getItem(storageKey)||crypto.randomUUID();sessionStorage.setItem(storageKey,key);headers.set('Idempotency-Key',key);}
  const response=await globalThis.fetch(input,{...init,headers,cache:'no-store'});
  if(mutates&&response.status<500)sessionStorage.removeItem(storageKey);
  if(mutates&&response.ok)window.dispatchEvent(new Event('mercatto:game-change'));
  return response;
}
