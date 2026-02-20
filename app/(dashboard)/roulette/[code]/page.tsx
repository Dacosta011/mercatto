"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { motion, AnimatePresence } from "motion/react";
import Link from "next/link";
import RouletteWheel, { Team, SPIN_DURATION_MS } from "../../../Components/RouletteWheel";
import { getMemberToken, saveTeamAssignment } from "@/lib/tokenStorage";

type Phase = "loading" | "ready" | "spinning" | "result" | "error" | "already";

interface SpinResult {
  alreadyAssigned?: boolean;
  assigned?: boolean;
  team: Team & { budget: number; squadValue: number };
  rerollsAllowed: number;
  rerollsUsed: number;
  rerollsRemaining: number;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const PALETTE = [
  "#8B5CF6","#6366F1","#EC4899","#F59E0B",
  "#10B981","#3B82F6","#EF4444","#14B8A6",
  "#F97316","#84CC16","#06B6D4","#A855F7",
  "#E11D48","#0EA5E9","#22C55E","#F43F5E",
];

function teamColor(name: string) {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) % PALETTE.length;
  return PALETTE[Math.abs(h)];
}

function teamAbbr(name: string) {
  const w = name.split(/\s+/).filter(Boolean);
  if (w.length === 1) return name.slice(0, 2).toUpperCase();
  if (w.length === 2) return (w[0][0] + w[1][0]).toUpperCase();
  return w.map((x) => x[0]).join("").slice(0, 3).toUpperCase();
}

