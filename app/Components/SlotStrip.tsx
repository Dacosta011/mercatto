"use client";

import { useEffect, useRef, useState, useCallback } from "react";
import { animate, useMotionValue } from "motion/react";

export interface Team {
  id?: string;
  name: string;
  crestUrl?: string | null;
  squadValue?: number | string;
  budget?: number | string;
}

export const SPIN_DURATION_MS = 4000;

const CARD_W   = 148;
const GAP      = 12;
const PITCH    = CARD_W + GAP;
export const VIEWPORT = 600;
const REPEATS  = 24;

function teamAbbr(name: string) {
  const w = name.split(/\s+/).filter(Boolean);
  if (w.length === 1) return name.slice(0, 2).toUpperCase();
  if (w.length === 2) return (w[0][0] + w[1][0]).toUpperCase();
  return w.map((z) => z[0]).join("").slice(0, 3).toUpperCase();
}

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function normalizeX(x: number, n: number): number {
  if (n === 0) return x;
  const period = n * PITCH;
  const safeMin = -6 * period;
  const safeMax = -3 * period;
  let v = x;
  while (v < safeMin) v += period;
  while (v > safeMax) v -= period;
  return v;
}

function calcCenteredIndex(finalX: number, n: number): number {
  const i = (VIEWPORT / 2 - CARD_W / 2 - finalX) / PITCH;
  const idx = Math.round(i);
  return ((idx % n) + n) % n;
}

interface Props {
  teams: Team[];
  availableTeams: Team[];
  spinning: boolean;
  onTeamSelected: (team: Team) => void;
}

