"use client";

import { useEffect, useRef, useState } from "react";
import { motion } from "motion/react";

export interface Team {
  id?: string;
  name: string;
  abbr?: string;
  squadValue: number | string;
  budget: number | string;
}

// ── Palette – violet monochromatic ────────────────────────────────────────────
const COLORS = [
  { bg: "#8B5CF6", text: "#ffffff" },
  { bg: "#6D28D9", text: "#ffffff" },
  { bg: "#7C3AED", text: "#ffffff" },
  { bg: "#4C1D95", text: "#ede9fe" },
];

const SIZE    = 560;
const CX      = SIZE / 2;
const CY      = SIZE / 2;
const R_OUTER = 262;
const R_INNER = 36;

export const SPIN_DURATION_MS = 3600;

function polar(cx: number, cy: number, r: number, deg: number) {
  const rad = ((deg - 90) * Math.PI) / 180;
  return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
}

function slicePath(cx: number, cy: number, rOuter: number, rInner: number, startDeg: number, endDeg: number) {
  const s1 = polar(cx, cy, rOuter, startDeg);
  const e1 = polar(cx, cy, rOuter, endDeg);
  const s2 = polar(cx, cy, rInner, endDeg);
  const e2 = polar(cx, cy, rInner, startDeg);
  const large = endDeg - startDeg > 180 ? 1 : 0;
  return [
    `M ${e2.x.toFixed(2)} ${e2.y.toFixed(2)}`,
    `L ${s1.x.toFixed(2)} ${s1.y.toFixed(2)}`,
    `A ${rOuter} ${rOuter} 0 ${large} 1 ${e1.x.toFixed(2)} ${e1.y.toFixed(2)}`,
    `L ${s2.x.toFixed(2)} ${s2.y.toFixed(2)}`,
    `A ${rInner} ${rInner} 0 ${large} 0 ${e2.x.toFixed(2)} ${e2.y.toFixed(2)}`,
    "Z",
  ].join(" ");
}

function nameFontSize(name: string, segCount: number): number {
  const base = segCount > 14 ? 9.5 : segCount > 10 ? 11 : 13;
  if (name.length > 16) return base - 1.5;
  if (name.length > 10) return base;
  return base + 1.5;
}

interface Props {
  /** All teams to display on the wheel */
  teams: Team[];
  /** Only these teams can be selected (subset of teams) */
  availableTeams: Team[];
  /** Set to true to trigger a spin */
  spinning: boolean;
  /**
   * Called immediately when the wheel has picked a landing team
   * (before animation finishes) so the parent can start the API call in parallel.
   */
  onTeamSelected: (team: Team) => void;
}