function fmtBudget(v: number | null | undefined) {
  if (!v || isNaN(v)) return null;
  if (v >= 1_000_000) return `€${(v / 1_000_000).toFixed(0)}M`;
  if (v >= 1_000)     return `€${(v / 1_000).toFixed(0)}K`;
  return `€${v}`;
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function RoulettePage() {
  const { code } = useParams<{ code: string }>();
  const router    = useRouter();

  const [phase,        setPhase]        = useState<Phase>("loading");
  const [teams,        setTeams]        = useState<Team[]>([]);
  const [availPool,    setAvailPool]    = useState<Team[]>([]); // teams the wheel can land on
  const [spinResult,   setSpinResult]   = useState<SpinResult | null>(null);
  const [errorMsg,     setErrorMsg]     = useState("");
  const [isSpinning,   setIsSpinning]   = useState(false);
  const [isReroll,     setIsReroll]     = useState(false);

  const wheelTeamsRef  = useRef<Team[]>([]);
  const spinning       = useRef(false);
  // Stores API result while animation plays; both must complete before showing result
  const pendingApi     = useRef<{ data: SpinResult; ok: boolean } | null>(null);
  const animDone       = useRef(false);

  const getToken = useCallback(() => {
    const t = getMemberToken(code);
    if (!t) { router.replace("/"); return null; }
    return t;
  }, [code, router]);

  // ── Load ──────────────────────────────────────────────────────────────────
  const checkAndLoad = useCallback(async () => {
    const token = getToken();
    if (!token) return;

    const res = await fetch(`/api/tournaments/${code}/spin`, {
      headers: { Authorization: `Bearer ${token}` },
    });

    if (res.ok) {
      const data: SpinResult = await res.json();
      if (data.assigned) {
        saveTeamAssignment(code, data.team.name);
        setSpinResult(data);
        setPhase("already");
        return;
      }
    }

    try {
      const r = await fetch(`/api/tournaments/${code}/teams`);
      if (!r.ok) throw new Error("No se pudieron cargar los equipos.");
      const available: Team[] = await r.json();
      setTeams(available);
      setAvailPool(available);
      if (wheelTeamsRef.current.length === 0) wheelTeamsRef.current = available;
      setPhase("ready");
    } catch (e: any) {
      setErrorMsg(e.message);
      setPhase("error");
    }
  }, [code, getToken]);

  useEffect(() => { checkAndLoad(); }, [checkAndLoad]);

  // ── Helpers para coordinar animación + API ────────────────────────────────
  const tryShowResult = useCallback(() => {
    if (!animDone.current || !pendingApi.current) return;
    const { data, ok } = pendingApi.current;
    setIsSpinning(false);
    spinning.current = false;

    if (!ok) {
      setErrorMsg((data as any)?.error ?? "Error de conexión.");
      setPhase("error");
      return;
    }
    saveTeamAssignment(code, data.team.name);
    setSpinResult(data);
    setPhase("result");
    if (data.rerollsRemaining > 0) {
      fetch(`/api/tournaments/${code}/teams`).then((r) => r.json()).then((t) => {
        setTeams(t);
        setAvailPool(t);
      }).catch(() => {});
    }
  }, [code]);

  // ── Called by RouletteWheel as soon as it picks a landing team ────────────
  const handleTeamSelected = useCallback(async (chosen: Team) => {
    const token = getToken();
    if (!token) return;

    // Start API call in parallel with the animation
    try {
      const r = await fetch(`/api/tournaments/${code}/spin`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ teamId: chosen.id, reroll: isReroll }),
      });
      const data = await r.json();
      pendingApi.current = { data, ok: r.ok };
    } catch {
      pendingApi.current = { data: { error: "Error de conexión." } as any, ok: false };
    }
    tryShowResult();
  }, [code, getToken, isReroll, tryShowResult]);

  // ── Trigger spin ──────────────────────────────────────────────────────────
  const handleSpin = () => {
    if (spinning.current || teams.length === 0) return;
    spinning.current = true;
    pendingApi.current = null;
    animDone.current   = false;
    setIsReroll(false);
    setAvailPool(teams);
    setIsSpinning(true);
    setPhase("spinning");

    // After animation ends, try to show result
    setTimeout(() => {
      animDone.current = true;
      tryShowResult();
    }, SPIN_DURATION_MS);
  };

  const handleReroll = () => {
    if (spinning.current) return;
    const cur  = spinResult?.team ?? null;
    // Include the current (freed) team back in the available pool
    const pool = cur ? [...teams.filter((t) => t.id !== cur.id), cur] : teams;
    spinning.current = true;
    pendingApi.current = null;
    animDone.current   = false;
    setIsReroll(true);
    setAvailPool(pool);
    setIsSpinning(true);
    setPhase("spinning");

    setTimeout(() => {
      animDone.current = true;
      tryShowResult();
    }, SPIN_DURATION_MS);
  };

  // ── Loading ───────────────────────────────────────────────────────────────
  if (phase === "loading") return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="flex flex-col items-center gap-3">
        <div className="w-10 h-10 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
        <p className="text-[#9CA3AF] text-sm">Preparando la ruleta…</p>
      </div>
    </div>
  );

  // ── Error ─────────────────────────────────────────────────────────────────
  if (phase === "error") return (
    <div className="min-h-screen flex items-center justify-center p-8">
      <div className="bg-[#131722] rounded-2xl border border-[#EF4444]/20 p-10 max-w-sm w-full flex flex-col items-center gap-5 text-center">
        <div className="w-12 h-12 rounded-2xl bg-[#EF4444]/10 flex items-center justify-center">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
          </svg>
        </div>
        <div>
          <p className="text-[#F3F4F6] font-semibold">Algo salió mal</p>
          <p className="text-[#9CA3AF] text-sm mt-1">{errorMsg}</p>
        </div>
        <Link href={`/lobby/${code}`}>
          <button className="px-5 py-2.5 rounded-xl bg-[#1A1F2E] text-[#F3F4F6] text-sm font-medium hover:bg-[#1A1F2E]/80 transition-colors cursor-pointer">
            Volver al Lobby
          </button>
        </Link>
      </div>
    </div>
  );

  // ── Already assigned ──────────────────────────────────────────────────────
  if (phase === "already" && spinResult) return (
    <RevealScreen
      spinResult={spinResult}
      code={code}
      isAlready
      onReroll={spinResult.rerollsRemaining > 0 ? handleReroll : undefined}
    />
  );

  // ── Main layout (ready / spinning / result) ───────────────────────────────
  const allWheelTeams = wheelTeamsRef.current.length > 0 ? wheelTeamsRef.current : teams;
  const availableIds  = new Set(teams.map((t) => t.id));

  return (
    <div className="min-h-screen flex flex-col overflow-hidden">

      {/* ── Header ── */}
      <div className="px-8 pt-8 pb-5 flex items-center justify-between gap-4 shrink-0">
        <div>
          <h1 className="text-[#F3F4F6] text-2xl font-bold tracking-tight">Ruleta de Equipos</h1>
          <p className="text-[#9CA3AF] text-sm mt-0.5">El destino asigna. El mercado castiga.</p>
        </div>

        {/* Pills */}
        <div className="flex items-center gap-2 shrink-0">
          <Pill>
            <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E]" />
            {teams.length} disponibles
          </Pill>
          {spinResult && (
            <Pill>
              <RerollIcon size={10} />
              Rerolls {spinResult.rerollsRemaining}/{spinResult.rerollsAllowed}
            </Pill>
          )}
        </div>
      </div>

      {/* ── Body: 2-col ── */}
      <div className="flex-1 px-8 pb-8 flex gap-10 items-start justify-center min-h-0">

        {/* Left: wheel + controls */}
        <div className="flex flex-col items-center gap-5 shrink-0">
          {/* Glow wrapper */}
          <div className="relative flex items-center justify-center">
            {isSpinning && (
              <div className="absolute rounded-full animate-pulse pointer-events-none"
                style={{ inset: -20, background: "radial-gradient(circle, rgba(139,92,246,0.2) 0%, transparent 65%)" }}
              />
            )}
            <RouletteWheel
              teams={allWheelTeams}
              availableTeams={availPool}
              spinning={isSpinning}
              onTeamSelected={handleTeamSelected}
            />
          </div>

          {/* CTA */}
          <div className="w-full max-w-[300px] flex flex-col gap-2.5">
            <AnimatePresence mode="wait">
              {phase === "ready" && (
                <motion.button
                  key="girar"
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -6 }}
                  transition={{ duration: 0.2 }}
                  onClick={handleSpin}
                  disabled={teams.length === 0}
                  className="w-full flex items-center justify-center gap-2.5 py-4 px-6 rounded-2xl
                    bg-[#8B5CF6] hover:bg-[#7C3AED] active:scale-[0.98]
                    text-white font-bold text-sm tracking-wide
                    shadow-lg shadow-[#8B5CF6]/30 hover:shadow-[#8B5CF6]/50
                    transition-all duration-200 disabled:opacity-40 disabled:cursor-not-allowed cursor-pointer"
                >
                  <RerollIcon size={16} />
                  Girar Ruleta
                </motion.button>
              )}

              {phase === "spinning" && (
                <motion.div
                  key="spinning"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="w-full flex items-center justify-center gap-2.5 py-4 rounded-2xl
                    bg-[#131722] border border-white/6 text-[#9CA3AF] text-sm font-medium"
                >
                  <div className="w-4 h-4 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
                  Asignando equipo…
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>

        {/* Right: teams grid OR result reveal */}
        <div className="w-[500px] shrink-0">
          <AnimatePresence mode="wait">

            {/* Result reveal panel */}
            {phase === "result" && spinResult && (
              <motion.div
                key="result"
                initial={{ opacity: 0, x: 20 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.4, ease: [0.16, 1, 0.3, 1] }}
              >
                <ResultCard
                  spinResult={spinResult}
                  code={code}
                  onReroll={spinResult.rerollsRemaining > 0 ? handleReroll : undefined}
                />
              </motion.div>
            )}

            {/* Teams grid */}
            {(phase === "ready" || phase === "spinning") && (
              <motion.div key="grid" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
                className="flex flex-col w-full">
                <div className="flex items-center justify-between mb-3 shrink-0">
                  <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest font-semibold">
                    Equipos del torneo
                  </p>
                  <span className="text-[#9CA3AF]/40 text-xs">{allWheelTeams.length} equipos</span>
                </div>

                <div className="grid grid-cols-2 gap-2 overflow-y-auto pr-1"
                  style={{ maxHeight: 480 }}>
                  {allWheelTeams.map((team) => (
                    <TeamCard
                      key={team.id ?? team.name}
                      team={team}
                      available={availableIds.has(team.id ?? "")}
                    />
                  ))}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}

// ── Sub-components ────────────────────────────────────────────────────────────

function Pill({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full
      bg-[#131722] border border-white/6 text-[#9CA3AF] text-xs font-medium">
      {children}
    </span>
  );
}

function RerollIcon({ size = 14 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="23 4 23 10 17 10"/>
      <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
    </svg>
  );
}

function TeamCard({ team, available }: { team: Team; available: boolean }) {
  const color = teamColor(team.name);
  const abbr  = teamAbbr(team.name);

  return (
    <div className={`
      flex items-center gap-3 px-3 py-2.5 rounded-xl border transition-all duration-200
      ${available
        ? "bg-[#131722] border-white/6 hover:bg-[#1A1F2E] hover:border-white/10"
        : "bg-[#0D0F14]/40 border-white/4 opacity-40"
      }
    `}>
      {/* Crest */}
      <div className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0"
        style={{ background: `${color}20`, border: `1.5px solid ${color}40` }}>
        <span className="text-[10px] font-black" style={{ color }}>{abbr}</span>
      </div>

      {/* Info */}
      <div className="flex-1 min-w-0">
        <p className={`text-xs font-semibold truncate leading-tight ${available ? "text-[#F3F4F6]" : "text-[#9CA3AF]"}`}>
          {team.name}
        </p>
        <div className="flex items-center gap-1 mt-0.5">
          {available
            ? <><span className="w-1.5 h-1.5 rounded-full bg-[#22C55E] shrink-0" /><span className="text-[#22C55E] text-[10px]">Disponible</span></>
            : <><span className="w-1.5 h-1.5 rounded-full bg-[#9CA3AF]/30 shrink-0" /><span className="text-[#9CA3AF] text-[10px]">Asignado</span></>
          }
        </div>
      </div>
    </div>
  );
}

function ResultCard({ spinResult, code, onReroll }: {
  spinResult: SpinResult;
  code: string;
  onReroll?: () => void;
}) {
  const color  = teamColor(spinResult.team.name);
  const abbr   = teamAbbr(spinResult.team.name);
  const budget = fmtBudget(spinResult.team.budget);

  return (
    <div className="rounded-3xl border overflow-hidden" style={{
      background: "#131722",
      borderColor: `${color}40`,
      boxShadow: `0 0 60px ${color}12, 0 0 120px ${color}06`,
    }}>
      {/* Accent bar */}
      <div className="h-1" style={{ background: `linear-gradient(90deg, ${color}, ${color}66)` }} />

      <div className="p-8">
        {/* Label */}
        <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest font-semibold text-center mb-7">
          ¡Equipo asignado!
        </p>

        {/* Crest + Name */}
        <div className="flex flex-col items-center gap-4 mb-7">
          <motion.div
            initial={{ scale: 0.6, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ duration: 0.5, delay: 0.1, ease: [0.16, 1, 0.3, 1] }}
            className="w-24 h-24 rounded-3xl flex items-center justify-center"
            style={{
              background: `${color}18`,
              border: `2px solid ${color}55`,
              boxShadow: `0 0 50px ${color}30`,
            }}
          >
            <span className="text-3xl font-black" style={{ color }}>{abbr}</span>
          </motion.div>

          <motion.h2
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.4, delay: 0.2 }}
            className="text-[#F3F4F6] text-3xl font-bold tracking-tight text-center"
          >
            {spinResult.team.name}
          </motion.h2>
        </div>

        {/* Budget */}
        {budget && (
          <motion.div
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35, delay: 0.3 }}
            className="flex justify-center mb-7"
          >
            <div className="bg-[#22C55E]/8 border border-[#22C55E]/20 rounded-2xl px-8 py-4 text-center">
              <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mb-1">Presupuesto asignado</p>
              <p className="text-[#22C55E] text-2xl font-bold">{budget}</p>
            </div>
          </motion.div>
        )}

        {/* Rerolls indicator */}
        {spinResult.rerollsAllowed > 0 && (
          <div className="flex items-center justify-center gap-2 mb-7">
            <span className="text-[#9CA3AF] text-xs">Rerolls restantes</span>
            <div className="flex gap-1.5">
              {Array.from({ length: spinResult.rerollsAllowed }).map((_, i) => (
                <span key={i} className={`w-2 h-2 rounded-full transition-colors ${
                  i < spinResult.rerollsRemaining ? "bg-[#8B5CF6]" : "bg-white/10"
                }`} />
              ))}
            </div>
            <span className="text-[#9CA3AF] text-xs">
              {spinResult.rerollsRemaining}/{spinResult.rerollsAllowed}
            </span>
          </div>
        )}

        {/* Actions */}
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.3, delay: 0.4 }}
          className="flex flex-col gap-2.5"
        >
          <Link href={`/lobby/${code}`}>
            <button className="w-full py-3.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED]
              text-white font-semibold text-sm transition-colors duration-200 cursor-pointer flex items-center justify-center gap-2">
              Ir al Lobby
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor"
                strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="9 18 15 12 9 6"/>
              </svg>
            </button>
          </Link>

          {onReroll && (
            <button
              onClick={onReroll}
              className="w-full py-3 rounded-xl border border-white/8 hover:bg-[#1A1F2E] hover:border-white/12
                text-[#9CA3AF] hover:text-[#F3F4F6] font-medium text-sm
                transition-all duration-200 flex items-center justify-center gap-2 cursor-pointer"
            >
              <RerollIcon size={13} />
              Volver a girar (Reroll)
            </button>
          )}
        </motion.div>
      </div>
    </div>
  );
}

// ── Full-page reveal (for "already" state) ───────────────────────────────────

function RevealScreen({ spinResult, code, isAlready, onReroll }: {
  spinResult: SpinResult;
  code: string;
  isAlready?: boolean;
  onReroll?: () => void;
}) {
  const color = teamColor(spinResult.team.name);

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 relative">
      <div className="absolute pointer-events-none" style={{
        width: 600, height: 600,
        background: `radial-gradient(circle, ${color}12 0%, transparent 65%)`,
        top: "50%", left: "50%", transform: "translate(-50%,-50%)",
      }} />
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="relative z-10 w-full max-w-md"
      >
        {isAlready && (
          <p className="text-center text-[#9CA3AF] text-xs uppercase tracking-widest mb-4">
            Ya tienes equipo asignado
          </p>
        )}
        <ResultCard spinResult={spinResult} code={code} onReroll={onReroll} />
      </motion.div>
    </div>
  );
}