export default function SlotStrip({ teams, availableTeams, spinning, onTeamSelected }: Props) {
  const x         = useMotionValue(0);
  const didSpin   = useRef(false);
  const idleRef   = useRef<ReturnType<typeof animate> | null>(null);
  const looping   = useRef(false);
  const hasResult = useRef(false);

  // Shuffled order — only set on first load and reshuffled on each spin.
  // NEVER reshuffle on parent re-renders (teams prop reference changes)
  // to avoid visual jumps after a spin result.
  const [order, setOrder] = useState<Team[]>([]);
  const initialized = useRef(false);

  useEffect(() => {
    if (!initialized.current && teams.length > 0) {
      setOrder(shuffle(teams));
      initialized.current = true;
    }
  }, [teams.length]);

  const n     = order.length || 1;
  const strip = Array.from({ length: REPEATS }, () => order).flat();

  // Initialise x
  useEffect(() => {
    x.set(normalizeX(-(4 * n * PITCH), n));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [n]);

  // ── Idle loop ──────────────────────────────────────────────────────────────
  const startIdle = useCallback(() => {
    if (looping.current) return;
    looping.current = true;

    const tick = () => {
      const safe   = normalizeX(x.get(), n);
      x.set(safe);
      const target = safe - n * PITCH;

      idleRef.current = animate(x, target, {
        duration:   14,
        ease:       "linear",
        onComplete: () => {
          x.set(safe);
          tick();
        },
      });
    };

    tick();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [n]);

  const stopIdle = () => {
    idleRef.current?.stop();
    idleRef.current = null;
    looping.current = false;
  };

  useEffect(() => {
    if (spinning || order.length === 0 || hasResult.current) {
      stopIdle();
      return;
    }
    startIdle();
    return stopIdle;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spinning, order.length]);

  // ── Spin ───────────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!spinning || teams.length === 0 || availableTeams.length === 0) return;
    if (didSpin.current) return;
    didSpin.current = true;

    stopIdle();

    // Reshuffle the strip order so each spin looks completely different
    const newOrder = shuffle(teams);
    setOrder(newOrder);
    const nn = newOrder.length;

    // Normalise position for the new order length
    const currentX = normalizeX(x.get(), nn);
    x.set(currentX);

    // Pick random target from the available pool
    const chosen    = availableTeams[Math.floor(Math.random() * availableTeams.length)];
    const targetIdx = newOrder.findIndex((t) => t.name === chosen.name);
    const safeIdx   = targetIdx >= 0 ? targetIdx : 0;

    const MIN_LOOPS = 8;
    const period    = nn * PITCH;
    const minTravel = MIN_LOOPS * period;
    const landAt    = VIEWPORT / 2 - CARD_W / 2 - safeIdx * PITCH;
    const m         = Math.ceil((landAt - currentX + minTravel) / period);
    const finalX    = landAt - m * period;

    animate(x, finalX, {
      duration:   SPIN_DURATION_MS / 1000,
      ease:       [0.08, 0.92, 0.3, 1] as any,
      onComplete: () => {
        const actualX = x.get();
        const idx     = calcCenteredIndex(actualX, nn);
        const winner  = newOrder[idx] ?? chosen;
        x.set(normalizeX(actualX, nn));
        hasResult.current = true;
        onTeamSelected(winner);
      },
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [spinning]);

  useEffect(() => {
    if (!spinning) didSpin.current = false;
    if (spinning) hasResult.current = false;
  }, [spinning]);

  const wrapperRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const measure = () => {
      if (!wrapperRef.current) return;
      const available = wrapperRef.current.clientWidth;
      setScale(available >= VIEWPORT ? 1 : available / VIEWPORT);
    };
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);

  const scaledHeight = (CARD_W + 24) * scale;

  if (order.length === 0) return null;

  return (
    <div ref={wrapperRef} className="w-full" style={{ height: scaledHeight }}>
      <div
        className="relative origin-top-left"
        style={{
          width: VIEWPORT,
          height: CARD_W + 24,
          overflow: "hidden",
          transform: scale < 1 ? `scale(${scale})` : undefined,
          transformOrigin: "top center",
          marginLeft: scale < 1 ? `calc(50% - ${VIEWPORT / 2 * scale}px)` : undefined,
        }}
      >
        <StripInner x={x} strip={strip} />

        {/* Side fades */}
        <div className="absolute left-0 top-0 bottom-0 z-10 pointer-events-none"
          style={{ width: 228, background: "linear-gradient(to right, #0D0F14 50%, transparent 100%)" }} />
        <div className="absolute right-0 top-0 bottom-0 z-10 pointer-events-none"
          style={{ width: 228, background: "linear-gradient(to left, #0D0F14 50%, transparent 100%)" }} />

        {/* Center selector frame */}
        <div className="absolute z-20 pointer-events-none"
          style={{
            top: 4, bottom: 4,
            left: "50%",
            width: CARD_W + 8,
            transform: "translateX(-50%)",
            border: "2px solid #8B5CF6",
            borderRadius: 22,
            boxShadow: "0 0 0 1px #8B5CF620, 0 0 32px #8B5CF650, 0 0 64px #8B5CF620",
            background: "linear-gradient(180deg, #8B5CF608 0%, transparent 100%)",
          }} />

        {/* Top / bottom depth */}
        <div className="absolute inset-x-0 top-0 h-3 z-10 pointer-events-none"
          style={{ background: "linear-gradient(to bottom, #0D0F14, transparent)" }} />
        <div className="absolute inset-x-0 bottom-0 h-3 z-10 pointer-events-none"
          style={{ background: "linear-gradient(to top, #0D0F14, transparent)" }} />
      </div>
    </div>
  );
}

function StripInner({ x, strip }: { x: ReturnType<typeof useMotionValue<number>>; strip: Team[] }) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    return x.on("change", (v) => {
      if (ref.current) ref.current.style.transform = `translateX(${v}px)`;
    });
  }, [x]);

  return (
    <div
      ref={ref}
      style={{ display: "flex", gap: GAP, position: "absolute", top: 12, left: 0, willChange: "transform" }}
    >
      {strip.map((team, i) => <SlotCard key={i} team={team} />)}
    </div>
  );
}

function SlotCard({ team }: { team: Team }) {
  const abbr = teamAbbr(team.name);
  return (
    <div style={{ width: CARD_W, height: CARD_W, flexShrink: 0 }}
      className="rounded-2xl bg-[#131722] border border-white/8 flex flex-col items-center justify-center gap-3 select-none">
      {team.crestUrl ? (
        <img src={team.crestUrl} alt={team.name}
          className="w-14 h-14 object-contain drop-shadow-md" draggable={false} />
      ) : (
        <div className="w-14 h-14 rounded-xl bg-[#8B5CF6]/15 border border-[#8B5CF6]/25 flex items-center justify-center">
          <span className="text-[#8B5CF6] text-base font-black">{abbr}</span>
        </div>
      )}
      <p className="text-[#F3F4F6] text-xs font-semibold text-center leading-tight px-3 line-clamp-2">
        {team.name}
      </p>
    </div>
  );
}
