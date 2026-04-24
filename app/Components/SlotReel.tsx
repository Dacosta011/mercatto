"use client";
/**
 * SlotReel v2 — clean, professional, sequential
 *
 * KEY FIXES:
 * - spinKey prop: resets reel only at start of new game (not when active→false after completion)
 * - Stays on winner card after animation ends (no reset on deactivation)
 * - Correct downward scroll math
 * - Single card visible (tight viewport), crystal clear result
 */
import { useMemo, useEffect, useRef } from "react";
import type { SlotPrize } from "@/app/api/slot-machine/prizes/route";

const CARD_H  = 164;
const GAP     = 8;
const PITCH   = CARD_H + GAP;   // 172
const VIEW_H  = CARD_H + 36;    // 200 — shows the winner + tiny peek at neighbours
const FADE_H  = 48;             // gradient fade height, hides partial cards

// Strip: N_BEFORE copies before the anchor, N_SPIN copies of runway, N_AFTER buffer
// We scroll DOWNWARD: translateY increases (strip moves down, cards fall from top).
// We start deep (large negative Y) and end at less-negative Y (winner near top of strip).
//
// initY: copy N_BEFORE + N_SPIN is centered (= we start deep into the strip)
// finalY: copy N_BEFORE, card winIdx, is centered  (= we land near the top)
// Since finalY > initY, strip moves DOWN — cards visually fall.
const N_BEFORE = 3;    // copies above landing zone (buffer — so we never show empty space at top)
const N_SPIN   = 10;   // copies of runway to spin through
const N_AFTER  = 2;    // copies below start position (buffer)
// Total copies needed: N_BEFORE + N_SPIN + N_AFTER
const N_TOTAL  = N_BEFORE + N_SPIN + N_AFTER;

// Y where winner card top should sit so card is centered in viewport
const WIN_TOP = (VIEW_H - CARD_H) / 2;   // 18px

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
  spinKey:  number;   // increments each game — triggers reset
  fast?:    boolean;  // skip long animation
}

export default function SlotReel({ prizes, active, winner, slowDown, onDone, spinKey, fast = false }: SlotReelProps) {
  // Stable shuffled order — rebuilds only if prizes reference changes
  const order = useMemo(() => prizes.length ? shuffle(prizes) : [], [prizes]);
  const n     = order.length || 1;
  const strip = useMemo(
    () => Array.from({ length: N_TOTAL }, () => order).flat(),
    [order]
  );

  // Y positions
  // initY: card 0 of copy (N_BEFORE + N_SPIN) centered — this is where we START (deep in strip)
  const initY  = useMemo(() => WIN_TOP - (N_BEFORE + N_SPIN) * n * PITCH, [n]);
  // finalY(winIdx): card winIdx of copy N_BEFORE centered — this is where we LAND
  const landY  = useCallback((winIdx: number) => WIN_TOP - N_BEFORE * n * PITCH - winIdx * PITCH, [n]);

  // DOM refs — direct mutation for zero re-renders during animation
  const stripEl = useRef<HTMLDivElement>(null);
  const frameEl = useRef<HTMLDivElement>(null);
  const animRef = useRef<Animation | null>(null);

  // State refs
  const hasSpun    = useRef(false);
  const isFinished = useRef(false);   // true after this reel completed (keep final position)

  // ── Reset on new game (spinKey change) ─────────────────────────────────────
  useEffect(() => {
    // Cancel any running animation
    animRef.current?.cancel();
    animRef.current = null;
    hasSpun.current    = false;
    isFinished.current = false;

    // Return strip to init position
    if (stripEl.current) stripEl.current.style.transform = `translateY(${initY}px)`;

    // Reset frame style
    if (frameEl.current) {
      frameEl.current.style.borderColor = "#8B5CF6";
      frameEl.current.style.boxShadow   = "0 0 18px #8B5CF650";
      frameEl.current.style.animation   = "none";
    }
  }, [spinKey]);   // eslint-disable-line

  // Also set initY when n changes (prizes loaded)
  useEffect(() => {
    if (!isFinished.current && stripEl.current) {
      stripEl.current.style.transform = `translateY(${initY}px)`;
    }
  }, [initY]);

  // ── Spin when active becomes true ──────────────────────────────────────────
  useEffect(() => {
    if (!active || !winner || !stripEl.current || order.length === 0) return;
    if (hasSpun.current) return;
    hasSpun.current = true;

    const winIdx = Math.max(0, order.findIndex(p => p.id === winner.id));
    const final  = landY(winIdx);

    // Near-win glow
    if (slowDown && frameEl.current) {
      frameEl.current.style.borderColor = "#F59E0B";
      frameEl.current.style.boxShadow   = "0 0 30px #F59E0B90, 0 0 60px #F59E0B40";
      frameEl.current.style.animation   = "reelNear .6s ease-in-out infinite alternate";
    }

    const duration = fast ? 350 : slowDown ? 7000 : 3200;
    // Heavy ease-out: starts screaming fast, crawls to a stop
    const easing = slowDown
      ? "cubic-bezier(0.0, 0.97, 0.06, 1.0)"
      : fast ? "linear" : "cubic-bezier(0.0, 0.95, 0.15, 1.0)";

    animRef.current = stripEl.current.animate(
      [
        { transform: `translateY(${initY}px)` },
        { transform: `translateY(${final}px)`  },
      ],
      { duration, easing, fill: "forwards" }
    );

    animRef.current.onfinish = () => {
      // Lock position permanently
      if (stripEl.current) {
        stripEl.current.style.transform = `translateY(${final}px)`;
        animRef.current?.cancel();
      }
      isFinished.current = true;

      // Victory frame
      if (frameEl.current) {
        frameEl.current.style.borderColor = slowDown ? "#F59E0B" : "#8B5CF6";
        frameEl.current.style.boxShadow   = slowDown ? "0 0 24px #F59E0B80" : "0 0 20px #8B5CF660";
        frameEl.current.style.animation   = "none";
      }

      onDone();
    };
  }, [active]);   // eslint-disable-line

  // ── IMPORTANT: do NOT reset when active→false (that would move the reel back!)
  // The reel stays on its final card after finishing. Only spinKey triggers reset.

  if (!order.length) return (
    <div style={{ width: 154, height: VIEW_H, borderRadius: 14, background: "#131722", border: "1px solid rgba(255,255,255,.07)" }} />
  );

  return (
    <div style={{ width: 154, height: VIEW_H, position: "relative", overflow: "hidden", borderRadius: 14 }}>
      {/* Strip — no state changes during animation */}
      <div ref={stripEl} style={{ position: "absolute", top: 0, left: 0, right: 0, display: "flex", flexDirection: "column", gap: GAP, willChange: "transform" }}>
        {strip.map((p, i) => <ReelCard key={i} prize={p} />)}
      </div>

      {/* Fades — hide partial cards at top and bottom */}
      <div style={{ position: "absolute", inset: "0 0 auto", height: FADE_H, background: "linear-gradient(to bottom, #060810 40%, transparent)", zIndex: 10, pointerEvents: "none" }} />
      <div style={{ position: "absolute", inset: "auto 0 0", height: FADE_H, background: "linear-gradient(to top, #060810 40%, transparent)", zIndex: 10, pointerEvents: "none" }} />

      {/* Selector frame — mutated directly via ref */}
      <div ref={frameEl} style={{
        position: "absolute", zIndex: 20, pointerEvents: "none",
        top: WIN_TOP - 3, height: CARD_H + 6, left: 3, right: 3,
        border: "2px solid #8B5CF6", borderRadius: 14,
        boxShadow: "0 0 18px #8B5CF650",
      }} />

      <style>{`
        @keyframes reelNear {
          from { box-shadow: 0 0 20px #F59E0B60 }
          to   { box-shadow: 0 0 48px #F59E0BAA, 0 0 90px #F59E0B50 }
        }
      `}</style>
    </div>
  );
}

