"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { motion, AnimatePresence } from "motion/react";
import SlotStrip, { Team } from "../../../Components/SlotStrip";
import { getMemberToken, saveTeamAssignment } from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";

type Phase = "loading" | "ready" | "spinning" | "result" | "confirming" | "conflict" | "locked" | "error";

// ── Helpers ───────────────────────────────────────────────────────────────────

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
  const router   = useRouter();

  const [phase,       setPhase]       = useState<Phase>("loading");
  // Full team list (never shrinks — used for grid display)
  const [allTeams,    setAllTeams]    = useState<Team[]>([]);
  const [pendingTeam, setPendingTeam] = useState<Team & { budget?: number } | null>(null);
  const [errorMsg,    setErrorMsg]    = useState("");
  const [isSpinning,  setIsSpinning]  = useState(false);

  // Reroll state — `rerollsUsedInDB` is the single source of truth. Each reroll
  // is PATCHed to the server before the animation starts, so reload no longer
  // resets the counter and the limit cannot be bypassed.
  const [rerollsAllowed,  setRerollsAllowed]  = useState(0);
  const [rerollsUsedInDB, setRerollsUsedInDB] = useState(0);
  const [wasAssigned,     setWasAssigned]      = useState(false);

  // IDs of teams taken by OTHER members (live via Realtime)
  const [takenIds, setTakenIds] = useState<Set<string>>(new Set());
  const tournamentIdRef = useRef<string | null>(null);
  const myMemberIdRef   = useRef<string | null>(null);

  const rerollsRemaining = Math.max(0, rerollsAllowed - rerollsUsedInDB);

  // Available teams = allTeams minus taken ones (but keep pending team eligible)
  const availableTeams = useMemo(() => {
    return allTeams.filter((t) => {
      if (takenIds.has(t.id ?? "")) {
        // Still allow the user's own pending team
        if (pendingTeam && t.id === pendingTeam.id) return true;
        return false;
      }
      return true;
    });
  }, [allTeams, takenIds, pendingTeam]);

  const spinning = useRef(false);

  const getToken = useCallback(() => {
    const t = getMemberToken(code);
    if (!t) { router.replace("/"); return null; }
    return t;
  }, [code, router]);

  // ── Load ──────────────────────────────────────────────────────────────────
  const load = useCallback(async () => {
    const token = getToken();
    if (!token) return;
    myMemberIdRef.current = token;

    const res  = await fetch(`/api/tournaments/${code}/spin`, { headers: { Authorization: `Bearer ${token}` } });
    const data = await res.json();

    const allowed   = data.rerollsAllowed ?? 0;
    const usedInDB  = data.rerollsUsed    ?? 0;
    const remaining = Math.max(0, allowed - usedInDB);

    setRerollsAllowed(allowed);
    setRerollsUsedInDB(usedInDB);

    if (data.assigned) {
      setWasAssigned(true);
      setPendingTeam(data.team);
      if (remaining === 0) {
        setPhase("locked");
        return;
      }
    }

    try {
      const r     = await fetch(`/api/tournaments/${code}/teams`);
      const teamsData = await r.json();
      let teams: Team[] = Array.isArray(teamsData) ? teamsData : [];

      if (data.assigned && data.team && !teams.find((t: Team) => t.id === data.team.id)) {
        teams = [...teams, data.team];
      }

      setAllTeams(teams);
      setPhase(data.assigned ? "result" : "ready");
    } catch {
      setErrorMsg("No se pudieron cargar los equipos.");
      setPhase("error");
    }
  }, [code, getToken]);

  useEffect(() => { load(); }, [load]);

  // ── Sync taken teams (Realtime + polling fallback) ──────────────────────────

  const markTaken = useCallback((takenTeamId: string) => {
    setTakenIds((prev) => {
      if (prev.has(takenTeamId)) return prev;
      const next = new Set(prev);
      next.add(takenTeamId);
      return next;
    });

    setPendingTeam((prev) => {
      if (prev && prev.id === takenTeamId) {
        setPhase("conflict");
      }
      return prev;
    });
  }, []);

  // Realtime: listen for ALL assignment changes (INSERT, UPDATE, DELETE)
  useEffect(() => {
    const supabase = getBrowserClient();

    supabase
      .from("tournaments")
      .select("id")
      .eq("code", code.toUpperCase())
      .single()
      .then(({ data }) => {
        if (data?.id) tournamentIdRef.current = data.id;
      });

    const channel = supabase
      .channel(`roulette-${code}`)
      .on(
        "postgres_changes" as any,
        { event: "*", schema: "public", table: "assignments" },
        (payload: any) => {
          const row = payload.new;
          if (!row?.team_id || !tournamentIdRef.current) return;
          if (row.tournament_id !== tournamentIdRef.current) return;
          markTaken(row.team_id as string);
        },
      )
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [code, markTaken]);

  // ── SlotStrip callback ────────────────────────────────────────────────────
  const handleTeamSelected = useCallback((winner: Team) => {
    setPendingTeam(winner as Team & { budget?: number });
    spinning.current = false;
    setIsSpinning(false);
    setPhase("result");
  }, []);

  const startSpin = (pool: Team[]) => {
    if (spinning.current || pool.length === 0) return;
    spinning.current = true;
    setIsSpinning(true);
    setPhase("spinning");
  };

  const handleFirstSpin = () => startSpin(availableTeams);

  const handleReroll = async () => {
    if (rerollsRemaining <= 0 || spinning.current) return;
    const token = getToken();
    if (!token) return;

    // Persist the reroll BEFORE animating, so a page reload mid-flow cannot
    // bypass the limit. The server enforces the cap and returns the updated
    // counter; we trust that value over the local one.
    try {
      const res = await fetch(`/api/tournaments/${code}/spin`, {
        method: "PATCH",
        headers: { Authorization: `Bearer ${token}` },
      });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) {
        if (typeof data.rerollsUsed === "number") {
          setRerollsUsedInDB(data.rerollsUsed);
        }
        return;
      }

      if (typeof data.rerollsUsed === "number") {
        setRerollsUsedInDB(data.rerollsUsed);
      }
    } catch {
      return;
    }

    startSpin(availableTeams);
  };

  const handleRespin = () => {
    // Triggered when the team the user picked got taken by someone else. This
    // is NOT a voluntary reroll, so don't charge it server-side.
    setPendingTeam(null);
    startSpin(availableTeams);
  };

  // ── Confirm ───────────────────────────────────────────────────────────────
  const handleConfirm = async () => {
    if (!pendingTeam?.id) return;

    const token = getToken();
    if (!token) return;
    setPhase("confirming");

    try {
      const r = await fetch(`/api/tournaments/${code}/spin`, {
        method:  "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body:    JSON.stringify({ teamId: pendingTeam.id, rerollsUsed: rerollsUsedInDB }),
      });
      const data = await r.json();

      if (r.status === 409) {
        setTakenIds((prev) => { const s = new Set(prev); s.add(pendingTeam.id!); return s; });
        setPhase("conflict");
        return;
      }

      if (!r.ok) {
        setErrorMsg(data?.error ?? "Error al asignar el equipo.");
        setPhase("error");
        return;
      }

      saveTeamAssignment(code, data.team.name, data.team.crestUrl);
      router.push(`/lobby/${code}`);
    } catch {
      setErrorMsg("Error de conexión.");
      setPhase("error");
    }
  };

  // ── Locked ────────────────────────────────────────────────────────────────
  if (phase === "locked" && pendingTeam) {
    return (
      <div className="min-h-dvh flex flex-col items-center justify-center p-4 sm:p-8 relative">
        <div className="absolute pointer-events-none"
          style={{ width: 600, height: 600, background: "radial-gradient(circle, #8B5CF612 0%, transparent 65%)", top: "50%", left: "50%", transform: "translate(-50%,-50%)" }} />
        <motion.div initial={{ opacity: 0, y: 24 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.5 }}
          className="relative z-10 w-full max-w-md">
          <p className="text-center text-[#9CA3AF] text-xs uppercase tracking-widest mb-4">
            Tu equipo asignado
          </p>
          <ResultCard team={pendingTeam} rerollsAllowed={rerollsAllowed} rerollsRemaining={0} />
          <button onClick={() => router.push(`/lobby/${code}`)}
            className="mt-4 w-full py-3.5 rounded-xl text-white font-semibold text-sm transition-colors cursor-pointer"
            style={{ background: "linear-gradient(135deg, #8B5CF6, #6D28D9)", boxShadow: "0 0 20px #8B5CF640" }}>
            Ir al Lobby →
          </button>
        </motion.div>
      </div>
    );
  }

  // ── Loading ───────────────────────────────────────────────────────────────
  if (phase === "loading") return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="flex flex-col items-center gap-3">
        <div className="w-10 h-10 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
        <p className="text-[#9CA3AF] text-sm">Cargando equipos…</p>
      </div>
    </div>
  );

  // ── Error ─────────────────────────────────────────────────────────────────
  if (phase === "error") return (
    <div className="min-h-dvh flex items-center justify-center p-4 sm:p-8">
      <div className="bg-[#131722] rounded-2xl border border-[#EF4444]/20 p-6 sm:p-10 max-w-sm w-full flex flex-col items-center gap-5 text-center">
        <div className="w-12 h-12 rounded-2xl bg-[#EF4444]/10 flex items-center justify-center">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
          </svg>
        </div>
        <div>
          <p className="text-[#F3F4F6] font-semibold">Algo salió mal</p>
          <p className="text-[#9CA3AF] text-sm mt-1">{errorMsg}</p>
        </div>
        <button onClick={load}
          className="px-5 py-2.5 rounded-xl bg-[#1A1F2E] text-[#F3F4F6] text-sm font-medium hover:bg-[#1A1F2E]/80 transition-colors cursor-pointer">
          Reintentar
        </button>
      </div>
    </div>
  );

  // ── Main layout ───────────────────────────────────────────────────────────
  return (
    <div className="min-h-dvh flex flex-col overflow-x-hidden">
      {/* Header */}
      <div className="px-4 sm:px-8 pt-5 sm:pt-8 pb-4 sm:pb-6 flex flex-col sm:flex-row sm:items-center justify-between gap-3 sm:gap-4 shrink-0">
        <div>
          <h1 className="text-[#F3F4F6] text-xl sm:text-2xl font-bold tracking-tight">Asignación de Equipos</h1>
          <p className="text-[#9CA3AF] text-xs sm:text-sm mt-0.5">El destino asigna. El mercado castiga.</p>
        </div>
        <div className="flex items-center gap-1.5 sm:gap-2 shrink-0 overflow-x-auto">
          <span className="inline-flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-full bg-[#131722] border border-white/6 text-[#9CA3AF] text-[11px] sm:text-xs font-medium shrink-0">
            <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E]" />
            {availableTeams.length} disponibles
          </span>
          {takenIds.size > 0 && (
            <span className="inline-flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-full bg-[#131722] border border-white/6 text-[#9CA3AF] text-[11px] sm:text-xs font-medium shrink-0">
              <span className="w-1.5 h-1.5 rounded-full bg-[#EF4444]/60" />
              {takenIds.size} asignados
            </span>
          )}
          {rerollsAllowed > 0 && (
            <span className="inline-flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-full bg-[#131722] border border-white/6 text-[#9CA3AF] text-[11px] sm:text-xs font-medium shrink-0">
              <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
              </svg>
              Rerolls {rerollsRemaining}/{rerollsAllowed}
            </span>
          )}
        </div>
      </div>

      {/* Body */}
      <div className="flex-1 flex flex-col items-center px-4 sm:px-8 pb-6 sm:pb-8 gap-5 sm:gap-8">

        {/* Strip + CTA */}
        <div className="flex flex-col items-center gap-5 w-full">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest font-semibold">
            Selección aleatoria
          </p>

          <div className="relative">
            {isSpinning && (
              <div className="absolute -inset-8 pointer-events-none rounded-3xl"
                style={{ background: "radial-gradient(ellipse, #8B5CF618 0%, transparent 70%)" }} />
            )}
            <SlotStrip
              teams={availableTeams}
              availableTeams={availableTeams}
              spinning={isSpinning}
              onTeamSelected={handleTeamSelected}
            />
          </div>

          {/* Action buttons */}
          <AnimatePresence mode="wait">
            {phase === "ready" && (
              <motion.button
                key="spin-btn"
                initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -8 }}
                transition={{ duration: 0.2 }}
                onClick={handleFirstSpin}
                disabled={availableTeams.length === 0}
                className="flex items-center gap-2.5 px-12 py-4 rounded-2xl text-white font-bold text-sm tracking-wide transition-all duration-200 cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
                style={{ background: "linear-gradient(135deg, #8B5CF6, #6D28D9)", boxShadow: "0 0 24px #8B5CF640, 0 4px 16px #6D28D940" }}
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
                </svg>
                Asignar equipo
              </motion.button>
            )}

            {phase === "spinning" && (
              <motion.div key="spinning-state" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
                className="flex items-center gap-2.5 px-12 py-4 rounded-2xl bg-[#131722] border border-white/6 text-[#9CA3AF] text-sm font-medium">
                <div className="w-4 h-4 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
                Girando…
              </motion.div>
            )}

            {phase === "conflict" && pendingTeam && (
              <motion.div key="conflict-msg" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }} className="flex flex-col items-center gap-3 w-full max-w-sm">
                <div className="flex items-center gap-2 px-4 py-3 rounded-xl bg-[#EF4444]/8 border border-[#EF4444]/20 text-sm w-full">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                    <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
                  </svg>
                  <span className="text-[#F3F4F6]">
                    <strong>{pendingTeam.name}</strong> fue tomado por otro jugador.
                  </span>
                </div>
                <button onClick={handleRespin}
                  className="w-full py-3.5 rounded-xl text-white font-semibold text-sm transition-colors cursor-pointer flex items-center justify-center gap-2"
                  style={{ background: "linear-gradient(135deg, #8B5CF6, #6D28D9)", boxShadow: "0 0 16px #8B5CF630" }}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
                  </svg>
                  Girar de nuevo
                </button>
              </motion.div>
            )}

            {(phase === "result" || phase === "confirming") && pendingTeam && (
              <motion.div key="result-actions" initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }} transition={{ duration: 0.35, ease: [0.16, 1, 0.3, 1] }}
                className="flex flex-col items-center gap-3 w-full max-w-sm">

                {rerollsAllowed > 0 && (
                  <div className="flex items-center gap-2">
                    {Array.from({ length: rerollsAllowed }).map((_, i) => (
                      <span key={i} className={`w-2 h-2 rounded-full transition-all ${i < rerollsRemaining ? "bg-[#8B5CF6]" : "bg-white/10"}`} />
                    ))}
                    <span className="text-[#9CA3AF] text-xs ml-1">
                      {rerollsRemaining} reroll{rerollsRemaining !== 1 ? "s" : ""} disponible{rerollsRemaining !== 1 ? "s" : ""}
                    </span>
                  </div>
                )}

                <div className="flex gap-2 w-full">
                  <button
                    onClick={handleConfirm}
                    disabled={phase === "confirming"}
                    className="flex-1 py-3.5 rounded-xl text-white font-semibold text-sm transition-colors cursor-pointer disabled:opacity-60 flex items-center justify-center gap-2"
                    style={{ background: "linear-gradient(135deg, #8B5CF6, #6D28D9)", boxShadow: "0 0 16px #8B5CF630" }}
                  >
                    {phase === "confirming" ? (
                      <><div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />Confirmando…</>
                    ) : (
                      <>Ir al Lobby →</>
                    )}
                  </button>

                  {rerollsRemaining > 0 && phase !== "confirming" && (
                    <button onClick={handleReroll}
                      className="flex-1 py-3.5 rounded-xl border border-white/8 hover:bg-[#1A1F2E] text-[#9CA3AF] hover:text-[#F3F4F6] font-medium text-sm transition-all flex items-center justify-center gap-2 cursor-pointer">
                      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                        <polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
                      </svg>
                      Reroll
                    </button>
                  )}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>

        {/* Divider */}
        <div className="w-full max-w-3xl h-px bg-white/4" />

        {/* Bottom: result card OR teams grid (always show full list) */}
        <div className="w-full max-w-3xl">
          <AnimatePresence mode="wait">
            {(phase === "result" || phase === "confirming") && pendingTeam && (
              <motion.div key="result-card" initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0 }} transition={{ duration: 0.45, ease: [0.16, 1, 0.3, 1] }}
                className="flex justify-center">
                <div className="w-full max-w-sm">
                  <ResultCard
                    team={pendingTeam}
                    rerollsAllowed={rerollsAllowed}
                    rerollsRemaining={rerollsRemaining}
                    preview
                  />
                </div>
              </motion.div>
            )}

            {(phase === "ready" || phase === "spinning" || phase === "conflict") && (
              <motion.div key="teams-grid" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
                <div className="flex items-center justify-between mb-4">
                  <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest font-semibold">Todos los equipos</p>
                  <span className="text-[#9CA3AF]/40 text-xs">
                    {availableTeams.length} disponibles · {takenIds.size} asignados
                  </span>
                </div>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                  {allTeams.map((team) => (
                    <TeamCard
                      key={team.id ?? team.name}
                      team={team}
                      available={!takenIds.has(team.id ?? "")}
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

// ── Sub-components ─────────────────────────────────────────────────────────────

function TeamCard({ team, available }: { team: Team; available: boolean }) {
  const abbr = teamAbbr(team.name);
  return (
    <div className={`flex items-center gap-3 px-3 py-2.5 rounded-xl border transition-all duration-300
      ${available
        ? "bg-[#131722] border-white/6 hover:bg-[#1A1F2E] hover:border-white/10"
        : "bg-[#0D0F14]/60 border-white/4 opacity-40"
      }`}>
      {team.crestUrl ? (
        <img src={team.crestUrl} alt={team.name}
          className={`w-8 h-8 object-contain shrink-0 transition-all duration-300 ${available ? "" : "grayscale"}`} />
      ) : (
        <div className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 border transition-all duration-300
          ${available ? "bg-[#8B5CF6]/15 border-[#8B5CF6]/25" : "bg-white/5 border-white/10"}`}>
          <span className={`text-[10px] font-black ${available ? "text-[#8B5CF6]" : "text-[#6B7280]"}`}>{abbr}</span>
        </div>
      )}
      <div className="flex-1 min-w-0">
        <p className={`text-xs font-semibold truncate leading-tight transition-colors duration-300 ${available ? "text-[#F3F4F6]" : "text-[#6B7280] line-through"}`}>
          {team.name}
        </p>
        <div className="flex items-center gap-1 mt-0.5">
          {available ? (
            <>
              <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E] shrink-0" />
              <span className="text-[#22C55E] text-[10px]">Disponible</span>
            </>
          ) : (
            <>
              <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#6B7280" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
              </svg>
              <span className="text-[#6B7280] text-[10px]">Asignado</span>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function ResultCard({
  team,
  rerollsAllowed,
  rerollsRemaining,
  preview,
}: {
  team: Team & { budget?: number };
  rerollsAllowed: number;
  rerollsRemaining: number;
  preview?: boolean;
}) {
  const budget = fmtBudget(team.budget);
  const abbr   = teamAbbr(team.name);

  return (
    <div className="rounded-3xl border overflow-hidden"
      style={{
        background:  "#131722",
        borderColor: preview ? "#8B5CF660" : "#8B5CF630",
        boxShadow:   preview ? "0 0 60px #8B5CF620" : "0 0 40px #8B5CF610",
      }}>
      <div className="h-1" style={{ background: "linear-gradient(90deg, #8B5CF6, #6D28D9)" }} />

      <div className="p-5 sm:p-8 flex flex-col items-center gap-5 sm:gap-6">
        {preview && (
          <span className="text-[10px] uppercase tracking-widest font-semibold px-3 py-1 rounded-full bg-[#8B5CF6]/12 text-[#8B5CF6] border border-[#8B5CF6]/20">
            Vista previa — pendiente de confirmar
          </span>
        )}

        <motion.div
          initial={{ scale: 0.5, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ duration: 0.5, delay: 0.1, ease: [0.16, 1, 0.3, 1] }}
          className="relative"
        >
          <div className="w-32 h-32 rounded-3xl flex items-center justify-center"
            style={{ background: "#8B5CF618", border: "2px solid #8B5CF640", boxShadow: "0 0 60px #8B5CF630" }}>
            {team.crestUrl ? (
              <img src={team.crestUrl} alt={team.name} className="w-20 h-20 object-contain drop-shadow-lg" />
            ) : (
              <span className="text-4xl font-black text-[#8B5CF6]">{abbr}</span>
            )}
          </div>
          <div className="absolute inset-0 rounded-3xl pointer-events-none animate-pulse"
            style={{ border: "1px solid #8B5CF640" }} />
        </motion.div>

        <motion.h2
          initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.2 }}
          className="text-[#F3F4F6] text-2xl sm:text-3xl font-bold tracking-tight text-center"
        >
          {team.name}
        </motion.h2>

        {budget && (
          <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.35, delay: 0.3 }}>
            <div className="bg-[#22C55E]/8 border border-[#22C55E]/20 rounded-2xl px-6 sm:px-8 py-3 sm:py-4 text-center">
              <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mb-1">Presupuesto</p>
              <p className="text-[#22C55E] text-2xl font-bold">{budget}</p>
            </div>
          </motion.div>
        )}

        {rerollsAllowed > 0 && (
          <div className="flex items-center gap-1.5">
            {Array.from({ length: rerollsAllowed }).map((_, i) => (
              <span key={i} className={`w-1.5 h-1.5 rounded-full transition-colors ${i < rerollsRemaining ? "bg-[#8B5CF6]" : "bg-white/10"}`} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
