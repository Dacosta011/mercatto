"use client";
import { useEffect, useRef, useMemo } from "react";
import { animate, useMotionValue } from "motion/react";
import type { SlotPrize } from "@/app/api/slot-machine/prizes/route";

const CARD_H      = 160;
const GAP         = 10;
const PITCH       = CARD_H + GAP;      // 170
const VIEWPORT    = 204;
const CENTER_Y    = (VIEWPORT - CARD_H) / 2;   // 22px

// Strip layout: ABOVE copies before the anchor, then BELOW copies after.
// Downward scroll uses the ABOVE copies as runway.
const ABOVE       = 12;   // copies above anchor (runway for downward scroll)
const BELOW       = 4;    // buffer below anchor
const TOTAL       = ABOVE + 1 + BELOW;   // 17

// How many full loops to spin through before stopping
const MIN_LOOPS   = 9;    // must be <= ABOVE
// C_final: the copy where the winner lands (scrolling from copy ABOVE down to copy C_final)
const C_FINAL     = ABOVE - MIN_LOOPS;   // = 3

interface Props {
  prizes:    SlotPrize[];
  spinning:  boolean;
  winner:    SlotPrize | null;
  delay?:    number;
  slowDown?: boolean;
  onDone?:   () => void;
}

export default function SlotColumn({ prizes, spinning, winner, delay = 0, slowDown = false, onDone }: Props) {
  const y     = useMotionValue(0);
  const ctrl  = useRef<ReturnType<typeof animate> | null>(null);
  const spun  = useRef(false);
  const glow  = useRef<HTMLDivElement>(null);

  // ── Build strip ONCE, never reshuffle — no state, no re-renders ───────────
  const order = useMemo(() => {
    if (prizes.length === 0) return [];
    const a = [...prizes];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }, [prizes]);   // only rebuilds if prizes array reference changes (i.e. on first load)

  const n     = order.length || 1;
  const strip = useMemo(() => Array.from({ length: TOTAL }, () => order).flat(), [order]);

  // ── Anchor position: card 0 of copy ABOVE is at CENTER_Y ─────────────────
  // y_anchor = CENTER_Y - ABOVE * n * PITCH
  const anchorY = useMemo(() => CENTER_Y - ABOVE * n * PITCH, [n]);

  // Set y to anchor on first render and when order changes
  useEffect(() => {
    if (order.length > 0) y.set(anchorY);
  }, [anchorY]);   // eslint-disable-line

  // ── Spin animation ────────────────────────────────────────────────────────
  useEffect(() => {
    if (!spinning || !winner || order.length === 0) return;
    if (spun.current) return;
    spun.current = true;

    ctrl.current?.stop();

    // Find winner in the EXISTING order (no shuffle = no re-render = no dark flash)
    let winIdx = order.findIndex(p => p.id === winner.id);
    if (winIdx < 0) winIdx = 0;   // fallback

    // Target: copy C_FINAL, card winIdx, centered
    // finalY = CENTER_Y - (C_FINAL * n + winIdx) * PITCH
    // Since C_FINAL < ABOVE, finalY > anchorY (scrolling DOWN = v increases)
    const finalY = CENTER_Y - (C_FINAL * n + winIdx) * PITCH;

    if (slowDown && glow.current) {
      glow.current.style.borderColor = "#F59E0B";
      glow.current.style.boxShadow = "0 0 28px #F59E0B90, 0 0 56px #F59E0B40";
      glow.current.style.animation = "nearGlow .55s ease-in-out infinite alternate";
    }

    const duration = slowDown ? 10.5 : 6.0;
    // Bezier: [x1,y1,x2,y2] — fast burst then dramatic crawl to a stop
    // y1 close to 1 = fast start; x2 close to 1 = most time spent decelerating
    const ease = slowDown
      ? [0.0, 0.96, 0.1, 1.0] as any
      : [0.0, 0.94, 0.18, 1.0] as any;

    const t = setTimeout(() => {
      ctrl.current = animate(y, finalY, {
        duration, ease,
        onComplete: () => {
          y.set(finalY);
          if (glow.current) {
            glow.current.style.borderColor = "#8B5CF6";
            glow.current.style.boxShadow = "0 0 18px #8B5CF650";
            glow.current.style.animation = "none";
          }
          onDone?.();
        },
      });
    }, delay);

    return () => { clearTimeout(t); ctrl.current?.stop(); };
  }, [spinning]);   // eslint-disable-line

  useEffect(() => {
    if (!spinning) {
      spun.current = false;
      ctrl.current?.stop();
      if (glow.current) {
        glow.current.style.borderColor = "#8B5CF6";
        glow.current.style.boxShadow = "0 0 18px #8B5CF650";
        glow.current.style.animation = "none";
      }
    }
  }, [spinning]);

  // ── DOM strip renderer ────────────────────────────────────────────────────
  const stripRef = useRef<HTMLDivElement>(null);
  useEffect(() => y.on("change", (v: number) => {
    if (stripRef.current) stripRef.current.style.transform = `translateY(${v}px)`;
  }), [y]);

  if (order.length === 0) return (
    <div style={{ width: 150, height: VIEWPORT, borderRadius: 14, background: "#131722", border: "1px solid rgba(255,255,255,.07)" }} />
  );

  return (
    <div style={{ width: 150, height: VIEWPORT, position: "relative", overflow: "hidden", borderRadius: 14 }}>
      {/* Strip — rendered directly, not as a child component, to avoid re-renders */}
      <div ref={stripRef} style={{ position: "absolute", top: 0, left: 0, right: 0, display: "flex", flexDirection: "column", gap: GAP, willChange: "transform" }}>
        {strip.map((p, i) => <PrizeCard key={i} prize={p} />)}
      </div>

      {/* Top/bottom fades — hide any partial cards at edges */}
      <div style={{ position: "absolute", inset: "0 0 auto", height: 52, background: "linear-gradient(to bottom,#060810 30%,transparent)", zIndex: 10, pointerEvents: "none" }} />
      <div style={{ position: "absolute", inset: "auto 0 0", height: 52, background: "linear-gradient(to top,#060810 30%,transparent)", zIndex: 10, pointerEvents: "none" }} />

      {/* Selector frame — separate ref for direct DOM mutation to avoid re-renders */}
      <div ref={glow} style={{
        position: "absolute", zIndex: 20, pointerEvents: "none",
        top: CENTER_Y - 3, height: CARD_H + 6, left: 2, right: 2,
        border: "2px solid #8B5CF6", borderRadius: 14,
        boxShadow: "0 0 18px #8B5CF650",
        transition: "border-color .3s, box-shadow .3s",
      }} />

      <style>{`
        @keyframes nearGlow {
          from { box-shadow: 0 0 18px #F59E0B60 }
          to   { box-shadow: 0 0 42px #F59E0BAA, 0 0 72px #F59E0B50 }
        }
      `}</style>
    </div>
  );
}