export default function RouletteWheel({ teams, availableTeams, spinning, onTeamSelected }: Props) {
  const [rotation, setRotation] = useState(0);
  const rotRef        = useRef(0);
  const didSelect     = useRef(false); // prevent double-firing

  const count    = teams.length || 1;
  const segAngle = 360 / count;

  // When spinning becomes true: pick a random team from availableTeams,
  // calculate the target rotation, and immediately notify the parent.
  useEffect(() => {
    if (!spinning || teams.length === 0 || availableTeams.length === 0) return;
    if (didSelect.current) return;
    didSelect.current = true;

    // Pick a random team from the available pool
    const chosen = availableTeams[Math.floor(Math.random() * availableTeams.length)];

    // Find its index in the full wheel array (for visual positioning)
    const idx = teams.findIndex(
      (t) => t.name.toLowerCase() === chosen.name.toLowerCase()
    );
    const targetIdx = idx >= 0 ? idx : Math.floor(Math.random() * teams.length);

    // Calculate final rotation: land needle exactly at center of target segment
    const midAngle  = (targetIdx + 0.5) * segAngle;
    const finalOff  = (360 - (midAngle % 360)) % 360;
    const extraSpins = 6 + Math.floor(Math.random() * 3); // 6–8 full rotations
    const newRotation = rotRef.current + extraSpins * 360 + finalOff;

    rotRef.current = newRotation;
    setRotation(newRotation);

    // Notify parent immediately → they start the API call in parallel
    onTeamSelected(chosen);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spinning]);

  // Reset the guard when spinning stops
  useEffect(() => {
    if (!spinning) didSelect.current = false;
  }, [spinning]);

  if (teams.length === 0) {
    return (
      <div className="rounded-full border border-white/10 flex items-center justify-center"
        style={{ width: SIZE, height: SIZE, background: "#131722" }}>
        <div className="w-8 h-8 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="relative flex items-center justify-center select-none"
      style={{ width: SIZE, height: SIZE }}>

      {/* Ambient glow */}
      <div className="absolute inset-0 rounded-full pointer-events-none" style={{
        background: "radial-gradient(circle, rgba(139,92,246,0.13) 0%, transparent 68%)",
      }} />

      {/* Outer rings */}
      <div className="absolute rounded-full border-2 border-white/8 pointer-events-none"
        style={{ width: SIZE + 10, height: SIZE + 10, top: -5, left: -5 }} />
      <div className="absolute rounded-full border border-white/4 pointer-events-none"
        style={{ width: SIZE + 22, height: SIZE + 22, top: -11, left: -11 }} />

      {/* Needle */}
      <div className="absolute z-30 pointer-events-none"
        style={{ top: -4, left: "50%", transform: "translateX(-50%)" }}>
        <svg width="36" height="46" viewBox="0 0 36 46" fill="none">
          <defs>
            <linearGradient id="needle-grad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#C4B5FD" />
              <stop offset="100%" stopColor="#7C3AED" />
            </linearGradient>
          </defs>
          <path d="M18 44 L2 5 Q18 -3 34 5 Z" fill="url(#needle-grad)"
            filter="drop-shadow(0 4px 12px rgba(139,92,246,0.8))" />
          <circle cx="18" cy="8" r="5" fill="#F3F4F6" opacity="0.9" />
        </svg>
      </div>

      {/* Spinning wheel */}
      <motion.div
        animate={{ rotate: rotation }}
        transition={{ duration: SPIN_DURATION_MS / 1000, ease: [0.12, 0.9, 0.3, 1] }}
        style={{ width: SIZE, height: SIZE, borderRadius: "50%", position: "relative" }}
      >
        <svg viewBox={`0 0 ${SIZE} ${SIZE}`} width={SIZE} height={SIZE}>
          <defs>
            <radialGradient id="hub-grad" cx="40%" cy="35%" r="65%">
              <stop offset="0%" stopColor="#4C1D95" />
              <stop offset="100%" stopColor="#1a1a2e" />
            </radialGradient>
          </defs>

          {/* Segments */}
          {teams.map((team, i) => {
            const startDeg = i * segAngle;
            const endDeg   = (i + 1) * segAngle;
            const midDeg   = (i + 0.5) * segAngle;
            const col      = COLORS[i % COLORS.length];
            const textPos  = polar(CX, CY, R_OUTER * 0.62, midDeg);
            const fontSize = nameFontSize(team.name, count);

            return (
              <g key={`seg-${i}`}>
                <path
                  d={slicePath(CX, CY, R_OUTER, R_INNER + 2, startDeg, endDeg)}
                  fill={col.bg}
                  stroke="#0D0F14"
                  strokeWidth="1.5"
                />
                <path
                  d={slicePath(CX, CY, R_OUTER - 1, R_OUTER - 8, startDeg, endDeg)}
                  fill="rgba(255,255,255,0.07)"
                  stroke="none"
                />
                <text
                  x={textPos.x}
                  y={textPos.y}
                  textAnchor="middle"
                  dominantBaseline="middle"
                  fill={col.text}
                  fontSize={fontSize}
                  fontWeight="700"
                  fontFamily="system-ui, -apple-system, sans-serif"
                  letterSpacing="0.03em"
                  transform={`rotate(${midDeg - 90}, ${textPos.x}, ${textPos.y})`}
                >
                  {team.name}
                </text>
              </g>
            );
          })}

          {/* Tick marks */}
          {teams.map((_, i) => {
            const p1 = polar(CX, CY, R_OUTER - 1, i * segAngle);
            const p2 = polar(CX, CY, R_OUTER - 10, i * segAngle);
            return <line key={`tick-${i}`} x1={p1.x} y1={p1.y} x2={p2.x} y2={p2.y}
              stroke="#0D0F14" strokeWidth="2" />;
          })}

          {/* Hub */}
          <circle cx={CX} cy={CY} r={R_INNER + 10} fill="#0D0F14" opacity="0.4" />
          <circle cx={CX} cy={CY} r={R_INNER + 6} fill="url(#hub-grad)" />
          <circle cx={CX} cy={CY} r={R_INNER + 6} fill="none" stroke="#8B5CF6" strokeWidth="2" opacity="0.7" />
          <circle cx={CX} cy={CY} r={R_INNER + 2} fill="none" stroke="#C4B5FD" strokeWidth="0.5" opacity="0.4" />
          <circle cx={CX} cy={CY} r={8} fill="#8B5CF6" opacity="0.9" />
          <circle cx={CX} cy={CY} r={4} fill="#C4B5FD" />
        </svg>
      </motion.div>
    </div>
  );
}
