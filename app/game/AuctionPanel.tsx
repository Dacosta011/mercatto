'use client';
import { useState } from 'react';
import type { GameMarket, GameState } from '@/lib/game-types';
const money=(value:number)=>new Intl.NumberFormat('es-CO',{style:'currency',currency:'EUR',maximumFractionDigits:0}).format(value);
const button='rounded-lg bg-emerald-600 px-3 py-2 text-white disabled:opacity-40';
export default function AuctionPanel({state,market,admin,pending,onCommand}: {
  state:GameState;market:GameMarket;admin:boolean;pending:boolean;
  onCommand:(body:Record<string,unknown>,admin?:boolean)=>void;
}) {
  const [amounts,setAmounts]=useState<Record<string,string>>({});
  const myClub=state.clubs.find(club=>club.memberId===state.memberId);
  const limit=market.limits.find(limit=>limit.clubId===myClub?.id);
  const open=market.window?.status==='open';
  const auctions=market.auctions ?? [];
  const active=auctions.some(auction=>auction.windowId===market.window?.id && ['active','expired'].includes(auction.status));
  return <section className="space-y-3 rounded-xl border border-white/15 p-4">
    <h3 className="text-xl font-semibold">Subastas de iconos</h3>
    <p className="text-sm text-white/60">Un cupo de subasta por club y ventana, separado de las compras normales. Incremento mínimo: 5 millones. Las pujas en los últimos dos minutos dejan dos minutos para responder, hasta el cierre del mercado.</p>
    {myClub && limit && <p>Iconos: {limit.iconsUsed} adjudicados · {limit.iconsHeld} cupos reservados.</p>}
    {admin && open && !active && <div className="flex flex-wrap gap-3">{(market.auctionIcons ?? []).map(icon=><div key={icon.id} className="space-y-2 rounded-lg bg-white/5 p-3"><p>{icon.name} · {icon.ovr} · Mínimo {money(icon.minBid)}</p><button disabled={pending} className={button} onClick={()=>onCommand({action:'auction_open',playerId:icon.id,minutes:10},true)}>Subastar por 10 minutos</button></div>)}</div>}
    {auctions.length===0 && <p className="text-white/60">Todavía no hay subastas.</p>}
    {auctions.map(auction=>{
      const expired=auction.status==='expired';
      const minimum=Math.max(auction.minBid,auction.highestBid+5000000);
      const status=auction.status==='settled'?'Adjudicada':auction.status==='unsold'?'Sin pujas':expired?'Pendiente de adjudicación':'Abierta';
      return <div key={auction.id} className="space-y-2 rounded-lg bg-white/5 p-3">
        <p>{auction.playerName} · {status}</p>
        <p>{auction.highestClub ? `${auction.highestClub} · ${money(auction.highestBid)}` : `Puja mínima: ${money(minimum)}`}</p>
        <p className="text-sm text-white/60">Cierre: {new Date(auction.endsAt).toLocaleString('es-CO')}</p>
        {auction.status==='active' && <><label>Importe de la puja <input className="w-40 rounded bg-white/10 p-2" type="number" min={minimum} step={5000000} value={amounts[auction.id] ?? minimum} onChange={event=>setAmounts({...amounts,[auction.id]:event.target.value})}/></label><button className={button} disabled={pending || !open || expired || !myClub || auction.highestClubId===myClub.id || (limit?.iconsUsed ?? 0)+(limit?.iconsHeld ?? 0)>=1} onClick={()=>onCommand({action:'auction_bid',auctionId:auction.id,amount:Number(amounts[auction.id] ?? minimum)})}>Pujar por el icono</button></>}
        <details><summary>Historial de pujas</summary><ul>{auction.bids.map(bid=><li key={bid.id}>{bid.club} · {money(bid.amount)}</li>)}</ul></details>
      </div>;
    })}
  </section>;
}
