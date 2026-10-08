import 'server-only';
import webPush from 'web-push';
import type {SupabaseClient} from '@supabase/supabase-js';
import {validPushEndpoint} from './game-notifications';
let running=false;
export async function flushGamePush(db:SupabaseClient){
 // Local regression never sends messages to external push services.
 if(running||process.env.MERCATTO_GAME_MODEL!=='clubs'||!process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY||!process.env.VAPID_PRIVATE_KEY)return;
 running=true;
 try{
  webPush.setVapidDetails(process.env.VAPID_EMAIL||'mailto:mercatto@app.com',process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY,process.env.VAPID_PRIVATE_KEY);
  const {data:pending,error}=await db.rpc('game_claim_push',{p_limit:5});if(error)throw error;
  for(const n of pending||[]){
   const {data:subs,error}=await db.from('push_subscriptions').select('id,endpoint,p256dh,auth').eq('member_id',n.member_id);if(error)throw error;
   let success=true;
   for(const sub of subs||[]){
    if(!validPushEndpoint(sub.endpoint)){success=false;continue;}
    try{await webPush.sendNotification({endpoint:sub.endpoint,keys:{p256dh:sub.p256dh,auth:sub.auth}},JSON.stringify({title:n.title,body:n.body||'',icon:'/icon',tag:n.id}),{timeout:3000,TTL:3600});}
    catch(e){const status=(e as {statusCode?:number}).statusCode;if(status===404||status===410){const removed=await db.from('push_subscriptions').delete().eq('id',sub.id);if(removed.error)success=false;}else success=false;}
   }
   if(success){const updated=await db.from('notifications').update({push_sent_at:new Date().toISOString()}).eq('id',n.id);if(updated.error)throw updated.error;}
  }
 }catch{console.error('[game push] delivery deferred');}finally{running=false;}
}
