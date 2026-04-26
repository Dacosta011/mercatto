"use client";
import { useState, useCallback, useEffect, useRef, useMemo } from "react";
import SlotReel from "./SlotReel";
import type { SlotPrize } from "@/app/api/slot-machine/prizes/route";

const SPIN_PRICE       = 1_000;
const FREE_SPINS_GRANT = 10;
const FREE_SPINS_ID    = "__free_spins__";
const WIN_CHANCE       = 0.40;
const NEAR_WIN_CHANCE  = 0.30;

const FREE_SPINS_PRIZE: SlotPrize = {
  id: FREE_SPINS_ID, name: "10 Tiros Gratis", ovr: 0,
  position: "", headshotUrl: null, type: "free_spins",
};

function getWeight(p: SlotPrize) {
  if (p.type === "free_spins") return 4;
  if (p.type === "icon")       return 2;
  if (p.ovr >= 90) return 3;  if (p.ovr >= 87) return 5;
  if (p.ovr >= 84) return 10; if (p.ovr >= 80) return 20;
  if (p.ovr >= 75) return 30; return 60;
}

function weightedPick(pool: SlotPrize[]) {
  const ws = pool.map(getWeight);
  const total = ws.reduce((a, b) => a + b, 0);
  let r = Math.random() * total;
  for (let i = 0; i < pool.length; i++) { r -= ws[i]; if (r <= 0) return pool[i]; }
  return pool[pool.length - 1];
}

interface Outcome {
  winners:    [SlotPrize, SlotPrize, SlotPrize];
  isWin:      boolean;
  isNearWin:  boolean;
}

function decide(pool: SlotPrize[]): Outcome {
  if (pool.length < 3) return { winners: [pool[0], pool[0], pool[0]], isWin: false, isNearWin: false };

  if (Math.random() < WIN_CHANCE) {
    const w = weightedPick(pool);
    return { winners: [w, w, w], isWin: true, isNearWin: false };
  }
  if (Math.random() < NEAR_WIN_CHANCE) {
    const w  = weightedPick(pool);
    let p3   = weightedPick(pool);
    let t    = 0;
    while (p3.id === w.id && t++ < 50) p3 = weightedPick(pool);
    return { winners: [w, w, p3], isWin: false, isNearWin: true };
  }
  const p1 = weightedPick(pool);
  let p2   = weightedPick(pool);
  let p3   = weightedPick(pool);
  let t    = 0;
  while ((p2.id === p1.id || p3.id === p1.id || p3.id === p2.id) && t++ < 50) {
    p2 = weightedPick(pool); p3 = weightedPick(pool);
  }
  return { winners: [p1, p2, p3], isWin: false, isNearWin: false };
}

function ovrColor(ovr: number) {
  if (ovr >= 87) return "#22C55E"; if (ovr >= 84) return "#84CC16";
  if (ovr >= 80) return "#F59E0B"; if (ovr >= 75) return "#FB923C";
  return "#9CA3AF";
}

function fmt(v: number) {
  if (v >= 1e6) return `€${(v/1e6).toFixed(1)}M`;
  if (v >= 1e3) return `€${(v/1e3).toFixed(0)}K`;
  return `€${v}`;
}

const AUTO_OPT = [5, 10, 25, 50];

interface PoolRange { label: string; count: number; players: SlotPrize[]; }
interface PoolSlotItem {
  id: string; player_id: string; ovr: number; is_premium: boolean;
  status: string; claimed_by_name: string | null; claimed_at: string | null;
  players: { id: string; name: string; ovr: number; position: string; headshot_url: string | null; salary: number; is_icon: boolean } | null;
}
interface Props { prizes: SlotPrize[]; budget?: number; tournamentCode?: string; memberToken?: string; poolDate?: string; pool?: PoolSlotItem[]; }

