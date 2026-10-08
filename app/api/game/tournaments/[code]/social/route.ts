import {NextResponse} from 'next/server';
import {bearer,gameError,gameRpc,jsonBody,requestKey,UUID} from '@/lib/game-server';
type Params={params:Promise<{code:string}>};
export async function GET(request:Request,{params}:Params){try{const {code}=await params;return NextResponse.json(await gameRpc('game_social_state',{p_code:code,p_token:bearer(request)}),{headers:{'Cache-Control':'no-store'}});}catch(error){return gameError(error);}}
export async function POST(request:Request,{params}:Params){try{
 const {code}=await params,body=await jsonBody(request);
 if(typeof body.action!=='string'||!['post','like','unlike'].includes(body.action))throw new Error('INVALID_ACTION');
 if(body.postId!==undefined&&(typeof body.postId!=='string'||!UUID.test(body.postId)))throw new Error('INVALID_POST');
 if(body.action==='post'&&(typeof body.content!=='string'||body.content.trim().length<1||body.content.length>2000))throw new Error('INVALID_CONTENT');
 if(body.action!=='post'&&body.postId===undefined)throw new Error('INVALID_POST');
 return NextResponse.json(await gameRpc('game_social_command',{p_code:code,p_token:bearer(request),p_key:requestKey(request),p_action:body.action,p_content:body.action==='post'?body.content:null,p_post:body.postId||null}),{headers:{'Cache-Control':'no-store'}});
}catch(error){return gameError(error);}}
