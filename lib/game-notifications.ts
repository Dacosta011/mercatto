import 'server-only';
import {NextResponse} from 'next/server';
import {localGameClient,UUID} from './game-server';

export function validPushEndpoint(value:unknown):value is string {
 if(typeof value!=='string'||value.length>2048)return false;
 try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&(
 u.hostname==='fcm.googleapis.com'||u.hostname==='updates.push.services.mozilla.com'||u.hostname.endsWith('.push.services.mozilla.com')||u.hostname==='web.push.apple.com'||u.hostname.endsWith('.notify.windows.com'));}catch{return false;}
}
export async function gameNotificationRoute(request:Request,code:string,token:string,body:Record<string,unknown>){
 const db=localGameClient(),{data:s,error}=await db.rpc('game_state',{p_code:code,p_token:token});if(error)throw error;
 const json=(data:unknown)=>NextResponse.json(data,{headers:{'Cache-Control':'no-store'}});
 if(new URL(request.url).pathname.endsWith('/push/subscribe')){
  if(!validPushEndpoint(body.endpoint))throw Error('INVALID_PUSH_ENDPOINT');
  if(request.method==='DELETE'){const {error}=await db.from('push_subscriptions').delete().eq('member_id',s.memberId).eq('endpoint',body.endpoint);if(error)throw error;return json({ok:true});}
  if(request.method!=='POST')throw Error('INVALID_METHOD');
  for(const [key,length] of [['p256dh',65],['auth',16]] as const){const value=body[key];if(typeof value!=='string'||! /^[A-Za-z0-9_-]+={0,2}$/.test(value)||Buffer.from(value,'base64url').length!==length)throw Error('INVALID_PUSH_KEY');}
  const {error}=await db.from('push_subscriptions').upsert({member_id:s.memberId,endpoint:body.endpoint,p256dh:body.p256dh,auth:body.auth},{onConflict:'member_id,endpoint'});if(error)throw error;
  return json({ok:true});
 }
 if(request.method==='GET'){
  const url=new URL(request.url),limit=Number(url.searchParams.get('limit')||30),offset=Number(url.searchParams.get('offset')||0);
  if(!Number.isInteger(limit)||limit<1||limit>100||!Number.isInteger(offset)||offset<0||offset>10000)throw Error('INVALID_PAGINATION');
  const {data,count,error}=await db.from('notifications').select('*',{count:'exact'}).eq('member_id',s.memberId).eq('tournament_id',s.id).order('created_at',{ascending:false}).range(offset,offset+limit-1);if(error)throw error;
  const unread=await db.from('notifications').select('id',{count:'exact',head:true}).eq('member_id',s.memberId).eq('tournament_id',s.id).eq('read',false);if(unread.error)throw unread.error;
  return json({notifications:data,total:count,unreadCount:unread.count});
 }
 if(request.method!=='PATCH')throw Error('INVALID_METHOD');
 let query=db.from('notifications').update({read:true}).eq('member_id',s.memberId).eq('tournament_id',s.id);
 if(body.all!==true){if(!Array.isArray(body.ids)||body.ids.length>100||body.ids.some(x=>typeof x!=='string'||!UUID.test(x)))throw Error('INVALID_IDS');query=query.in('id',body.ids);}
 const result=await query;if(result.error)throw result.error;return json({ok:true});
}
