'use client';
import { useState } from 'react';
import type { GameMarket, GameState } from '@/lib/game-types';
import AuctionPanel from './AuctionPanel';
const money = (value: number) => new Intl.NumberFormat('es-CO', { style: 'currency', currency: 'EUR', maximumFractionDigits: 0 }).format(value);
const button = 'rounded-lg bg-emerald-600 px-3 py-2 text-white disabled:opacity-40';
const statusNames: Record<string,string> = { pending:'Pendiente',accepted:'Aceptada',rejected:'Rechazada',cancelled:'Cancelada',stale:'Jugador traspasado',expired:'Vencida' };

export default function MarketPanel({ state, market, admin, pending, complete=false, finished=false, onCommand }: {
  state: GameState; market: GameMarket; admin: boolean; pending: boolean; complete?:boolean; finished?:boolean;
  onCommand: (body: Record<string,unknown>, admin?: boolean) => void;
}) {
  const [kind, setKind] = useState('summer');
  const [amounts, setAmounts] = useState<Record<string,string>>({});
  const [counters, setCounters] = useState<Record<string,string>>({});
  const myClub = state.clubs.find(c=>c.memberId===state.memberId);
  const limits = market.limits.find(l=>l.clubId===myClub?.id);
  const open = market.window?.status==='open';
  const activeWindow = market.window && market.window.status!=='closed';
  return <section className="space-y-4 rounded-xl border border-white/15 p-4">
    <h2 className="text-2xl font-semibold">Mercado</h2>
    <p>{market.window ? `${market.window.kind==='winter'?'Invierno':'Verano'} · ${market.window.status==='open'?'Abierto':market.window.status==='expired'?'Vencido':'Cerrado'}` : 'Todavía no hay ventana de mercado.'}</p>
    {market.window && <p className="text-sm text-white/60">Cierre: {new Date(market.window.closesAt).toLocaleString('es-CO')}</p>}
    <p className="text-sm text-white/60">Al vencer el plazo se cierra la ventana y se libera el dinero reservado.</p>
    {admin && <div className="flex flex-wrap gap-3">{activeWindow ? <button className={button} disabled={pending} onClick={()=>onCommand({action:'close'},true)}>Cerrar mercado y liberar reservas</button> : <><label>Ventana <select className="rounded bg-[#171b20] p-2" value={kind} onChange={e=>setKind(e.target.value)}><option value="summer">Verano</option><option value="winter">Invierno</option></select></label><button className={button} disabled={pending||finished} onClick={()=>onCommand({action:'open',kind,minutes:60},true)}>Abrir mercado por 60 minutos</button></>}</div>}
    {myClub && <p>{limits && <>Compras: {limits.used} · Cupos reservados: {limits.held} · Límite: {limits.limit}. </>}Saldo disponible: {money(myClub.budget-myClub.reserved)}.</p>}
    <p className="text-sm text-white/60">Las ofertas reservan dinero y un cupo hasta su resolución. Cada propuesta debe aceptarla el otro club. Las compras realizadas consumen el cupo durante esta ventana.</p>
    <AuctionPanel state={state} market={market} admin={admin&&!complete} pending={pending} onCommand={onCommand} />
    <h3 className="font-semibold">Jugadores libres</h3>
    {market.freePlayers.length===0 && <p className="text-white/60">No hay jugadores libres.</p>}
    <div className="flex flex-wrap gap-3">{[...market.freePlayers].sort((a,b)=>b.ovr-a.ovr).map(player=><div className="rounded-lg border border-white/15 p-3" key={player.id}><p>{player.name} · {player.ovr}</p><p>{money(player.price)}</p><button className={button} disabled={pending || !open || !myClub} onClick={()=>onCommand({action:'sign',playerId:player.id})}>Contratar jugador libre</button></div>)}</div>
    <h3 className="font-semibold">Ofertar a otros clubes</h3>
    <div className="grid gap-3 md:grid-cols-2">{state.clubs.filter(c=>c.id!==myClub?.id && c.memberId!==null).flatMap(club=>club.squad.map(player=>({club,player}))).sort((a,b)=>b.player.ovr-a.player.ovr).map(({club,player})=><div className="space-y-2 rounded-lg border border-white/15 p-3" key={player.id}><p>{player.name} · {club.name}</p><label className="block text-sm">Importe de la oferta<input type="number" min={1} step={1000000} className="ml-2 w-40 rounded bg-white/10 p-2" value={amounts[player.id] ?? String(player.price)} onChange={e=>setAmounts({...amounts,[player.id]:e.target.value})} /></label><button className={button} disabled={pending || !open || !myClub} onClick={()=>onCommand({action:'offer',playerId:player.id,amount:Number(amounts[player.id] ?? player.price)})}>Enviar oferta</button></div>)}</div>
    <h3 className="font-semibold">Cláusulas de rescisión</h3>
    <p className="text-sm text-white/60">El jugador puede rechazar la cláusula (25 %); en ese caso no hay cobro ni compra y tu club no puede repetir el intento por él en esta ventana. Protección del vendedor: {market.window?.clauseProtectionLimit===0?'sin límite':`${market.window?.clauseProtectionLimit ?? 1} cláusula por ventana`}.</p>
    <div className="flex flex-wrap gap-3">{state.clubs.filter(club=>club.id!==myClub?.id && club.memberId!==null).flatMap(club=>club.squad.filter(player=>player.clause!==null && player.clause>0).map(player=><div key={player.id} className="space-y-2 rounded-lg border border-white/15 p-3"><p>{player.name} · {club.name}</p><p>{money(player.clause!)}</p><button className={button} disabled={pending || !open || !myClub || market.clauseAttempts.some(attempt=>attempt.windowId===market.window?.id && attempt.buyerClubId===myClub?.id && attempt.playerId===player.id)} onClick={()=>onCommand({action:'clause',playerId:player.id})}>Pagar cláusula</button></div>))}</div>
    {market.clauseAttempts.map(attempt=><p key={`${attempt.windowId}-${attempt.buyerClubId}-${attempt.playerId}`} className="rounded-lg bg-white/5 p-3">{attempt.buyer} → {attempt.seller} · {attempt.playerName} · {money(attempt.amount)} · {attempt.outcome==='rejected'?'Cláusula rechazada por el jugador · sin cobro':'Cláusula pagada'}</p>)}
    <h3 className="font-semibold">Negociaciones</h3>
    {market.offers.map(offer=><div className="space-y-2 rounded-lg bg-white/5 p-3" key={offer.id}><p>{offer.buyer} → {offer.seller} · {offer.playerName} · {money(offer.amount)} · {statusNames[offer.status] || offer.status}</p>
      {offer.proposedAmount!==null && <p>Propuesta {offer.status==='pending'?'actual':'final'}: {money(offer.proposedAmount)}{offer.status==='pending' && <> · Responde {offer.proposedByClubId===offer.buyerClubId ? offer.seller : offer.buyer}.</>}</p>}
      {offer.revisions.length>0 && <details><summary>Historial de negociación</summary><ul>{offer.revisions.map(revision=><li key={revision.revision}>{revision.authorClubId===offer.buyerClubId?offer.buyer:offer.seller}: {money(revision.amount)}</li>)}</ul></details>}
      {offer.status==='pending' && <div className="flex flex-wrap gap-2">{(myClub?.id===offer.buyerClubId || myClub?.id===offer.sellerClubId) && myClub?.id!==(offer.proposedByClubId ?? offer.buyerClubId) && <><button className={button} disabled={pending || !open} onClick={()=>onCommand({action:'accept',offerId:offer.id})}>Aceptar oferta</button><button className={button} disabled={pending} onClick={()=>onCommand({action:'reject',offerId:offer.id})}>Rechazar</button><label>Importe de contraoferta <input type="number" min={1} step={1000000} className="w-40 rounded bg-white/10 p-2" value={counters[offer.id] ?? String(offer.proposedAmount ?? offer.amount)} onChange={e=>setCounters({...counters,[offer.id]:e.target.value})} /></label><button className={button} disabled={pending || !open} onClick={()=>onCommand({action:'counter',offerId:offer.id,amount:Number(counters[offer.id] ?? offer.proposedAmount ?? offer.amount)})}>Enviar contraoferta</button></>}{offer.buyerClubId===myClub?.id && <button className={button} disabled={pending} onClick={()=>onCommand({action:'cancel',offerId:offer.id})}>Cancelar y liberar reserva</button>}</div>}
    </div>)}
    {market.transfers.map(transfer=><p className="rounded-lg bg-emerald-950/40 p-3" key={transfer.id}>{transfer.playerName}: {transfer.seller || 'Libre'} → {transfer.buyer} · {money(transfer.amount)}</p>)}
    <details><summary>Movimientos financieros de mi club</summary><ul className="mt-2 space-y-2">{market.ledger.map(entry=><li key={entry.id}>{({opening:'Presupuesto inicial',market_sign:'Contratación de libre',market_clause:'Pago de cláusula',icon_auction:'Adjudicación de icono',match_expenses:'Gastos del partido',auto_release:'Reembolso por liberación',release:'Liberación voluntaria',season_income:'Ingreso de temporada',slot_spin:'Giro de libres',debt_payment:'Pago de deuda'} as Record<string,string>)[entry.kind]||'Traspaso'} · {entry.amount>0?'+':''}{money(entry.amount)}</li>)}</ul></details>
  </section>;
}

