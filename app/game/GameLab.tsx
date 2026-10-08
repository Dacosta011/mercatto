'use client';
import { useEffect, useState } from 'react';
import type { GameState, GameMarket, GameCompetition } from '@/lib/game-types';
import MarketPanel from './MarketPanel';
import CompetitionPanel from './CompetitionPanel';
import SocialPanel from './SocialPanel';

interface Session { code: string; memberToken: string; adminToken?: string; displayName?: string }
const money = (value: number) => new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'COP', maximumFractionDigits: 0 }).format(value);

export default function GameLab() {
  const [name, setName] = useState('Torneo de prueba');
  const [displayName, setDisplayName] = useState('David');
  const [code, setCode] = useState('');
  const [token, setToken] = useState('');
  const [adminAccess,setAdminAccess]=useState('');
  const [session, setSession] = useState<Session | null>(null);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [state, setState] = useState<GameState | null>(null);
  const [market, setMarket] = useState<GameMarket | null>(null);
  const [competition,setCompetition]=useState<GameCompetition|null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');
  // A failed network request retains its key. A changed action gets a fresh key.
  const [retry, setRetry] = useState<{ signature: string; key: string } | null>(null);

  useEffect(() => {
    if (!session || pending) return;
    const controller = new AbortController();
    let active = true;
    let refreshing = false;
    const current = session;
    async function refresh() {
      if (refreshing) return;
      refreshing = true;
      try {
        const base = `/api/game/tournaments/${encodeURIComponent(current.code)}`;
        const options = { headers: { Authorization: `Bearer ${current.memberToken}` }, cache: 'no-store' as const, signal: controller.signal };
        const responses = await Promise.all([fetch(base, options), fetch(`${base}/market`, options),fetch(`${base}/competition`,options)]);
        if (responses.some(response => !response.ok)) return;
        const [nextState, nextMarket,nextCompetition] = await Promise.all(responses.map(response => response.json()));
        if (active) { setState(nextState); setMarket(nextMarket);setCompetition(nextCompetition); }
      } catch {
        // A temporary connection failure leaves the last snapshot visible.
      } finally { refreshing = false; }
    }
    const timer = setInterval(refresh, 10000);
    return () => { active = false; controller.abort(); clearInterval(timer); };
  }, [session, pending]);

  async function load(current: Session) {
    const response = await fetch(`/api/game/tournaments/${encodeURIComponent(current.code)}`, { headers: { Authorization: `Bearer ${current.memberToken}` }, cache: 'no-store' });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'No se pudo cargar el torneo.');
    setState(data);
    const marketResponse = await fetch(`/api/game/tournaments/${encodeURIComponent(current.code)}/market`, { headers: { Authorization: `Bearer ${current.memberToken}` }, cache: 'no-store' });
    const marketData = await marketResponse.json();
    if (!marketResponse.ok) throw new Error(marketData.error || 'No se pudo cargar el mercado.');
    setMarket(marketData);
    const competitionResponse=await fetch(`/api/game/tournaments/${encodeURIComponent(current.code)}/competition`,{headers:{Authorization:`Bearer ${current.memberToken}`},cache:'no-store'});
    const competitionData=await competitionResponse.json();if(!competitionResponse.ok)throw new Error(competitionData.error);setCompetition(competitionData);
    return data as GameState;
  }
  async function action(path: string, body: object, auth?: string) {
    const signature = JSON.stringify([path, body, auth]);
    const key = retry?.signature === signature ? retry.key : crypto.randomUUID();
    setRetry({ signature, key });
    const response = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key, ...(auth ? { Authorization: `Bearer ${auth}` } : {}) }, body: JSON.stringify(body) });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'No se pudo completar la operación.');
    setRetry(null);
    return data;
  }
  async function run(work: () => Promise<unknown>) {
    setPending(true); setError('');
    try { await work(); } catch (err) { setError(err instanceof Error ? err.message : 'Error inesperado.'); }
    finally { setPending(false); }
  }
  async function connect(current: Session) {
    setSession(current); setCode(current.code); setToken(current.memberToken);
    setState(null); setMarket(null); setCompetition(null);
    const loaded = await load(current);
    const saved = { ...current, displayName: loaded.members.find(m=>m.id===loaded.memberId)?.name };
    setSession(saved);
    setSessions(previous=>[...previous.filter(s=>s.code!==saved.code || s.memberToken!==saved.memberToken),saved]);
  }
  const input = 'w-full rounded-lg border border-white/20 bg-white/5 px-3 py-2';
  const button = 'rounded-lg bg-emerald-600 px-4 py-2 text-white disabled:opacity-40';
  return <main className="mx-auto max-w-5xl space-y-6 p-6 text-white">
    <div><h1 className="text-3xl font-bold">Clubes · prueba local</h1><p className="mt-2 text-white/60">Crea un torneo y prueba su patrimonio con clubes ficticios. Cada club conserva su plantilla y presupuesto al cambiar de administrador o temporada.</p></div>
    {error && <p role="alert" className="rounded-lg bg-red-950 p-3">{error}</p>}
    <div className="grid gap-4 md:grid-cols-2">
      <section className="space-y-3 rounded-xl border border-white/15 p-4"><h2 className="font-semibold">Crear torneo</h2>
        <label className="block">Nombre del torneo<input className={input} maxLength={80} value={name} onChange={e=>setName(e.target.value)} /></label>
        <label className="block">Tu nombre<input className={input} maxLength={40} value={displayName} onChange={e=>setDisplayName(e.target.value)} /></label>
        <button disabled={pending} className={button} onClick={()=>run(async()=>{ const data = await action('/api/game/tournaments',{name,displayName,complete:true}); await connect(data); })}>Crear y entrar</button>
      </section>
      <section className="space-y-3 rounded-xl border border-white/15 p-4"><h2 className="font-semibold">Entrar a un torneo</h2>
        <label className="block">Código<input className={input} value={code} onChange={e=>setCode(e.target.value.trim())} /></label>
        <p className="text-sm text-white/60">Para un participante nuevo, usa tu nombre del formulario de creación.</p>
        <button disabled={pending || !code} className={button} onClick={()=>run(async()=>{ const data = await action(`/api/game/tournaments/${encodeURIComponent(code)}/join`,{displayName}); await connect(data); })}>Unirse como participante</button>
        <label className="block">Token de participante<input className={input} type="password" value={token} onChange={e=>setToken(e.target.value.trim())} /></label>
        <label className="block">Token de administrador (opcional)<input className={input} type="password" value={adminAccess} onChange={e=>setAdminAccess(e.target.value.trim())}/></label>
        <button disabled={pending || !token || !code} className={button} onClick={()=>run(()=>connect({code,memberToken:token,...(adminAccess?{adminToken:adminAccess}:{})}))}>Recuperar acceso</button>
        {sessions.length>0 && <label className="block">Cambiar participante de prueba<select className={input} disabled={pending} value={sessions.findIndex(s=>s.memberToken===session?.memberToken && s.code===session?.code)} onChange={e=>{const saved=sessions[Number(e.target.value)]; if(saved) run(()=>connect(saved));}}><option value={-1}>Selecciona un acceso guardado</option>{sessions.map((saved,index)=><option className="bg-[#171b20]" key={index} value={index}>{saved.displayName} · {saved.code.slice(0,12)}{saved.adminToken?' · administrador':''}</option>)}</select></label>}
      </section>
    </div>
    {session && <section className="space-y-2 rounded-xl border border-white/15 p-4">
      <p>Código: <span className="break-all font-mono">{session.code}</span></p>
      <details><summary>Guardar mis credenciales de prueba</summary><p className="mt-2 break-all font-mono text-sm">Participante: {session.memberToken}</p>{session.adminToken && <p className="break-all font-mono text-sm">Administrador: {session.adminToken}</p>}</details>
      <p className="text-sm text-white/60">Guarda las credenciales si quieres volver después de recargar la página.</p>
      <div className="flex flex-wrap gap-3"><button disabled={pending} className={button} onClick={()=>run(()=>load(session))}>Actualizar</button>
        {session.adminToken && !competition?.enabled && <button disabled={pending} className={button} onClick={()=>run(async()=>{ await action(`/api/game/tournaments/${session.code}/season`,{},session.adminToken); await load(session); })}>Simular siguiente temporada</button>}
      </div>
    </section>}
    {state && session && <><h2 className="text-xl font-semibold">{state.name} · Temporada {state.season}</h2><p className="text-sm text-white/60">{state.members.map(m=>m.name).join(' · ')}</p><div className="grid gap-4 md:grid-cols-3">
      {state.clubs.map(club=><section key={club.id} className="space-y-3 rounded-xl border border-white/15 p-4">
        <h3 className="text-xl font-semibold">{club.name}</h3><p>Administrador: {club.manager || 'Sin asignar'}</p><p>Presupuesto: {money(club.budget)}</p><p className="text-sm text-white/60">Disponible: {money(club.budget-club.reserved)}</p>
        <ul className="space-y-2">{club.squad.map(player=><li key={player.id}>{player.name} · {player.ovr} · {player.position}<div className="text-sm text-white/60">{money(player.price)}</div></li>)}</ul>
        {club.squad.length===0 && <p className="text-white/60">Sin jugadores.</p>}
        <button disabled={pending || (competition?.enabled && competition.phase!=='assignment') || (club.memberId!==null && club.memberId!==state.memberId)} className={button} onClick={()=>run(async()=>{ await action(`/api/game/tournaments/${session.code}/club`,{clubId:club.id},session.memberToken); await load(session); })}>{club.memberId===state.memberId ? 'Mi club' : 'Administrar este club'}</button>
      </section>)}
    </div></>}
    {state && session && competition && <CompetitionPanel state={state} competition={competition} market={market} admin={!!session.adminToken} pending={pending} onCommand={(body,admin)=>run(async()=>{
      await action(`/api/game/tournaments/${session.code}/competition`,body,admin?session.adminToken:session.memberToken);
      if((body as {action:string}).action==='leave'){setSession(null);setState(null);setMarket(null);setCompetition(null);setToken('');setSessions(previous=>previous.filter(s=>s.memberToken!==session.memberToken));return;}
      await load(session);
    })}/>}
    {state && session && market && <MarketPanel finished={competition?.phase==='finished'} complete={!!competition?.enabled} state={state} market={market} admin={!!session.adminToken} pending={pending} onCommand={(body,admin)=>run(async()=>{
      await action(`/api/game/tournaments/${session.code}/market`,body,admin ? session.adminToken : session.memberToken);
      await load(session);
    })} />}
    {state&&session&&<SocialPanel code={session.code} token={session.memberToken} pending={pending} onCommand={async body=>{let success=false;await run(async()=>{await action(`/api/game/tournaments/${session.code}/social`,body,session.memberToken);success=true;});return success;}}/>}
  </main>;
}