export default function SlotMachine({ prizes, budget = 0, tournamentCode = "", memberToken = "", poolDate, pool: poolData = [] }: Props) {
  const storageKey = `mercatto:slots:free-spins:${tournamentCode}`;

  // Stable pool — memoized so SlotReel useMemo doesn't re-run on parent renders
  const pool = useMemo(() => [FREE_SPINS_PRIZE, ...prizes], [prizes]);  // internal spin pool

  // Detect mobile for smaller reels
  const [isMobile, setIsMobile] = useState(false);
  const [showPool, setShowPool] = useState(false);
  useEffect(() => {
    const check = () => setIsMobile(window.innerWidth < 640);
    check();
    window.addEventListener('resize', check);
    return () => window.removeEventListener('resize', check);
  }, []);

  const [freeSpins, setFreeSpins] = useState(() => {
    if (typeof window === "undefined") return 0;
    const s = localStorage.getItem(storageKey);
    return s !== null ? parseInt(s, 10) : 0;
  });

  // ── Spin state ────────────────────────────────────────────────────────────
  // activeReel: -1 = idle, 0/1/2 = which reel is currently spinning, 3 = all done
  const [activeReel, setActiveReel] = useState(-1);
  const [spinKey,    setSpinKey]    = useState(0);
  const [reel2Fast,  setReel2Fast]  = useState(false);
  const [reel2Slow,  setReel2Slow]  = useState(false);
  const [waitingDecision, setWaitingDecision] = useState(false);  // pauses auto-spin during win modal
  const [outcome,    setOutcome]    = useState<Outcome | null>(null);
  const [leverPulled,setLeverPulled]= useState(false);
  const [winPrize,   setWinPrize]   = useState<SlotPrize | null>(null);
  const [spinId,     setSpinId]     = useState<string | null>(null);
  const [decision,   setDecision]   = useState<"accepted" | "returned" | null>(null);
  const [celebrating,setCelebrating]= useState(false);
  const [autoCount,  setAutoCount]  = useState(10);
  const [autoRemaining, setAutoRemaining] = useState(0);
  const [isAutoSpinning, setIsAutoSpinning] = useState(false);
  const autoRef      = useRef(false);
  const isFreeAutoRef= useRef(false);
  const [history,    setHistory]    = useState<{ prize: SlotPrize; free: boolean }[]>([]);

  useEffect(() => {
    if (typeof window !== "undefined") localStorage.setItem(storageKey, String(freeSpins));
  }, [freeSpins, storageKey]);

  const isSpinning = activeReel >= 0 && activeReel < 3;
  const allDone    = activeReel === 3;
  const isFree     = freeSpins > 0;
  const canSpin    = pool.length >= 4 && (isFree || budget >= SPIN_PRICE);  // allow mid-spin interrupt

  const doSpin = useCallback(async () => {
    if (!prizes.length) return;
    if (!isFree && budget < SPIN_PRICE) return;
    if (isSpinning) setActiveReel(-1);
    setLeverPulled(true);
    setTimeout(() => setLeverPulled(false), 400);
    try {
      const res = await fetch(`/api/tournaments/${tournamentCode}/slot-machine/spin`, {
        method: "POST",
        headers: { Authorization: `Bearer ${memberToken}`, "Content-Type": "application/json", "X-Free-Spins": String(freeSpins) },
      });
      const data = await res.json();
      if (!res.ok) { console.error("Spin error:", data.error); return; }
      const serverReels: [SlotPrize, SlotPrize, SlotPrize] = data.reels.map((r: any) => ({
        id: r.id, name: r.name, ovr: r.ovr, position: r.position,
        headshotUrl: r.headshotUrl, salary: r.salary, type: r.type as "player" | "icon" | "free_spins",
      })) as [SlotPrize, SlotPrize, SlotPrize];
      const o: Outcome = { winners: serverReels, isWin: data.isWin, isNearWin: data.isNearWin };
      setSpinId(data.spinId);
      setOutcome(o); setWinPrize(null); setDecision(null); setCelebrating(false);
      setReel2Fast(false); setReel2Slow(false); setWaitingDecision(false);
      setSpinKey(k => k + 1);
      setActiveReel(0);
      if (isFree) setFreeSpins(p => Math.max(0, p - 1));
    } catch (e) { console.error("Spin error:", e); }
  }, [prizes.length, isFree, budget, isSpinning, tournamentCode, memberToken]);

  // ── Sequential reel completion ────────────────────────────────────────────
  const handleReelDone = useCallback((reelIdx: number) => {
    if (reelIdx < 2) {
      // reel 1 done + no match -> reel 2 fast
      if (reelIdx === 1 && outcome) {
        const mismatch = outcome.winners[0].id !== outcome.winners[1].id;
        setReel2Fast(mismatch);
        setReel2Slow(!mismatch);  // slow down reel 2 if first two match (win or near-win)
      }
      setActiveReel(reelIdx + 1);   // start next reel
    } else {
      // All 3 done
      setActiveReel(3);
      if (outcome?.isWin) {
        const prize = outcome.winners[0];
        setWinPrize(prize);
        setCelebrating(true);
        setTimeout(() => setCelebrating(false), 4000);
        if (prize.type === "free_spins") {
          setFreeSpins(p => p + FREE_SPINS_GRANT);
          setHistory(h => [{ prize, free: isFree }, ...h].slice(0, 20));
          // Pause auto-spin: let user accept or reject before continuing
          if (isAutoSpinning) setWaitingDecision(true);
          setTimeout(() => {
            autoRef.current = true; isFreeAutoRef.current = true;
            setIsAutoSpinning(true); setAutoRemaining(FREE_SPINS_GRANT - 1);
          }, 1600);
        } else {
          setHistory(h => [{ prize, free: isFree }, ...h].slice(0, 20));
        }
      }
    }
  }, [outcome, isFree]);

  // Auto-spin
  useEffect(() => {
    if (!isAutoSpinning || isSpinning || autoRemaining <= 0 || waitingDecision) return;
    const t = setTimeout(() => {
      if (!autoRef.current) return;
      setAutoRemaining(p => {
        const n = p - 1;
        if (n <= 0) { setIsAutoSpinning(false); autoRef.current = false; isFreeAutoRef.current = false; }
        return n;
      });
      doSpin();
    }, 1200);
    return () => clearTimeout(t);
  }, [isAutoSpinning, isSpinning, autoRemaining, doSpin]);

  const startAuto = () => {
    if (!canSpin) return;
    autoRef.current = true; isFreeAutoRef.current = false;
    setIsAutoSpinning(true); setAutoRemaining(autoCount); doSpin();
  };
  const stopAuto = () => {
    autoRef.current = false; setIsAutoSpinning(false);
    setAutoRemaining(0); isFreeAutoRef.current = false;
  };

  const isWin         = outcome?.isWin && allDone;
  const isFreeAuto    = isAutoSpinning && isFreeAutoRef.current;
  const showWinPanel  = isWin && winPrize && !decision && winPrize.type !== "free_spins";

  return (
    <div className="flex flex-col lg:flex-row gap-4 lg:gap-6 w-full items-start justify-center">

      {/* ── Main machine column ── */}
      <div className="flex flex-col items-center gap-3 w-full flex-shrink-0" style={{ maxWidth: 600 }}>

        {/* Stats */}
        <div className="w-full grid grid-cols-2 sm:grid-cols-3 gap-2">
          {[
            { label: "PRESUPUESTO",            value: fmt(budget),                          color: "#F3F4F6", bg: "#131722", border: "#ffffff08" },
            { label: isFree ? "🎁 GRATIS" : "💰 PRECIO / TIRADA", value: isFree ? `${freeSpins} restantes` : fmt(SPIN_PRICE), color: isFree ? "#22C55E" : "#F59E0B", bg: isFree ? "#22C55E10" : "#F59E0B10", border: isFree ? "#22C55E30" : "#F59E0B30" },
            { label: "GRATIS ACUMULADOS",       value: String(freeSpins),                   color: "#22C55E", bg: "#131722", border: "#ffffff08" },
          ].map((s, i) => (
            <div key={i} className="flex flex-col gap-0.5 px-3 py-2.5 rounded-xl" style={{ background: s.bg, border: `1px solid ${s.border}` }}>
              <span className="text-[9px] tracking-widest font-medium" style={{ color: i === 0 ? "#9CA3AF" : s.color }}>{s.label}</span>
              <span className="font-black text-sm" style={{ color: s.color }}>{s.value}</span>
            </div>
          ))}
        </div>

        {/* Free auto banner */}
        {isFreeAuto && (
          <div className="w-full flex items-center justify-between px-4 py-2.5 rounded-2xl" style={{ background: "linear-gradient(135deg,#052e16,#131722)", border: "1px solid #22C55E40" }}>
            <div className="flex items-center gap-2">
              <div className="w-2 h-2 rounded-full bg-[#22C55E] animate-pulse" style={{ boxShadow: "0 0 8px #22C55E" }} />
              <span className="text-[#22C55E] font-black text-xs tracking-wide">AUTO-GIRANDO GRATIS</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-[#22C55E] font-black text-lg">{autoRemaining}</span>
              <button onClick={stopAuto} className="ml-1 px-2.5 py-1 rounded-lg text-xs font-bold" style={{ background: "#0D0F14", border: "1px solid #EF444440", color: "#EF4444" }}>Stop</button>
            </div>
          </div>
        )}

        {/* Machine + Lever */}
        <div className="flex items-center gap-3 relative">
          {celebrating && <Fireworks />}

          {/* Machine */}
          <div className="flex flex-col flex-shrink-0" style={{ filter: "drop-shadow(0 6px 32px #8B5CF620)" }}>
            {/* Marquee */}
            <div className="flex items-center justify-center gap-2 py-2.5 px-6 rounded-t-3xl" style={{ background: "linear-gradient(135deg,#1E1340,#2D1B69,#1E1340)", border: "1px solid #8B5CF650", borderBottom: "none" }}>
              <Bulbs /><span className="text-[#E9D5FF] text-[10px] font-black tracking-[0.2em] mx-2">🎰 MERCATTO SLOTS</span><Bulbs reverse />
            </div>

            {/* Reels window */}
            <div style={{ background: "linear-gradient(180deg,#131722,#0D0F14)", border: "1px solid #8B5CF630", borderTop: "none", borderBottom: "none", padding: "14px", position: "relative" }}>
              {isWin && <div className="absolute inset-0 pointer-events-none animate-pulse" style={{ background: "radial-gradient(ellipse at center,#22C55E18,transparent 70%)", zIndex: 30 }} />}

              <div className="flex gap-2.5 p-3 rounded-2xl" style={{ background: "#060810", border: "2px solid #8B5CF618", boxShadow: "inset 0 4px 20px #00000090" }}>
                {[0, 1, 2].map(i => (
                  <SlotReel
                    key={i}
                    prizes={pool}
                    active={activeReel === i}
                    winner={outcome ? outcome.winners[i] : null}
                    slowDown={i === 2 && reel2Slow}
                    small={isMobile}
                    fast={i === 2 && reel2Fast}
                    onDone={() => handleReelDone(i)}
                    spinKey={spinKey}
                  />
                ))}
              </div>

              {/* Status dots */}
              <div className="flex items-center justify-center gap-2.5 mt-3">
                {[0, 1, 2].map(i => {
                  const done  = allDone || (activeReel > i + 1);
                  const spin  = activeReel === i;
                  const nearW = i === 2 && !!outcome?.isNearWin && spin;
                  return (
                    <div key={i} className="w-2 h-2 rounded-full transition-all duration-500" style={{
                      background: spin ? (nearW ? "#F59E0B" : "#8B5CF6") : isWin ? "#22C55E" : done ? "#374151" : "#374151",
                      boxShadow:  spin ? (nearW ? "0 0 8px #F59E0B" : "0 0 8px #8B5CF6") : isWin ? "0 0 8px #22C55E" : "none",
                    }} />
                  );
                })}
              </div>

              {/* Message */}
              <div className="h-6 flex items-center justify-center mt-1.5">
                {activeReel === 2 && (outcome?.isNearWin || outcome?.isWin) && <p className="text-[#F59E0B] font-black text-xs tracking-widest animate-pulse">⚡ ¡CASI...!</p>}
                {allDone && isWin && winPrize?.type === "free_spins" && <p className="text-[#22C55E] font-black text-xs tracking-widest animate-bounce">🎁 ¡10 TIROS GRATIS!</p>}
                {allDone && isWin && winPrize?.type !== "free_spins" && !decision && <p className="text-[#22C55E] font-black text-xs tracking-widest animate-bounce">🎉 ¡3 EN RAYA!</p>}
                {allDone && decision === "accepted" && <p className="text-[#22C55E] text-[10px] tracking-widest">✅ Premio aceptado</p>}
                {allDone && decision === "returned" && <p className="text-[#9CA3AF] text-[10px] tracking-widest">↩ Devuelto</p>}
                {allDone && !isWin && !outcome?.isNearWin && <p className="text-[#9CA3AF] text-[10px] tracking-widest">Sin suerte esta vez</p>}
                {allDone && !isWin && outcome?.isNearWin && <p className="text-[#EF4444] text-[10px] tracking-widest font-semibold">💔 ¡Tan cerca...!</p>}
              </div>
            </div>

            {/* Bottom bar */}
            <div className="flex items-center justify-center py-2.5 px-6 rounded-b-3xl" style={{ background: "linear-gradient(180deg,#131722,#1E1340)", border: "1px solid #8B5CF650", borderTop: "none" }}>
              <span className="text-[9px] text-[#9CA3AF]/50 font-medium tracking-widest">
                {isFree ? `🎁 ${freeSpins} GRATIS RESTANTES` : `${fmt(SPIN_PRICE)} / TIRADA`}
              </span>
            </div>
          </div>

          {/* Lever */}
          <Lever onPull={!isAutoSpinning ? doSpin : () => {}} disabled={isAutoSpinning} pulled={leverPulled} />
        </div>

        {/* Mobile button */}
        <div className="sm:hidden w-full">
          <button onClick={!isAutoSpinning ? doSpin : () => {}} disabled={isAutoSpinning}
            className="w-full py-4 rounded-2xl font-black text-base text-white transition-all active:scale-95 disabled:opacity-40"
            style={{ background: isSpinning ? "linear-gradient(135deg,#6D28D9,#4C1D95)" : "linear-gradient(135deg,#8B5CF6,#6D28D9)", boxShadow: isSpinning ? "none" : "0 0 24px #8B5CF640" }}>
            {isSpinning ? "⏳ Girando..." : isFree ? `🎁 Girar (GRATIS)` : `🎰 Girar (${fmt(SPIN_PRICE)})`}
          </button>
        </div>

        {/* Auto controls */}
        {!isFreeAuto && (
          <div className="w-full flex flex-col gap-2">
            <div className="flex items-center gap-2">
              <div className="flex gap-1.5">
                {AUTO_OPT.map(n => (
                  <button key={n} onClick={() => setAutoCount(n)} disabled={isAutoSpinning}
                    className="px-2.5 py-2 rounded-xl text-xs font-black transition-all disabled:opacity-40"
                    style={{ background: autoCount === n ? "#8B5CF6" : "#131722", color: autoCount === n ? "#fff" : "#9CA3AF", border: `1px solid ${autoCount === n ? "#8B5CF6" : "#ffffff10"}` }}>
                    ×{n}
                  </button>
                ))}
              </div>
              {!isAutoSpinning
                ? <button onClick={startAuto} disabled={!canSpin} className="flex-1 py-2.5 rounded-xl font-black text-xs tracking-wide transition-all hover:scale-[1.02] disabled:opacity-40" style={{ background: "linear-gradient(135deg,#6D28D9,#4C1D95)", color: "#E9D5FF", border: "1px solid #8B5CF640" }}>⚡ Auto ×{autoCount}</button>
                : <button onClick={stopAuto} className="flex-1 py-2.5 rounded-xl font-black text-xs" style={{ background: "#131722", color: "#EF4444", border: "1px solid #EF444440" }}>⏹ Detener</button>
              }
            </div>
          </div>
        )}

        {/* Win modal overlay */}
        {showWinPanel && <WinModal prize={winPrize!} onAccept={async () => {
              setDecision("accepted");
              setWaitingDecision(false);
              if (spinId) {
                await fetch(`/api/tournaments/${tournamentCode}/slot-machine/accept`, {
                  method: "POST",
                  headers: { Authorization: `Bearer ${memberToken}`, "Content-Type": "application/json" },
                  body: JSON.stringify({ spinId }),
                });
              }
            }} onReturn={async () => {
              setDecision("returned");
              setWinPrize(null);
              setWaitingDecision(false);
              if (spinId) {
                await fetch(`/api/tournaments/${tournamentCode}/slot-machine/reject`, {
                  method: "POST",
                  headers: { Authorization: `Bearer ${memberToken}`, "Content-Type": "application/json" },
                  body: JSON.stringify({ spinId }),
                });
              }
            }} />}

        {decision === "accepted" && winPrize && (
          <div className="w-full rounded-2xl p-4 text-center" style={{ border: "1px solid #22C55E40", background: "linear-gradient(135deg,#05280f,#131722)" }}>
            <p className="text-[#22C55E] font-black text-base mb-1">🏆 ¡{winPrize.name} es tuyo!</p>
            <p className="text-[#9CA3AF] text-sm">Añadido a tu plantilla.</p>
          </div>
        )}

        {/* History */}
        {history.length > 0 && (
          <div className="w-full rounded-2xl overflow-hidden" style={{ border: "1px solid #ffffff08", background: "#131722" }}>
            <div className="px-4 py-3 border-b border-white/5 flex items-center justify-between">
              <span className="text-[#9CA3AF] text-xs font-semibold tracking-widest">HISTORIAL</span>
              <span className="text-[#9CA3AF]/40 text-[10px]">{history.length} premios</span>
            </div>
            <div className="p-3 flex flex-col gap-2 max-h-36 overflow-y-auto">
              {history.map((h, i) => {
                const c = h.prize.type === "free_spins" ? "#22C55E" : h.prize.type === "icon" ? "#F59E0B" : ovrColor(h.prize.ovr);
                return (
                  <div key={i} className="flex items-center gap-3 px-3 py-2 rounded-xl" style={{ background: "#0D0F14" }}>
                    <div className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-black flex-shrink-0" style={{ background: `${c}20`, color: c }}>
                      {h.prize.type === "free_spins" ? "🎁" : h.prize.name.split(" ").map(w => w[0]).join("").slice(0, 2)}
                    </div>
                    <p className="text-[#F3F4F6] text-xs font-semibold truncate flex-1">{h.prize.name}</p>
                    <span className="text-xs font-black px-1.5 py-0.5 rounded-lg flex-shrink-0" style={{ background: `${c}20`, color: c }}>
                      {h.prize.type === "free_spins" ? "+10" : h.prize.ovr}
                    </span>
                    {h.free && <span className="text-[9px] text-[#22C55E]/60 flex-shrink-0">GRATIS</span>}
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {/* ── Pool panel — collapsible on mobile, sidebar on desktop ── */}
      <div className="w-full lg:w-auto lg:flex-shrink-0" style={{ maxWidth: '100%' }}>
        {/* Mobile toggle */}
        <button
          onClick={() => setShowPool(p => !p)}
          className="lg:hidden w-full flex items-center justify-between px-4 py-3 rounded-xl mb-2"
          style={{ background: "#131722", border: "1px solid #ffffff08" }}
        >
          <span className="text-[#F3F4F6] text-sm font-bold">📋 Pool del día</span>
          <span className="text-[#9CA3AF] text-xs">{showPool ? '▲ cerrar' : '▼ ver jugadores'}</span>
        </button>
        <div className={`flex-col gap-3 ${showPool ? 'flex' : 'hidden'} lg:flex`} style={{ width: 240, maxWidth: '100%' }}>
        <div className="flex items-center justify-between">
          <div>
            <p className="text-[#F3F4F6] text-sm font-black">Pool del día</p>
            {poolDate && <p className="text-[#9CA3AF] text-[10px]">📅 {poolDate} · se renueva a medianoche</p>}
          </div>
          <div className="w-2 h-2 rounded-full bg-[#22C55E]" style={{ boxShadow: "0 0 6px #22C55E" }} />
        </div>
        {poolData.length === 0 && !loading && <div className="text-[#9CA3AF] text-xs text-center py-4">Generando pool...</div>}
        {poolData.map(slot => {
          if (!slot.players) return null;
          const p = slot.players;
          const isClaimed = slot.status === "claimed";
          const color = p.is_icon ? "#F59E0B" : ovrColor(p.ovr);
          const initials = p.name.split(" ").map((w: string) => w[0]).join("").slice(0, 2);
          return (
            <div key={slot.id} className="flex items-center gap-2 px-2 py-1.5 rounded-lg transition-all"
              style={{ background: isClaimed ? "#0a0f0a" : "#0D0F14", opacity: isClaimed ? 0.65 : 1 }}>
              {p.headshot_url
                ? <img src={p.headshot_url} alt="" className="w-6 h-6 rounded-full object-contain flex-shrink-0" style={{ filter: isClaimed ? "grayscale(1)" : "none" }} />
                : <div className="w-6 h-6 rounded-full flex items-center justify-center text-[9px] font-black flex-shrink-0" style={{ background: `${color}20`, color }}>{initials}</div>
              }
              <div className="flex-1 min-w-0">
                <p className="text-[10px] truncate" style={{ color: isClaimed ? "#4B5563" : "#F3F4F6", textDecoration: isClaimed ? "line-through" : "none" }}>{p.name}</p>
                {isClaimed && slot.claimed_by_name && (
                  <p className="text-[8px] truncate" style={{ color: "#22C55E", opacity: 0.6 }}>✓ {slot.claimed_by_name}</p>
                )}
              </div>
              <div className="flex items-center gap-1 flex-shrink-0">
                {slot.is_premium && <span className="text-[8px]" style={{ color: "#F59E0B" }}>★</span>}
                <span className="text-[9px] font-black" style={{ color: isClaimed ? "#374151" : color }}>{p.ovr}</span>
              </div>
            </div>
          );
        })}
        <p className="text-[#9CA3AF]/40 text-[9px] text-center">Jugadores elegibles como premios hoy</p>
        </div>
      </div>
    </div>
  );
}

// ── Sub-components ────────────────────────────────────────────────────────────
function Bulbs({ reverse = false }: { reverse?: boolean }) {
  const c = reverse ? ["#22C55E","#F59E0B","#EF4444","#8B5CF6"] : ["#8B5CF6","#EF4444","#F59E0B","#22C55E"];
  return <div className="flex gap-1.5">{c.map((col, i) => <div key={i} style={{ width: 8, height: 8, borderRadius: "50%", background: col, boxShadow: `0 0 5px ${col}` }} />)}</div>;
}

function Lever({ onPull, disabled, pulled }: { onPull: () => void; disabled: boolean; pulled: boolean }) {
  return (
    <div className="hidden sm:flex flex-col items-center" style={{ userSelect: "none" }}>
      <div style={{ width: 14, height: 20, background: "linear-gradient(180deg,#4B5563,#1F2937)", borderRadius: "4px 4px 0 0", border: "1px solid #6B7280", flexShrink: 0 }} />
      <div style={{ transformOrigin: "top center", transform: pulled ? "rotate(40deg)" : "rotate(0deg)", transition: "transform 0.28s cubic-bezier(0.34,1.56,0.64,1)", display: "flex", flexDirection: "column", alignItems: "center" }}>
        <div style={{ width: 7, height: 108, background: disabled ? "linear-gradient(180deg,#374151,#1F2937)" : "linear-gradient(180deg,#C084FC,#7C3AED,#4C1D95)", borderRadius: "0 0 4px 4px", boxShadow: disabled ? "none" : "0 0 10px #8B5CF640" }} />
        <button onClick={onPull} disabled={disabled}
          style={{ width: 40, height: 40, borderRadius: "50%", border: "none", cursor: disabled ? "not-allowed" : "pointer", marginTop: -2, background: disabled ? "radial-gradient(circle at 35% 35%,#4B5563,#1F2937)" : "radial-gradient(circle at 35% 35%,#C084FC,#7C3AED,#4C1D95)", boxShadow: disabled ? "none" : "0 0 20px #8B5CF660,inset 0 2px 4px #ffffff30", display: "flex", alignItems: "center", justifyContent: "center", fontSize: 17 }}>
          🎰
        </button>
      </div>
    </div>
  );
}

function WinModal({ prize, onAccept, onReturn }: { prize: SlotPrize; onAccept: () => void; onReturn: () => void }) {
  const initials = prize.name.split(" ").map(w => w[0]).join("").slice(0, 2).toUpperCase();
  const color    = prize.type === "icon" ? "#F59E0B" : ovrColor(prize.ovr);
  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 100, background: "rgba(0,0,0,0.8)", display: "flex", alignItems: "center", justifyContent: "center", padding: 20 }}>
    <div className="w-full max-w-sm rounded-2xl overflow-hidden" style={{ border: `1px solid ${color}40`, background: `linear-gradient(135deg,${color}08,#0D0F14)`, boxShadow: `0 0 80px ${color}30` }}>
      <div className="flex items-center gap-2 px-4 py-3 border-b border-white/6"><span>🏆</span><h3 className="font-black text-sm" style={{ color }}>¡PREMIO GANADO!</h3></div>
      <div className="p-4 flex items-center gap-4">
        {prize.headshotUrl
          ? <img src={prize.headshotUrl} alt="" className="w-16 h-16 object-contain rounded-full flex-shrink-0" style={{ background: "#0D0F14", border: `2px solid ${color}40` }} />
          : <div className="w-16 h-16 rounded-full flex items-center justify-center text-lg font-black flex-shrink-0" style={{ background: `${color}15`, color, border: `2px solid ${color}40` }}>{initials}</div>
        }
        <div className="flex-1 min-w-0">
          {prize.type === "icon" && <div className="text-[10px] font-black tracking-widest mb-1" style={{ color: "#F59E0B" }}>✨ LEYENDA</div>}
          <p className="text-[#F3F4F6] font-black text-lg leading-tight">{prize.name}</p>
          <div className="flex items-center gap-2 mt-1.5">
            <span className="px-2 py-0.5 rounded-lg text-sm font-black" style={{ background: `${color}22`, color }}>{prize.ovr} OVR</span>
            <span className="text-[#9CA3AF] text-sm">{prize.position}</span>
            {((prize as any).salary ?? 0) > 0 && <span className="ml-2 text-[#22C55E] text-sm font-black">💰 {((prize as any).salary ?? 0) >= 1e6 ? `€${(((prize as any).salary)/1e6).toFixed(1)}M/sem` : `€${(((prize as any).salary)/1000).toFixed(0)}K/sem`}</span>}
          </div>
        </div>
      </div>
      <div className="flex gap-2 px-4 pb-4">
        <button onClick={onAccept} className="flex-1 py-3 rounded-xl font-black text-sm text-white active:scale-95" style={{ background: "linear-gradient(135deg,#22C55E,#16A34A)", boxShadow: "0 0 16px #22C55E40" }}>✅ Aceptar</button>
        <button onClick={onReturn} className="flex-1 py-3 rounded-xl font-black text-sm active:scale-95" style={{ background: "#0D0F14", border: "1px solid #EF444450", color: "#EF4444" }}>↩ Devolver</button>
      </div>
    </div>
    </div>
  );
}

function Fireworks() {
  return (
    <>
      <style>{`@keyframes burst{0%{transform:translate(0,0) scale(1);opacity:1}100%{transform:translate(var(--tx),var(--ty)) scale(0);opacity:0}}@keyframes rise{0%{opacity:1;transform:translateY(0)}100%{opacity:0;transform:translateY(-90px)}}`}</style>
      <div className="absolute inset-0 pointer-events-none z-50 overflow-hidden">
        {[...Array(22)].map((_, i) => {
          const a = (i/22)*360, d = 55+Math.random()*65;
          const tx = Math.cos(a*Math.PI/180)*d, ty = Math.sin(a*Math.PI/180)*d;
          const cols = ["#F59E0B","#22C55E","#8B5CF6","#EF4444","#EC4899","#06B6D4"];
          return <div key={i} style={{ position:"absolute",top:"50%",left:"50%",width:7,height:7,borderRadius:"50%",background:cols[i%cols.length],boxShadow:`0 0 5px ${cols[i%cols.length]}`,"--tx":`${tx}px`,"--ty":`${ty}px`,animation:`burst ${0.8+Math.random()*.5}s ease-out forwards`,animationDelay:`${Math.random()*.4}s`} as any} />;
        })}
        {["⭐","✨","🌟","💫","⭐"].map((s, i) => (
          <div key={i} style={{ position:"absolute",top:`${30+Math.random()*40}%`,left:`${5+i*20}%`,fontSize:18,animation:"rise 1.1s ease-out forwards",animationDelay:`${i*.12}s` }}>{s}</div>
        ))}
      </div>
    </>
  );
}
