"use client";
import { useMemo, useEffect, useRef } from "react";
import type { SlotPrize } from "@/app/api/slot-machine/prizes/route";

// ── Sizes — two modes ─────────────────────────────────────────────────────────
const SIZES = {
  sm: { CARD_W: 108, CARD_H: 130, GAP: 6, FADE: 36 },
  md: { CARD_W: 154, CARD_H: 164, GAP: 8, FADE: 48 },
};

const N_BEFORE = 3;
const N_SPIN   = 10;
const N_AFTER  = 2;
const N_TOTAL  = N_BEFORE + N_SPIN + N_AFTER;

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export interface SlotReelProps {
  prizes:   SlotPrize[];
  active:   boolean;
  winner:   SlotPrize | null;
  slowDown: boolean;
  onDone:   () => void;
  spinKey:  number;
  fast?:    boolean;
  small?:   boolean;   // mobile size
}

export default function SlotReel({ prizes, active, winner, slowDown, onDone, spinKey, fast = false, small = false }: SlotReelProps) {
  const S = small ? SIZES.sm : SIZES.md;
  const { CARD_H, GAP, FADE } = S;
  const CARD_W = S.CARD_W;
  const PITCH  = CARD_H + GAP;
  const VIEW_H = CARD_H + (small ? 24 : 36);
  const WIN_TOP = (VIEW_H - CARD_H) / 2;

  const order = useMemo(() => prizes.length ? shuffle(prizes) : [], [prizes]);
  const n     = order.length || 1;
  const strip = useMemo(() => Array.from({ length: N_TOTAL }, () => order).flat(), [order]);

  const initY  = useMemo(() => WIN_TOP - (N_BEFORE + N_SPIN) * n * PITCH, [n, WIN_TOP, PITCH]);
  const landY  = (winIdx: number) => WIN_TOP - N_BEFORE * n * PITCH - winIdx * PITCH;

  const stripEl = useRef<HTMLDivElement>(null);
  const frameEl = useRef<HTMLDivElement>(null);
  const animRef     = useRef<Animation | null>(null);
  const slowDownRef = useRef(slowDown);
  const lastYRef    = useRef<number | null>(null);   // last resting y position
  const lastWinIdxRef = useRef<number | null>(null); // winner index in strip from last spin
  const hasSpun    = useRef(false);
  const isFinished = useRef(false);

  // Always read latest slowDown (avoids stale closure in useEffect)
  slowDownRef.current = slowDown;

  // Reset on new game
  useEffect(() => {
    animRef.current?.cancel();
    animRef.current = null;
    hasSpun.current    = false;
    isFinished.current = false;
    // Reposition strip to same last winner but at a safe initY-equivalent position (no visible jump)
    if (lastWinIdxRef.current !== null && stripEl.current) {
      // Show same card but from a position that gives N_SPIN loops of runway
      const period = n * PITCH;
      const safeY = WIN_TOP - (N_BEFORE + N_SPIN) * n * PITCH - lastWinIdxRef.current * PITCH;
      stripEl.current.style.transform = `translateY(${safeY}px)`;
      lastYRef.current = safeY;
    }
    if (frameEl.current) {
      frameEl.current.style.borderColor = "#8B5CF6";
      frameEl.current.style.boxShadow   = "0 0 18px #8B5CF650";
      frameEl.current.style.animation   = "none";
    }
  }, [spinKey]);

  // Set initial position only on very first mount (no previous spin)
  useEffect(() => {
    if (lastYRef.current === null && stripEl.current) {
      stripEl.current.style.transform = `translateY(${initY}px)`;
    }
  }, []);   // eslint-disable-line

  // Spin
  useEffect(() => {
    if (!active || !winner || !stripEl.current || order.length === 0) return;
    if (hasSpun.current) return;
    hasSpun.current = true;

    const winIdx = Math.max(0, order.findIndex(p => p.id === winner.id));
    const final  = landY(winIdx);  // kept for landY reference, adjustedFinal used for animation

    const sd = slowDown;
    if (sd && frameEl.current) {
      frameEl.current.style.borderColor = "#F59E0B";
      frameEl.current.style.boxShadow   = "0 0 30px #F59E0B90, 0 0 60px #F59E0B40";
      frameEl.current.style.animation   = "reelNear .6s ease-in-out infinite alternate";
    }

    const duration = fast ? 350 : sd ? 7000 : 3200;
    const easing   = fast ? "linear" : sd
      ? "cubic-bezier(0.0, 0.97, 0.06, 1.0)"
      : "cubic-bezier(0.0, 0.95, 0.15, 1.0)";

    // Start from last known y (keep continuity) or initY if first spin
    const startY = lastYRef.current ?? initY;
    // Ensure we scroll at least N_SPIN loops forward from startY
    const period = n * PITCH;
    const minAdvance = 8 * period;   // at least 8 full loops
    // Re-compute final relative to startY
    const baseLandY = WIN_TOP - N_BEFORE * n * PITCH - winIdx * PITCH;
    const copiesNeeded = Math.max(0, Math.ceil((startY + minAdvance - baseLandY) / period));
    const adjustedFinal = baseLandY + copiesNeeded * period;

    // Snap strip to startY before animating (in case of drift)
    stripEl.current.style.transform = `translateY(${startY}px)`;

    animRef.current = stripEl.current.animate(
      [
        { transform: `translateY(${startY}px)` },
        { transform: `translateY(${adjustedFinal}px)` },
      ],
      { duration, easing, fill: "forwards" }
    );

    animRef.current.onfinish = () => {
      if (stripEl.current) { stripEl.current.style.transform = `translateY(${adjustedFinal}px)`; animRef.current?.cancel(); }
      lastYRef.current = adjustedFinal;   // remember where we stopped
      lastWinIdxRef.current = winIdx;    // remember which card index won
      isFinished.current = true;
      if (frameEl.current && sd) {
        frameEl.current.style.borderColor = "#F59E0B";
        frameEl.current.style.boxShadow   = "0 0 24px #F59E0B80";
        frameEl.current.style.animation   = "none";
      }
      onDone();
    };
  }, [active, slowDown]);

  useEffect(() => {
    if (!active) { hasSpun.current = false; animRef.current?.cancel(); }
  }, [active]);

  // Strip dom
  const stripRef2 = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = stripEl.current;
    if (el) el.style.transform = `translateY(${initY}px)`;
  }, []);

  if (!order.length) return <div style={{ width: CARD_W, height: VIEW_H, borderRadius: 12, background: "#131722" }} />;

  return (
    <div style={{ width: CARD_W, height: VIEW_H, position: "relative", overflow: "hidden", borderRadius: 12 }}>
      <div ref={stripEl} style={{ position: "absolute", top: 0, left: 0, right: 0, display: "flex", flexDirection: "column", gap: GAP, willChange: "transform" }}>
        {strip.map((p, i) => <ReelCard key={i} prize={p} cardH={CARD_H} cardW={CARD_W} small={small} />)}
      </div>

      {/* Fades */}
      <div style={{ position: "absolute", inset: "0 0 auto", height: FADE, background: "linear-gradient(to bottom,#060810 35%,transparent)", zIndex: 10, pointerEvents: "none" }} />
      <div style={{ position: "absolute", inset: "auto 0 0", height: FADE, background: "linear-gradient(to top,#060810 35%,transparent)", zIndex: 10, pointerEvents: "none" }} />

      {/* Frame */}
      <div ref={frameEl} style={{
        position: "absolute", zIndex: 20, pointerEvents: "none",
        top: WIN_TOP - 2, height: CARD_H + 4, left: 2, right: 2,
        border: "2px solid #8B5CF6", borderRadius: 12,
        boxShadow: "0 0 18px #8B5CF650",
      }} />

      <style>{`@keyframes reelNear{from{box-shadow:0 0 20px #F59E0B60}to{box-shadow:0 0 44px #F59E0BAA,0 0 80px #F59E0B50}}`}</style>
    </div>
  );
}

