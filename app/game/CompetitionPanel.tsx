'use client';
import { useState } from 'react';
import type { GameCompetition,GameState,GameMarket } from '@/lib/game-types';
const money=(n:number)=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'EUR',maximumFractionDigits:0}).format(n);
const button='rounded-lg bg-emerald-600 px-3 py-2 disabled:opacity-40';
const input='rounded-lg border border-white/20 bg-white/5 px-3 py-2';
type Props={state:GameState;competition:GameCompetition;market:GameMarket|null;admin:boolean;pending:boolean;view?:'all'|'lobby'|'squad'|'spin'|'votes'|'calendar'|'table';onCommand:(body:object,admin?:boolean)=>Promise<void>};
export default function CompetitionPanel({state,competition:c,market,admin,pending,onCommand,view='all'}:Props){
 const show=(...views:string[])=>view==='all'||views.includes(view);
 const [season,setSeason]=useState('');
 const [scores,setScores]=useState<Record<string,{home:number;away:number}>>({});
 const [cards,setCards]=useState<Record<string,Record<string,string>>>({});
 const [selections,setSelections]=useState<Record<string,string[]>>({});
 const [replacements,setReplacements]=useState<Record<string,string>>({});
 const [settings,setSettings]=useState({minSquad:c.rules?.min_squad??0,maxSquad:c.rules?.max_squad??35,dailyBasic:c.rules?.daily_basic??2,dailyPremium:c.rules?.daily_premium??1,rerolls:c.rules?.rerolls??1,winterLimit:c.rules?.winter_limit??2,seasonIncome:c.rules?.season_income??0,spinFee:c.rules?.spin_fee??5000000,replacementDays:c.rules?.replacement_days??3});
 const myClub=state.clubs.find(cl=>cl.memberId===state.memberId);
 const open=market?.window?.status==='open';
 const selectedSeason=season||c.seasonId;
 const fixtures=c.fixtures.filter(f=>f.seasonId===selectedSeason);
 const names=(id:string)=>state.clubs.find(cl=>cl.id===id)?.name||id;
 const playerName=(id:string)=>state.clubs.flatMap(cl=>cl.squad).find(p=>p.id===id)?.name||c.fixtures.flatMap(f=>f.lineups).find(p=>p.playerId===id)?.name||market?.freePlayers.find(p=>p.id===id)?.name||id;
 const suspended=(id:string)=>c.suspensions.some(s=>s.playerId===id&&s.seasonId===c.seasonId&&!s.expired&&s.served<s.matches);
 const eligible=myClub?.squad.filter(p=>!suspended(p.id)).map(p=>p.id)||[];
 const currentBallot=c.ballots.find(b=>b.windowId===market?.window?.id&&b.status==='open');
 const standings=state.clubs.map(cl=>{
  let played=0,won=0,drawn=0,lost=0,gf=0,ga=0;
  for(const f of fixtures.filter(f=>['finished','forfeit'].includes(f.status))){
   if(f.homeClubId!==cl.id&&f.awayClubId!==cl.id)continue;
   const home=f.homeClubId===cl.id,g=home?f.homeGoals!:f.awayGoals!,against=home?f.awayGoals!:f.homeGoals!;
   played++;gf+=g;ga+=against;if(g>against)won++;else if(g===against)drawn++;else lost++;
  }
  return {id:cl.id,name:cl.name,played,won,drawn,lost,gf,ga,points:won*3+drawn};
 }).filter(cl=>fixtures.some(f=>f.homeClubId===cl.id||f.awayClubId===cl.id)).sort((a,b)=>b.points-a.points||(b.gf-b.ga)-(a.gf-a.ga)||b.gf-a.gf||a.name.localeCompare(b.name));
 return <section className="space-y-5 rounded-xl border border-white/15 p-4">
  <h2 className="text-xl font-semibold">Competición · {c.phase==='assignment'?'Elección y pretemporada':c.phase==='finished'?'Temporada finalizada':`Jornada ${c.round||'finalizada'}`}</h2>
  {!c.enabled?<button disabled={pending||!admin} className={button} onClick={()=>onCommand({action:'configure'},true)}>Activar reglas completas</button>:<>
   {show('lobby')&&<details><summary>Reglas de esta partida</summary>
    <p className="my-2 text-sm text-white/60">Plantilla {c.rules?.min_squad}–{c.rules?.max_squad}. Libres por día: {c.rules?.daily_basic} básicos y {c.rules?.daily_premium} premium (OVR ≥ 84). Reinicio a medianoche de Bogotá. Giro: {money(c.rules?.spin_fee||0)}. Reelecciones: {c.rules?.rerolls}. Invierno: {c.rules?.winter_limit} compras. Ingreso por temporada: {money(c.rules?.season_income||0)}. Plazo de sustitución: {c.rules?.replacement_days} días.</p>
    {admin&&!market?.window&&c.fixtures.length===0&&<div className="grid gap-3 sm:grid-cols-3">{Object.entries(settings).map(([key,value])=><label key={key}>{({minSquad:'Plantilla mínima',maxSquad:'Plantilla máxima',dailyBasic:'Libres básicos al día',dailyPremium:'Libres premium al día',rerolls:'Reelecciones',winterLimit:'Compras en invierno',seasonIncome:'Ingreso por temporada',spinFee:'Coste del giro',replacementDays:'Días para sustitución'} as Record<string,string>)[key]}<input type="number" min={0} className={`${input} w-full`} value={value} onChange={e=>setSettings({...settings,[key]:Number(e.target.value)})}/></label>)}<button disabled={pending} className={button} onClick={()=>onCommand({action:'configure',...settings},true)}>Guardar reglas</button></div>}
   </details>}
   {show('lobby','calendar')&&<div className="flex flex-wrap gap-3">
    {c.phase==='assignment'&&!open&&<button disabled={pending} className={button} onClick={()=>onCommand({action:'draw'})}>Girar ruleta de clubes</button>}
    {admin&&c.phase==='assignment'&&!open&&<button disabled={pending} className={button} onClick={()=>onCommand({action:'league_start',legs:2},true)}>Generar liga de ida y vuelta</button>}
    {admin&&c.phase==='league'&&<button disabled={pending||!!open} className={button} onClick={()=>onCommand({action:'round_close'},true)}>Cerrar jornada actual</button>}
    {admin&&c.phase==='finished'&&<button disabled={pending||!!open} className={button} onClick={()=>onCommand({action:'season_next'},true)}>Iniciar siguiente temporada</button>}
    {show('lobby')&&<button disabled={pending||!!open} className="rounded-lg border border-red-400/40 px-3 py-2 disabled:opacity-40" onClick={()=>onCommand({action:'leave'})}>Abandonar torneo</button>}
   </div>}
   {show('squad','spin')&&myClub&&<div className="space-y-3">
    <h3 className="font-semibold">{view==='spin'?'Ruleta de jugadores libres':'Plantilla y sanciones'}</h3>
    {show('squad')&&<>
    <p className="text-sm text-white/60">Liberar no devuelve cupos ni paga reembolso voluntario. El jugador puede contratarse desde el día siguiente; tu club espera a otra ventana. Las liberaciones por deuda recuperan el 50 % del precio del contrato.</p>
    <ul className="space-y-2">{myClub.squad.map(p=><li key={p.id} className="flex flex-wrap items-center justify-between gap-2"><span>{p.name} · Cláusula {money(p.clause||0)}{suspended(p.id)&&' · Suspendido'}</span><button disabled={pending||!open} className={button} onClick={()=>onCommand({action:'release',playerId:p.id})}>Liberar {p.name}</button></li>)}</ul>
    <p>Libres contratados hoy: {c.daily.filter(d=>d.clubId===myClub.id).map(d=>`${d.tier==='premium'?'Premium':'Básicos'}: ${d.used}`).join(' · ')||'0'}</p>
    {c.debts.filter(d=>d.clubId===myClub.id).map(d=><div key={d.clubId}><p role="alert">Deuda pendiente: {money(d.amount)}. Impide compras nuevas.</p><button disabled={pending} className={button} onClick={()=>onCommand({action:'pay_debt'})}>Pagar deuda con saldo disponible</button></div>)}
    </>}
    {show('spin')&&<>
    <button disabled={pending||!open} className={button} onClick={()=>onCommand({action:'spin'})}>Girar por un jugador libre · {money(c.rules?.spin_fee||0)}</button>
    {c.spins.filter(s=>s.status==='pending').map(s=><div key={s.id} className="space-y-2 rounded-lg bg-white/5 p-3"><p>{playerName(s.playerId)} · Resuelve antes de {new Date(s.expiresAt).toLocaleString('es-CO')}</p><p className="text-sm text-white/60">Aceptar cobra también el precio del jugador. El giro no reserva propiedad ni cupos.</p><button disabled={pending||!open} className={button} onClick={()=>onCommand({action:'spin_claim',spinId:s.id})}>Contratar resultado</button> <button disabled={pending} className={button} onClick={()=>onCommand({action:'spin_reject',spinId:s.id})}>Rechazar resultado</button></div>)}
    </>}
   </div>}
   {show('votes')&&<div className="space-y-3"><h3 className="font-semibold">Votación de iconos</h3><p className="text-sm text-white/60">Un voto por club. Gana el más votado; los empates se resuelven por identificador. Al vencer la votación se abre automáticamente su subasta.</p>
    {admin&&open&&!currentBallot&&!market?.auctions.some(a=>a.status==='active'||a.status==='expired')&&<button disabled={pending} className={button} onClick={()=>onCommand({action:'vote_open',minutes:2,auctionMinutes:10},true)}>Abrir votación de 2 minutos</button>}
    {currentBallot&&<><p>Cierra: {new Date(currentBallot.endsAt).toLocaleString('es-CO')} · {currentBallot.votedClubs.length}/{currentBallot.electorate} clubes votaron.</p>{currentBallot.options.map(o=><button key={o.playerId} disabled={pending||!myClub||currentBallot.votedClubs.includes(myClub.id)} className={`${button} mr-2`} onClick={()=>onCommand({action:'vote',ballotId:currentBallot.id,playerId:o.playerId})}>{o.name} · {o.votes} votos</button>)}{admin&&<button disabled={pending} className={button} onClick={()=>onCommand({action:'vote_close',ballotId:currentBallot.id},true)}>Cerrar votación y abrir subasta</button>}</>}
    <details><summary>Historial de votaciones</summary>{c.ballots.map(b=><p key={b.id}>{b.status==='chosen'?'Elegido':b.status==='cancelled'?'Cancelada':'Abierta'} · {b.options.map(o=>`${o.name}: ${o.votes}`).join(' · ')}</p>)}</details>
   </div>}
   {show('calendar','table')&&<label className="block">Consultar temporada <select className={input} value={selectedSeason} onChange={e=>setSeason(e.target.value)}>{c.seasons.map(s=><option className="bg-[#171b20]" key={s.id} value={s.id}>Temporada {s.number}</option>)}</select></label>}
   {show('table')&&standings.length>0&&<div className="overflow-x-auto"><h3 className="font-semibold">Clasificación</h3><table className="w-full text-left"><thead><tr>{['Club','PJ','G','E','P','GF','GC','Puntos'].map(h=><th key={h} className="p-2">{h}</th>)}</tr></thead><tbody>{standings.map(s=><tr key={s.id}>{[s.name,s.played,s.won,s.drawn,s.lost,s.gf,s.ga,s.points].map((v,i)=><td className="p-2" key={i}>{v}</td>)}</tr>)}</tbody></table></div>}
   {show('calendar')&&<div className="space-y-3"><h3 className="font-semibold">Calendario y resultados</h3>{fixtures.map(f=>{
    const score=scores[f.id]||{home:0,away:0}, participant=!!myClub&&[f.homeClubId,f.awayClubId].includes(myClub.id), active=f.seasonId===c.seasonId&&f.round===c.round;
    const selected=selections[f.id]||eligible;
    const resultCards=Object.entries(cards[f.id]||{}).filter(([,kind])=>kind).map(([playerId,kind])=>({playerId,kind}));
    return <article key={f.id} className="space-y-3 rounded-lg border border-white/10 p-3"><h4>Jornada {f.round} · {names(f.homeClubId)} — {names(f.awayClubId)}</h4><p>{({scheduled:'Pendiente',playing:'En juego',finished:'Finalizado',forfeit:'Incomparecencia'} as Record<string,string>)[f.status]}{f.homeGoals!==null&&` · ${f.homeGoals}–${f.awayGoals}`}</p>
     {active&&participant&&f.status==='scheduled'&&!f.confirmedClubs.includes(myClub!.id)&&<><p>Selecciona tu alineación. Los sancionados no pueden jugar.</p>{myClub!.squad.map(p=><label key={p.id} className="mr-3 inline-flex gap-2"><input type="checkbox" disabled={pending||suspended(p.id)} checked={selected.includes(p.id)} onChange={e=>setSelections({...selections,[f.id]:e.target.checked?[...selected,p.id]:selected.filter(id=>id!==p.id)})}/>{p.name}{suspended(p.id)&&' (sancionado)'}</label>)}<button disabled={pending||!!open} className={button} onClick={()=>onCommand({action:'lineup',fixtureId:f.id,players:selected})}>Confirmar mi alineación</button></>}
     {active&&f.status==='playing'&&(participant||admin)&&<><div className="flex gap-3"><label>Goles local <input aria-label={`Goles local ${f.id}`} className={`${input} w-20`} type="number" min={0} max={99} value={score.home} onChange={e=>setScores({...scores,[f.id]:{...score,home:Number(e.target.value)}})}/></label><label>Goles visitante <input aria-label={`Goles visitante ${f.id}`} className={`${input} w-20`} type="number" min={0} max={99} value={score.away} onChange={e=>setScores({...scores,[f.id]:{...score,away:Number(e.target.value)}})}/></label></div>
      <details><summary>Tarjetas del partido</summary>{f.lineups.filter(l=>l.selected).map(l=><label key={l.playerId} className="m-2 block">{l.name} <select className={input} value={cards[f.id]?.[l.playerId]||''} onChange={e=>setCards({...cards,[f.id]:{...cards[f.id],[l.playerId]:e.target.value}})}><option value="">Sin tarjeta</option><option value="yellow">Amarilla</option><option value="red">Roja / doble amarilla</option></select></label>)}</details>
      {participant&&(!f.proposal||f.proposerClubId===myClub?.id)&&<button disabled={pending} className={button} onClick={()=>onCommand({action:'result_submit',fixtureId:f.id,homeGoals:score.home,awayGoals:score.away,cards:resultCards})}>Proponer resultado</button>}
      {participant&&f.proposal&&f.proposerClubId!==myClub?.id&&<><p>Propuesta: {f.proposal.homeGoals}–{f.proposal.awayGoals} · Tarjetas: {f.proposal.cards.map(card=>`${playerName(card.playerId)}: ${card.kind==='red'?'roja':'amarilla'}`).join(', ')||'ninguna'}</p><button disabled={pending} className={button} onClick={()=>onCommand({action:'result_confirm',fixtureId:f.id})}>Confirmar resultado rival</button> <button disabled={pending} className={button} onClick={()=>onCommand({action:'result_dispute',fixtureId:f.id})}>Disputar resultado</button></>}
      {admin&&<button disabled={pending} className={`${button} ml-2`} onClick={()=>onCommand({action:'result_force',fixtureId:f.id,homeGoals:score.home,awayGoals:score.away,cards:resultCards},true)}>Resolver resultado como administrador</button>}
     </>}
     <details><summary>Alineaciones, tarjetas y gastos históricos</summary>{f.lineups.map(l=><p key={l.playerId}>{names(l.clubId)} · {l.name} · {l.selected?'Alineación':'Reserva'} · Precio {money(l.price)}</p>)}{f.cards.map(card=><p key={card.playerId}>{playerName(card.playerId)} · {card.kind==='red'?'Roja':'Amarilla'}</p>)}{f.expenses.map(e=><p key={`${e.playerId}:${e.kind}`}>{names(e.clubId)} · {playerName(e.playerId)} · {({salary:'Salario',yellow:'Multa por amarilla',red:'Multa por roja'} as Record<string,string>)[e.kind]||e.kind} · {money(e.amount)}</p>)}</details>
     {admin&&active&&f.status==='scheduled'&&<button disabled={pending||!!open} className={button} onClick={()=>onCommand({action:'forfeit',fixtureId:f.id},true)}>Resolver abandono vencido</button>}
    </article>;
   })}</div>}
   {show('lobby')&&admin&&<details><summary>Sustituir administrador de un club vacante</summary>{state.clubs.filter(cl=>!cl.memberId).map(cl=><div key={cl.id} className="my-3 flex gap-3"><span>{cl.name}</span><select aria-label={`Sustituto de ${cl.name}`} className={input} value={replacements[cl.id]||''} onChange={e=>setReplacements({...replacements,[cl.id]:e.target.value})}><option value="">Seleccionar participante</option>{state.members.filter(m=>!c.departures.includes(m.id)&&!state.clubs.some(cl=>cl.memberId===m.id)).map(m=><option key={m.id} value={m.id}>{m.name}</option>)}</select><button disabled={pending||!replacements[cl.id]||!!open} className={button} onClick={()=>onCommand({action:'replace',clubId:cl.id,memberId:replacements[cl.id]},true)}>Asignar sustituto</button></div>)}</details>}
   {show('squad')&&<details><summary>Historial de liberaciones</summary>{c.releases.map((r,i)=><p key={i}>{names(r.clubId)} · {playerName(r.playerId)} · {r.automatic?'Por deuda':'Voluntaria'} · {money(r.refund)} · {new Date(r.createdAt).toLocaleString('es-CO')}</p>)}</details>}
  </>}
 </section>;
}
