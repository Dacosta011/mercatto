'use client';
import {useEffect,useState} from 'react';
type Post={id:string;author:string;content:string|null;imageUrl:string|null;parentId:string|null;createdAt:string;likes:number;liked:boolean};
export default function SocialPanel({code,token,pending,onCommand}:{code:string;token:string;pending:boolean;onCommand:(body:object)=>Promise<boolean>}){
 const [posts,setPosts]=useState<Post[]>([]),[content,setContent]=useState(''),[reply,setReply]=useState<string|null>(null),[error,setError]=useState('');
 useEffect(()=>{
  if(pending)return;const controller=new AbortController();let busy=false;
  async function refresh(){if(busy)return;busy=true;try{const r=await fetch(`/api/game/tournaments/${code}/social`,{headers:{Authorization:`Bearer ${token}`},cache:'no-store',signal:controller.signal});const data=await r.json();if(!r.ok)throw new Error(data.error);if(!controller.signal.aborted){setPosts(data);setError('');}}catch(err){if(!controller.signal.aborted)setError(err instanceof Error?err.message:'No se pudo actualizar el muro.');}finally{busy=false;}}
  void refresh();const interval=setInterval(refresh,10000);return()=>{controller.abort();clearInterval(interval);};
 },[code,token,pending]);
 return <section className="space-y-3 rounded-xl border border-white/15 p-4"><h2 className="text-xl font-semibold">Muro del torneo</h2>{error&&<p role="alert">{error}</p>}<label className="block">{reply?'Responder a publicación':'Nueva publicación'}<textarea maxLength={2000} className="mt-2 w-full rounded-lg border border-white/20 bg-white/5 p-3" value={content} onChange={e=>setContent(e.target.value)}/></label><button disabled={pending||!content.trim()} className="rounded-lg bg-emerald-600 px-3 py-2 disabled:opacity-40" onClick={async()=>{if(await onCommand({action:'post',content,...(reply?{postId:reply}:{})})){setContent('');setReply(null);}}}>Publicar en este torneo</button>{reply&&<button className="ml-3" onClick={()=>setReply(null)}>Cancelar respuesta</button>}
 {posts.map(p=><article key={p.id} className="space-y-2 rounded-lg bg-white/5 p-3"><p>{p.author} · {new Date(p.createdAt).toLocaleString('es-CO')}{p.parentId?' · Respuesta':''}</p><p className="whitespace-pre-wrap">{p.content}</p><button disabled={pending} className="mr-4" onClick={()=>onCommand({action:p.liked?'unlike':'like',postId:p.id})}>{p.liked?'Quitar me gusta':'Me gusta'} · {p.likes}</button><button disabled={pending} onClick={()=>setReply(p.id)}>Responder</button></article>)}</section>;
}