function ovrColor(ovr: number) {
  if (ovr >= 87) return "#22C55E"; if (ovr >= 84) return "#84CC16";
  if (ovr >= 80) return "#F59E0B"; if (ovr >= 75) return "#FB923C";
  return "#9CA3AF";
}

function ReelCard({ prize, cardH, cardW, small }: { prize: SlotPrize; cardH: number; cardW: number; small: boolean }) {
  const initials = prize.name.split(/\s+/).filter(Boolean).map(w => w[0]).join("").slice(0, 2).toUpperCase();
  const imgSize  = small ? 40 : 54;
  const nameSize = small ? 9 : 10;
  const badgeSize = small ? 8 : 9;

  if (prize.type === "free_spins") return (
    <div style={{ height: cardH, flexShrink: 0, borderRadius: 10, background: "linear-gradient(135deg,#0d2818,#131722)", border: "1px solid #22C55E30", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 4, userSelect: "none" }}>
      <span style={{ fontSize: small ? 20 : 26 }}>🎁</span>
      <span style={{ color: "#22C55E", fontSize: small ? 7 : 9, fontWeight: 900, letterSpacing: ".1em", textAlign: "center" }}>TIROS GRATIS</span>
    </div>
  );

  const color = ovrColor(prize.ovr);
  return (
    <div style={{ height: cardH, flexShrink: 0, borderRadius: 10, background: "#131722", border: "1px solid rgba(255,255,255,.07)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: small ? 3 : 5, userSelect: "none", padding: "0 6px" }}>
      {prize.headshotUrl
        ? <img src={prize.headshotUrl} alt="" style={{ width: imgSize, height: imgSize, objectFit: "contain", borderRadius: "50%", flexShrink: 0 }} draggable={false} />
        : <div style={{ width: imgSize, height: imgSize, borderRadius: "50%", background: prize.type === "icon" ? "#F59E0B18" : "#8B5CF618", border: `1px solid ${prize.type === "icon" ? "#F59E0B33" : "#8B5CF633"}`, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
            <span style={{ color: prize.type === "icon" ? "#F59E0B" : "#8B5CF6", fontSize: small ? 11 : 14, fontWeight: 900 }}>{initials}</span>
          </div>
      }
      {prize.type === "icon" && <span style={{ color: "#F59E0B", fontSize: 7, fontWeight: 900 }}>LEYENDA</span>}
      <p style={{ color: "#F3F4F6", fontSize: nameSize, fontWeight: 600, textAlign: "center", lineHeight: 1.2, margin: 0, maxWidth: "100%", overflow: "hidden", display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical" }}>{prize.name}</p>
      <div style={{ display: "flex", gap: 3, alignItems: "center" }}>
        <span style={{ background: color + "22", color, fontSize: badgeSize, fontWeight: 900, padding: "1px 5px", borderRadius: 4 }}>{prize.ovr}</span>
        <span style={{ color: "#9CA3AF", fontSize: badgeSize }}>{prize.position}</span>
      </div>
    </div>
  );
}