function ovrColor(ovr: number) {
  if (ovr >= 87) return "#22C55E"; if (ovr >= 84) return "#84CC16";
  if (ovr >= 80) return "#F59E0B"; if (ovr >= 75) return "#FB923C";
  return "#9CA3AF";
}

function PrizeCard({ prize }: { prize: SlotPrize }) {
  const initials = prize.name.split(/\s+/).filter(Boolean).map(w => w[0]).join("").slice(0, 2).toUpperCase();

  if (prize.type === "free_spins") return (
    <div style={{ height: CARD_H, flexShrink: 0, borderRadius: 12, background: "linear-gradient(135deg,#0d2818,#131722)", border: "1px solid #22C55E30", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 6, userSelect: "none" }}>
      <span style={{ fontSize: 26 }}>🎁</span>
      <span style={{ color: "#22C55E", fontSize: 9, fontWeight: 900, letterSpacing: ".15em" }}>10 TIROS GRATIS</span>
      <div style={{ display: "flex", gap: 3 }}>{[...Array(4)].map((_, i) => <div key={i} style={{ width: 4, height: 4, borderRadius: "50%", background: "#22C55E", boxShadow: "0 0 4px #22C55E" }} />)}</div>
    </div>
  );

  const color = ovrColor(prize.ovr);
  return (
    <div style={{ height: CARD_H, flexShrink: 0, borderRadius: 12, background: "#131722", border: "1px solid rgba(255,255,255,.07)", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 5, userSelect: "none", padding: "0 8px" }}>
      {prize.headshotUrl
        ? <img src={prize.headshotUrl} alt="" style={{ width: 52, height: 52, objectFit: "contain", borderRadius: "50%", flexShrink: 0 }} draggable={false} />
        : <div style={{ width: 52, height: 52, borderRadius: "50%", background: prize.type === "icon" ? "#F59E0B18" : "#8B5CF618", border: `1px solid ${prize.type === "icon" ? "#F59E0B33" : "#8B5CF633"}`, display: "flex", alignItems: "center", justifyContent: "center", flexShrink: 0 }}>
            <span style={{ color: prize.type === "icon" ? "#F59E0B" : "#8B5CF6", fontSize: 14, fontWeight: 900 }}>{initials}</span>
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