// useCallback polyfill for useMemo in this context
function useCallback<T extends (...args: any[]) => any>(fn: T, deps: any[]): T {
  return useMemo(() => fn, deps);  // eslint-disable-line
}

// ── Card ──────────────────────────────────────────────────────────────────────
function ovrColor(ovr: number) {
  if (ovr >= 87) return "#22C55E"; if (ovr >= 84) return "#84CC16";
  if (ovr >= 80) return "#F59E0B"; if (ovr >= 75) return "#FB923C";
  return "#9CA3AF";
}

function ReelCard({ prize }: { prize: SlotPrize }) {
  const initials = prize.name.split(/\s+/).filter(Boolean).map(w => w[0]).join("").slice(0, 2).toUpperCase();

  if (prize.type === "free_spins") return (
    <div style={{ height: CARD_H, flexShrink: 0, borderRadius: 12, background: "linear-gradient(135deg,#0d2818,#131722)", border: "1px solid #22C55E30", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 6, userSelect: "none" }}>
      <span style={{ fontSize: 28 }}>🎁</span>
      <span style={{ color: "#22C55E", fontSize: 9, fontWeight: 900, letterSpacing: ".15em" }}>10 TIROS GRATIS</span>
    </div>
  );

  const color = ovrColor(prize.ovr);
  return (
    <div style={{ height: CARD_H, flexShrink: 0, borderRadius: 12, background: "#131722", border: "1px solid rgba(255,255,255,.07)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 5, userSelect: "none", padding: "0 8px" }}>
      {prize.headshotUrl
        ? <img src={prize.headshotUrl} alt="" style={{ width: 54, height: 54, objectFit: "contain", borderRadius: "50%", flexShrink: 0 }} draggable={false} />
        : <div style={{ width: 54, height: 54, borderRadius: "50%", background: prize.type === "icon" ? "#F59E0B18" : "#8B5CF618", border: `1px solid ${prize.type === "icon" ? "#F59E0B33" : "#8B5CF633"}`, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
            <span style={{ color: prize.type === "icon" ? "#F59E0B" : "#8B5CF6", fontSize: 15, fontWeight: 900 }}>{initials}</span>
          </div>
      }
      {prize.type === "icon" && <span style={{ color: "#F59E0B", fontSize: 8, fontWeight: 900, letterSpacing: ".15em" }}>LEYENDA</span>}
      <p style={{ color: "#F3F4F6", fontSize: 10, fontWeight: 600, textAlign: "center", lineHeight: 1.25, margin: 0, maxWidth: "100%", overflow: "hidden", display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical" }}>{prize.name}</p>
      <div style={{ display: "flex", gap: 4, alignItems: "center" }}>
        <span style={{ background: color + "22", color, fontSize: 9, fontWeight: 900, padding: "2px 6px", borderRadius: 5 }}>{prize.ovr}</span>
        <span style={{ color: "#9CA3AF", fontSize: 9 }}>{prize.position}</span>
      </div>
    </div>
  );
}
