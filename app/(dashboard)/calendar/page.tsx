"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "motion/react";
import { getLastTournamentCode, getMemberToken, getAdminToken } from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";
import type { RealtimeChannel } from "@supabase/supabase-js";

// ── Types ──────────────────────────────────────────────────────────────────────
interface MemberInfo { id: string; displayName: string; teamName: string; crestUrl?: string | null }
interface Fixture {
  id: string; matchday: number; status: string;
  homeMember: MemberInfo; awayMember: MemberInfo;
  homeConfirmed: boolean; awayConfirmed: boolean;
  homeGoals: number | null; awayGoals: number | null;
  homeYellow: number; awayYellow: number; homeRed: number; awayRed: number;
  resultSubmitterId: string | null;
  pendingHomeGoals: number | null; pendingAwayGoals: number | null;
  pendingCards: PlayerCard[];
  pendingHomeYellow: number | null; pendingAwayYellow: number | null;
  pendingHomeRed: number | null; pendingAwayRed: number | null;
  startedAt: string | null; finishedAt: string | null;
  postponeRequestedBy: string | null;
  reactivateRequestedBy: string | null;
}
interface LeagueState {
  status: string;
  session: { id: string; currentMatchday: number; totalMatchdays: number } | null;
  tournamentName: string;
  isAdmin: boolean;
  myMemberId: string;
  currentFixtures: Fixture[];
  allFixtures: Fixture[];
  restMember: MemberInfo | null;
  myDiscipline: { yellows: number; reds: number; suspended: boolean; yellowsToSuspension: number; suspendedPlayers?: { playerName: string; reason: string; matchesRemaining: number }[] };
  currentMatchdayFinished: boolean;
}

// ── Types ──────────────────────────────────────────────────────────────────────
interface SquadPlayer { id: string; name: string; position: string; ovr: number; suspended?: boolean }
interface SquadData { memberId: string; displayName: string; teamName: string; players: SquadPlayer[] }
interface PlayerCard { playerId: string; playerName: string; cardType: "yellow" | "red"; memberId: string }

interface ResultForm {
  homeGoals: string;
  awayGoals: string;
  cards: PlayerCard[];
}

const defaultForm = (): ResultForm => ({ homeGoals: "0", awayGoals: "0", cards: [] });

function StatusPill({ status }: { status: string }) {
  const cfg: Record<string, { label: string; color: string; bg: string }> = {
    pending:     { label: "Pendiente",  color: "#9CA3AF", bg: "#9CA3AF15" },
    in_progress: { label: "En Curso",   color: "#F59E0B", bg: "#F59E0B15" },
    finished:    { label: "Finalizado", color: "#22C55E", bg: "#22C55E15" },
    postponed:   { label: "Aplazado",   color: "#3B82F6", bg: "#3B82F615" },
  };
  const c = cfg[status] ?? cfg.pending;
  return (
    <span className="text-[10px] font-bold px-2 py-0.5 rounded-full"
      style={{ color: c.color, background: c.bg }}>
      {c.label}
    </span>
  );
}

function NumberInput({ label, value, onChange }: { label: string; value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex flex-col gap-1">
      <label className="text-[#9CA3AF] text-[10px] uppercase tracking-wider font-medium">{label}</label>
      <input
        type="number" min={0} max={99} value={value}
        onKeyDown={(e) => { if (e.key === "-" || e.key === "e") e.preventDefault(); }}
        onChange={(e) => {
          const n = parseInt(e.target.value);
          if (e.target.value === "") { onChange("0"); return; }
          if (isNaN(n) || n < 0) return;
          onChange(String(Math.min(n, 99)));
        }}
        className="w-full bg-[#0D0F14] border border-white/8 rounded-xl px-3 py-2 text-[#F3F4F6] text-sm font-semibold text-center focus:outline-none focus:border-[#8B5CF6]/50"
      />
    </div>
  );
}

function Modal({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm"
      onClick={onClose}>
      <motion.div initial={{ scale: 0.95, opacity: 0 }} animate={{ scale: 1, opacity: 1 }}
        exit={{ scale: 0.95, opacity: 0 }} transition={{ type: "spring", stiffness: 400, damping: 30 }}
        className="bg-[#131722] rounded-2xl border border-white/8 p-6 w-full max-w-md shadow-2xl"
        onClick={(e) => e.stopPropagation()}>
        {children}
      </motion.div>
    </motion.div>
  );
}

export default function CalendarPage() {
  const router = useRouter();
  const [code, setCode] = useState<string | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [adminToken, setAdminToken] = useState<string | null>(null);
  const [data, setData] = useState<LeagueState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [viewMatchday, setViewMatchday] = useState<number | null>(null);
  const [activeModal, setActiveModal] = useState<{ type: string; fixture?: Fixture } | null>(null);
  const [form, setForm] = useState<ResultForm>(defaultForm());
  const [squads, setSquads] = useState<{ home: SquadData | null; away: SquadData | null } | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [closingMatchday, setClosingMatchday] = useState(false);
  const [suspensionWarning, setSuspensionWarning] = useState<{ fixtureId: string; players: { playerName: string; reason: string; matchesRemaining: number }[] } | null>(null);
  const [winterModal, setWinterModal] = useState(false);
  const [winterForm, setWinterForm] = useState({ durationHours: 24, budgetInjection: 100, winterMaxTransfers: 3, winterClauseProtection: 1 });
  const [winterSubmitting, setWinterSubmitting] = useState(false);
  const [marketSessionStatus, setMarketSessionStatus] = useState<string | null>(null);
  const channelRef = useRef<RealtimeChannel | null>(null);
  const fetchingRef = useRef(false);

  useEffect(() => {
    const c = getLastTournamentCode();
    const t = c ? getMemberToken(c) : null;
    const at = c ? getAdminToken(c) : null;
    setCode(c); setToken(t); setAdminToken(at);
  }, []);

  const prevMatchdayRef = useRef<number | null>(null);
  const prevStatusRef   = useRef<string | null>(null);

  const fetchData = useCallback(async (silent = false) => {
    if (!code || !token) return;
    if (fetchingRef.current) return;
    fetchingRef.current = true;
    if (!silent) setLoading(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/league`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) { setError("Error al cargar el calendario."); return; }
      const d: LeagueState = await res.json();
      setData(d);

      // Redirect only if we witnessed the transition to finished (was active → now finished)
      if (d.status === "finished" && prevStatusRef.current && prevStatusRef.current !== "finished") {
        setTimeout(() => router.push("/table"), 1800);
      }
      prevStatusRef.current = d.status;

      if (d.session) {
        const newMd = d.session.currentMatchday;
        // Auto-jump to new current matchday when it advances
        if (prevMatchdayRef.current !== null && newMd !== prevMatchdayRef.current) {
          setViewMatchday(newMd);
        }
        // Initial load: go to current matchday
        if (prevMatchdayRef.current === null) {
          setViewMatchday(newMd);
        }
        prevMatchdayRef.current = newMd;
      }
      setError("");
    } catch { setError("Error de conexión."); }
    finally { fetchingRef.current = false; setLoading(false); }
  }, [code, token, router]);

  useEffect(() => {
    if (!code || !token) return;
    const supabase = getBrowserClient();

    fetchData(false).then(() => {
      setData((prev) => {
        if (!prev?.session?.id) return prev;
        const sessionId = prev.session.id;
        if (channelRef.current) supabase.removeChannel(channelRef.current);
        channelRef.current = supabase
          .channel(`league:${sessionId}`)
          .on("postgres_changes", { event: "*", schema: "public", table: "fixtures", filter: `session_id=eq.${sessionId}` }, () => fetchData(true))
          .on("postgres_changes", { event: "*", schema: "public", table: "league_sessions", filter: `id=eq.${sessionId}` }, () => fetchData(true))
          .subscribe();
        return prev;
      });
    });

    return () => {
      if (channelRef.current) { getBrowserClient().removeChannel(channelRef.current); channelRef.current = null; }
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [code, token]);

  const doConfirmStart = async (fixtureId: string) => {
    if (!code || !token) return;
    setSubmitting(true);
    try {
      await fetch(`/api/tournaments/${code}/league/fixtures/${fixtureId}/confirm-start`, {
        method: "POST", headers: { Authorization: `Bearer ${token}` },
      });
      await fetchData(true);
    } finally { setSubmitting(false); }
  };

  const confirmStart = (fixtureId: string) => {
    const suspended = data?.myDiscipline?.suspendedPlayers ?? [];
    if (suspended.length > 0) {
      setSuspensionWarning({ fixtureId, players: suspended });
    } else {
      doConfirmStart(fixtureId);
    }
  };

  const openResultModal = async (fixture: Fixture, type: "result" | "force" | "confirm") => {
    setForm(defaultForm());
    setSquads(null);
    setActiveModal({ type, fixture });
    if (code && token) {
      try {
        const res = await fetch(`/api/tournaments/${code}/league/fixtures/${fixture.id}/squads`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (res.ok) setSquads(await res.json());
      } catch { /* squads optional */ }
    }
  };

  const submitResult = async (fixtureId: string, action: "submit" | "confirm" | "dispute") => {
    if (!code || !token) return;
    setSubmitting(true);
    try {
      const body = action === "dispute"
        ? { confirm: false }
        : action === "confirm"
          ? { confirm: true, cards: form.cards }
          : {
              homeGoals: Math.max(0, parseInt(form.homeGoals) || 0),
              awayGoals: Math.max(0, parseInt(form.awayGoals) || 0),
              cards: form.cards,
            };
      await fetch(`/api/tournaments/${code}/league/fixtures/${fixtureId}/result`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify(body),
      });
      setActiveModal(null);
      await fetchData(true);
    } finally { setSubmitting(false); }
  };

  const forceValidate = async (fixtureId: string) => {
    if (!code || !adminToken) return;
    setSubmitting(true);
    try {
      await fetch(`/api/tournaments/${code}/league/fixtures/${fixtureId}/result`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${adminToken}` },
        body: JSON.stringify({
          homeGoals: Math.max(0, parseInt(form.homeGoals) || 0),
          awayGoals: Math.max(0, parseInt(form.awayGoals) || 0),
          cards: form.cards,
        }),
      });
      setActiveModal(null);
      await fetchData(true);
    } finally { setSubmitting(false); }
  };

  const closeMatchday = async () => {
    if (!code || !adminToken) return;
    setClosingMatchday(true);
    try {
      await fetch(`/api/tournaments/${code}/league/close-matchday`, {
        method: "POST", headers: { Authorization: `Bearer ${adminToken}` },
      });
      await fetchData(true);
    } finally { setClosingMatchday(false); }
  };

  const postponeFixture = async (fixtureId: string, force: boolean) => {
    if (!code) return;
    const authToken = force ? adminToken : token;
    if (!authToken) return;
    await fetch(`/api/tournaments/${code}/league/fixtures/${fixtureId}/postpone`, {
      method: "POST", headers: { Authorization: `Bearer ${authToken}` },
    });
    await fetchData(true);
  };

  const cancelPostpone = async (fixtureId: string) => {
    if (!code || !token) return;
    await fetch(`/api/tournaments/${code}/league/fixtures/${fixtureId}/postpone`, {
      method: "DELETE", headers: { Authorization: `Bearer ${token}` },
    });
    await fetchData(true);
  };

  const reactivateFixture = async (fixtureId: string, force: boolean) => {
    if (!code) return;
    const authToken = force ? adminToken : token;
    if (!authToken) return;
    await fetch(`/api/tournaments/${code}/league/fixtures/${fixtureId}/reactivate`, {
      method: "POST", headers: { Authorization: `Bearer ${authToken}` },
    });
    await fetchData(true);
  };

  const cancelReactivate = async (fixtureId: string) => {
    if (!code || !token) return;
    await fetch(`/api/tournaments/${code}/league/fixtures/${fixtureId}/reactivate`, {
      method: "DELETE", headers: { Authorization: `Bearer ${token}` },
    });
    await fetchData(true);
  };

  // ── Check market session status for winter market button ─────────────────────
  useEffect(() => {
    if (!code || !token) return;
    fetch(`/api/tournaments/${code}/market`, { headers: { Authorization: `Bearer ${token}` } })
      .then(r => r.ok ? r.json() : null)
      .then(d => { if (d) setMarketSessionStatus(d.session?.status ?? null); })
      .catch(() => {});
  }, [code, token]);

  const openWinterMarket = async () => {
    if (!code || !adminToken) return;
    setWinterSubmitting(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/market/start`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${adminToken}` },
        body: JSON.stringify({
          marketType: "winter",
          durationHours: winterForm.durationHours,
          budgetInjection: winterForm.budgetInjection * 1_000_000,
          winterMaxTransfers: winterForm.winterMaxTransfers,
          winterClauseProtection: winterForm.winterClauseProtection,
        }),
      });
      if (res.ok) {
        setWinterModal(false);
        setMarketSessionStatus("active");
        router.push("/market");
      }
    } finally { setWinterSubmitting(false); }
  };

  // ── Guard states ─────────────────────────────────────────────────────────────
  if (!code || !token) return (
    <div className="min-h-screen flex items-center justify-center p-8">
      <div className="text-center"><p className="text-[#F3F4F6] font-medium">Sin sesión activa</p></div>
    </div>
  );

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="flex flex-col items-center gap-4">
        <div className="w-8 h-8 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
        <p className="text-[#9CA3AF] text-sm">Cargando calendario…</p>
      </div>
    </div>
  );

  if (!data?.session) return (
    <div className="min-h-screen flex items-center justify-center p-8">
      <div className="bg-[#131722] rounded-2xl border border-white/5 p-10 max-w-sm text-center flex flex-col items-center gap-4">
        <div className="w-14 h-14 rounded-2xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/>
          </svg>
        </div>
        <div>
          <p className="text-[#F3F4F6] font-semibold mb-1">Liga no iniciada</p>
          <p className="text-[#9CA3AF] text-sm">El admin debe iniciar el torneo desde el lobby.</p>
        </div>
      </div>
    </div>
  );

  const { session, myMemberId, currentMatchdayFinished, restMember, myDiscipline } = data;
  const isAdmin = !!adminToken; // use local token, not API response
  const displayMatchday = viewMatchday ?? session.currentMatchday;
  const fixturesForDay = data.allFixtures.filter((f) => f.matchday === displayMatchday);
  const restForDay = displayMatchday === session.currentMatchday ? restMember : null;

  return (
    <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3 }}
      className="px-4 py-5 lg:p-8 max-w-5xl mx-auto">

      {/* Header */}
      <div className="flex flex-col gap-3 mb-5 lg:mb-8">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[#9CA3AF] text-[10px] lg:text-xs uppercase tracking-widest font-medium mb-0.5">Calendario</p>
            <h1 className="text-[#F3F4F6] text-lg lg:text-2xl font-bold tracking-tight">{data.tournamentName}</h1>
            <div className="flex items-center gap-2 mt-1 flex-wrap">
              <span className="text-[#9CA3AF] text-xs lg:text-sm">
                Fecha <span className="text-[#F3F4F6] font-bold">{session.currentMatchday}</span>/<span className="text-[#F3F4F6] font-bold">{session.totalMatchdays}</span>
              </span>
              {data.status === "finished" && (
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#8B5CF6]/15 text-[#8B5CF6]">FINALIZADA</span>
              )}
            </div>
          </div>

          {/* Admin buttons */}
          <div className="flex items-center gap-2 shrink-0">
            {/* Admin: open winter market */}
            {isAdmin && data.status !== "finished" && marketSessionStatus !== "active" && (
              <button onClick={() => setWinterModal(true)}
                className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-semibold border transition-all duration-200 cursor-pointer shrink-0"
                style={{ background: "#3B82F615", borderColor: "#3B82F640", color: "#3B82F6" }}>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2v20M2 12h20M4.93 4.93l14.14 14.14M19.07 4.93L4.93 19.07"/></svg>
                <span className="hidden sm:inline">Mercado de Invierno</span>
                <span className="sm:hidden">Invierno</span>
              </button>
            )}
            {/* Admin: close matchday */}
            {isAdmin && data.status !== "finished" && displayMatchday === session.currentMatchday && (
              <button onClick={closeMatchday} disabled={!currentMatchdayFinished || closingMatchday}
                className="flex items-center gap-1.5 px-3 py-2 rounded-xl text-xs font-semibold border transition-all duration-200 cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed shrink-0"
                style={currentMatchdayFinished
                  ? { background: "#8B5CF615", borderColor: "#8B5CF640", color: "#8B5CF6" }
                  : { background: "#1A1F2E", borderColor: "#ffffff10", color: "#9CA3AF" }}>
                {closingMatchday
                  ? <><svg className="animate-spin w-3 h-3" viewBox="0 0 24 24" fill="none"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/></svg><span className="hidden sm:inline">Cerrando…</span></>
                  : <><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                    <span className="hidden sm:inline">{session.currentMatchday >= session.totalMatchdays ? "Finalizar Liga" : "Cerrar Fecha"}</span>
                    <span className="sm:hidden">{session.currentMatchday >= session.totalMatchdays ? "Finalizar" : "Cerrar"}</span></>
                }
              </button>
            )}
          </div>
        </div>

        {/* My discipline pills */}
        {(myDiscipline.yellows > 0 || myDiscipline.suspended) && (
          <div className="flex items-center gap-2 flex-wrap">
            {myDiscipline.yellows > 0 && (
              <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[#F59E0B]/10 border border-[#F59E0B]/20">
                <div className="w-2.5 h-3.5 bg-[#F59E0B] rounded-sm" />
                <span className="text-[#F59E0B] text-[11px] font-bold">{myDiscipline.yellows}</span>
                <span className="text-[#9CA3AF] text-[10px]">amarillas</span>
              </div>
            )}
            {myDiscipline.suspended && (
              <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[#EF4444]/10 border border-[#EF4444]/20">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                  <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                </svg>
                <span className="text-[#EF4444] text-[11px] font-bold">SANCIONADO</span>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Matchday selector */}
      <div className="flex items-center gap-1.5 lg:gap-2 mb-5 lg:mb-6 overflow-x-auto pb-2 -mx-1 px-1">
        {Array.from({ length: session.totalMatchdays }, (_, i) => i + 1).map((md) => {
          const isCurrentMd = md === session.currentMatchday;
          const isPast = md < session.currentMatchday;
          const isSelected = md === displayMatchday;
          return (
            <button key={md} onClick={() => setViewMatchday(md)}
              className={`shrink-0 w-9 h-9 rounded-xl text-xs font-bold transition-all duration-150 cursor-pointer
                ${isSelected ? "bg-[#8B5CF6] text-white" : isPast ? "bg-[#131722] text-[#22C55E] border border-[#22C55E]/20" : isCurrentMd ? "bg-[#131722] text-[#F3F4F6] border border-white/10" : "bg-[#131722] text-[#9CA3AF] border border-white/5"}`}>
              {md}
            </button>
          );
        })}
      </div>

      {/* Rest notice */}
      {restForDay && (
        <div className="mb-5 rounded-2xl bg-linear-to-r from-[#F59E0B]/8 via-[#131722] to-[#F59E0B]/8 border border-[#F59E0B]/20 p-4">
          <div className="flex items-center gap-4">
            <div className="w-10 h-10 rounded-xl bg-[#F59E0B]/15 border border-[#F59E0B]/25 flex items-center justify-center shrink-0">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#F59E0B" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/>
              </svg>
            </div>
            <div className="flex items-center gap-3 flex-1 min-w-0">
              {restForDay.crestUrl && (
                <img src={restForDay.crestUrl} alt={restForDay.teamName} className="w-7 h-7 object-contain shrink-0" />
              )}
              <div className="min-w-0">
                <p className="text-[#F59E0B] text-[10px] uppercase tracking-widest font-bold mb-0.5">Descansa esta fecha</p>
                <p className="text-[#F3F4F6] text-sm font-bold truncate">
                  {restForDay.displayName}
                  <span className="text-[#9CA3AF] font-normal ml-1.5">({restForDay.teamName})</span>
                </p>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Fixtures list */}
      <div className="flex flex-col gap-3">
        {fixturesForDay.length === 0 && (
          <div className="text-center py-16 text-[#9CA3AF] text-sm">No hay partidos para esta fecha.</div>
        )}
        {fixturesForDay.map((fixture) => (
          <FixtureCard
            key={fixture.id}
            fixture={fixture}
            myMemberId={myMemberId}
            isAdmin={isAdmin}
            isLeagueActive={data.status !== "finished"}
            isCurrentMatchday={displayMatchday <= session.currentMatchday && data.status !== "finished"}
            submitting={submitting}
            onConfirmStart={() => confirmStart(fixture.id)}
            onOpenResult={() => openResultModal(fixture, "result")}
            onOpenConfirm={() => openResultModal(fixture, "confirm")}
            onDisputeResult={() => submitResult(fixture.id, "dispute")}
            onForceValidate={() => openResultModal(fixture, "force")}
            onPostponeForce={() => postponeFixture(fixture.id, true)}
            onPostponeRequest={() => postponeFixture(fixture.id, false)}
            onCancelPostpone={() => cancelPostpone(fixture.id)}
            onReactivateForce={() => reactivateFixture(fixture.id, true)}
            onReactivateRequest={() => reactivateFixture(fixture.id, false)}
            onCancelReactivate={() => cancelReactivate(fixture.id)}
          />
        ))}
      </div>

      {/* Modals */}
      <AnimatePresence>
        {/* Winter market modal */}
        {winterModal && (
          <Modal onClose={() => setWinterModal(false)}>
            <div className="flex flex-col gap-5">
              <div className="flex items-start gap-4">
                <div className="w-11 h-11 rounded-2xl bg-[#3B82F6]/10 border border-[#3B82F6]/20 flex items-center justify-center shrink-0">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#3B82F6" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 2v20M2 12h20M4.93 4.93l14.14 14.14M19.07 4.93L4.93 19.07"/></svg>
                </div>
                <div>
                  <p className="text-[#F3F4F6] font-bold text-base leading-tight">Mercado de Invierno</p>
                  <p className="text-[#9CA3AF] text-xs mt-1">Abre un mercado sin interrumpir la liga. Se inyecta presupuesto a todos los equipos.</p>
                </div>
              </div>

              <div className="flex flex-col gap-4">
                <div>
                  <label className="text-[#9CA3AF] text-[10px] uppercase tracking-wider font-medium mb-1.5 block">Duración</label>
                  <div className="grid grid-cols-4 gap-1.5">
                    {[6, 12, 24, 48].map(h => (
                      <button key={h} onClick={() => setWinterForm(f => ({ ...f, durationHours: h }))}
                        className={`py-2 rounded-xl text-xs font-semibold border transition-colors cursor-pointer
                          ${winterForm.durationHours === h ? "bg-[#3B82F6]/15 border-[#3B82F6]/40 text-[#3B82F6]" : "bg-[#0D0F14] border-white/8 text-[#9CA3AF] hover:text-[#F3F4F6]"}`}>
                        {h}h
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="text-[#9CA3AF] text-[10px] uppercase tracking-wider font-medium mb-1.5 block">Inyección de presupuesto (millones €)</label>
                  <input type="number" min={0} max={500} value={winterForm.budgetInjection}
                    onChange={e => setWinterForm(f => ({ ...f, budgetInjection: Math.max(0, parseInt(e.target.value) || 0) }))}
                    className="w-full bg-[#0D0F14] border border-white/8 rounded-xl px-3 py-2 text-[#F3F4F6] text-sm font-semibold text-center focus:outline-none focus:border-[#3B82F6]/50" />
                </div>

                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="text-[#9CA3AF] text-[10px] uppercase tracking-wider font-medium mb-1.5 block">Max fichajes</label>
                    <div className="flex gap-1">
                      {[1, 2, 3, 4, 5].map(n => (
                        <button key={n} onClick={() => setWinterForm(f => ({ ...f, winterMaxTransfers: n }))}
                          className={`flex-1 py-2 rounded-lg text-xs font-semibold border transition-colors cursor-pointer
                            ${winterForm.winterMaxTransfers === n ? "bg-[#3B82F6]/15 border-[#3B82F6]/40 text-[#3B82F6]" : "bg-[#0D0F14] border-white/8 text-[#9CA3AF]"}`}>
                          {n}
                        </button>
                      ))}
                    </div>
                  </div>
                  <div>
                    <label className="text-[#9CA3AF] text-[10px] uppercase tracking-wider font-medium mb-1.5 block">Max cláusulas/equipo</label>
                    <div className="flex gap-1">
                      {[0, 1, 2, 3].map(n => (
                        <button key={n} onClick={() => setWinterForm(f => ({ ...f, winterClauseProtection: n }))}
                          className={`flex-1 py-2 rounded-lg text-xs font-semibold border transition-colors cursor-pointer
                            ${winterForm.winterClauseProtection === n ? "bg-[#3B82F6]/15 border-[#3B82F6]/40 text-[#3B82F6]" : "bg-[#0D0F14] border-white/8 text-[#9CA3AF]"}`}>
                          {n}
                        </button>
                      ))}
                    </div>
                  </div>
                </div>
              </div>

              <div className="bg-[#0D0F14] rounded-xl px-3 py-2.5 text-[#9CA3AF] text-xs">
                Se inyectarán <span className="text-[#F3F4F6] font-bold">{winterForm.budgetInjection}M€</span> a cada equipo. Los jugadores ícono quedan protegidos de cláusula y ofertas.
              </div>

              <div className="flex gap-3">
                <button onClick={() => setWinterModal(false)}
                  className="flex-1 px-4 py-2.5 rounded-xl border border-white/8 text-[#9CA3AF] text-sm font-medium cursor-pointer hover:bg-[#1A1F2E] transition-colors">
                  Cancelar
                </button>
                <button onClick={openWinterMarket} disabled={winterSubmitting}
                  className="flex-1 px-4 py-2.5 rounded-xl bg-[#3B82F6] text-white text-sm font-semibold cursor-pointer hover:bg-[#2563EB] transition-colors disabled:opacity-50">
                  {winterSubmitting ? "Abriendo…" : "Abrir Mercado"}
                </button>
              </div>
            </div>
          </Modal>
        )}

        {/* Suspension warning */}
        {suspensionWarning && (
          <Modal onClose={() => setSuspensionWarning(null)}>
            <div className="flex flex-col gap-5">
              <div className="flex items-start gap-4">
                <div className="w-11 h-11 rounded-2xl bg-[#EF4444]/10 border border-[#EF4444]/20 flex items-center justify-center shrink-0">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
                    <line x1="12" y1="9" x2="12" y2="13"/>
                    <line x1="12" y1="17" x2="12.01" y2="17"/>
                  </svg>
                </div>
                <div>
                  <p className="text-[#F3F4F6] font-bold text-base leading-tight">Jugadores sancionados</p>
                  <p className="text-[#9CA3AF] text-xs mt-1">Los siguientes jugadores de tu plantilla no pueden jugar este partido por sanción:</p>
                </div>
              </div>

              <div className="flex flex-col gap-2">
                {suspensionWarning.players.map((p, i) => (
                  <div key={i} className="flex items-center gap-3 px-3 py-2.5 rounded-xl bg-[#EF4444]/8 border border-[#EF4444]/20">
                    <div className="w-3 h-4 bg-[#EF4444] rounded-sm shrink-0" />
                    <span className="text-[#F3F4F6] text-sm font-semibold">{p.playerName}</span>
                    <span className="ml-auto text-[#EF4444] text-[10px] font-bold uppercase tracking-wide">Sancionado</span>
                  </div>
                ))}
              </div>

              <p className="text-[#9CA3AF] text-xs bg-[#0D0F14] rounded-xl px-3 py-2.5">
                Puedes confirmar el inicio igualmente, pero debes tener en cuenta que estos jugadores no pueden ser alineados en este partido.
              </p>

              <div className="flex gap-3">
                <button onClick={() => setSuspensionWarning(null)}
                  className="flex-1 px-4 py-2.5 rounded-xl border border-white/8 text-[#9CA3AF] text-sm font-medium cursor-pointer hover:bg-[#1A1F2E] transition-colors">
                  Cancelar
                </button>
                <button
                  onClick={() => { const id = suspensionWarning.fixtureId; setSuspensionWarning(null); doConfirmStart(id); }}
                  className="flex-1 px-4 py-2.5 rounded-xl bg-[#EF4444]/80 hover:bg-[#EF4444] text-white text-sm font-semibold cursor-pointer transition-colors">
                  Entendido, confirmar inicio
                </button>
              </div>
            </div>
          </Modal>
        )}

        {(activeModal?.type === "result" || activeModal?.type === "force" || activeModal?.type === "confirm") && activeModal.fixture && (
          <Modal onClose={() => setActiveModal(null)}>
            <ResultModal
              fixture={activeModal.fixture}
              form={form} setForm={setForm}
              squads={squads}
              myMemberId={data?.myMemberId ?? ""}
              submitting={submitting}
              mode={activeModal.type as "result" | "force" | "confirm"}
              onSubmit={() => {
                const f = activeModal.fixture!;
                if (activeModal.type === "force") forceValidate(f.id);
                else if (activeModal.type === "confirm") submitResult(f.id, "confirm");
                else submitResult(f.id, "submit");
              }}
              onClose={() => setActiveModal(null)}
            />
          </Modal>
        )}
      </AnimatePresence>
    </motion.div>
  );
}

// ── Fixture card ───────────────────────────────────────────────────────────────
function FixtureCard({
  fixture, myMemberId, isAdmin, isLeagueActive, isCurrentMatchday, submitting,
  onConfirmStart, onOpenResult, onOpenConfirm, onDisputeResult, onForceValidate,
  onPostponeForce, onPostponeRequest, onCancelPostpone,
  onReactivateForce, onReactivateRequest, onCancelReactivate,
}: {
  fixture: Fixture; myMemberId: string; isAdmin: boolean; isLeagueActive: boolean; isCurrentMatchday: boolean; submitting: boolean;
  onConfirmStart: () => void; onOpenResult: () => void;
  onOpenConfirm: () => void; onDisputeResult: () => void; onForceValidate: () => void;
  onPostponeForce: () => void; onPostponeRequest: () => void; onCancelPostpone: () => void;
  onReactivateForce: () => void; onReactivateRequest: () => void; onCancelReactivate: () => void;
}) {
  const isHome = fixture.homeMember.id === myMemberId;
  const isAway = fixture.awayMember.id === myMemberId;
  const isParticipant = isHome || isAway;
  const hasPending = !!fixture.resultSubmitterId;
  const pendingIsMe = fixture.resultSubmitterId === myMemberId;
  const canConfirmResult = hasPending && !pendingIsMe && isParticipant;

  const postponeRequestedByMe = fixture.postponeRequestedBy === myMemberId;
  const postponeRequestedByRival = !!fixture.postponeRequestedBy && !postponeRequestedByMe;
  const reactivateRequestedByMe = fixture.reactivateRequestedBy === myMemberId;
  const reactivateRequestedByRival = !!fixture.reactivateRequestedBy && !reactivateRequestedByMe;

  const borderColor = fixture.status === "postponed" ? "#3B82F640"
    : fixture.status === "in_progress" ? "#F59E0B40"
    : fixture.status === "finished" ? "#22C55E20"
    : "#ffffff08";

  return (
    <motion.div layout className="bg-[#131722] rounded-2xl border overflow-hidden transition-colors duration-300"
      style={{ borderColor }}>
      {/* Top stripe */}
      {fixture.status === "in_progress" && <div className="h-0.5 bg-[#F59E0B]" />}
      {fixture.status === "finished" && <div className="h-0.5 bg-[#22C55E]" />}
      {fixture.status === "postponed" && <div className="h-0.5 bg-[#3B82F6]" />}

      <div className="p-3 sm:p-4 lg:p-5">
        {/* Match header */}
        <div className="flex items-center gap-2 sm:gap-3 lg:gap-4">
          {/* Home */}
          <div className={`flex-1 flex items-center justify-end gap-2 lg:gap-3 min-w-0 ${isHome ? "opacity-100" : "opacity-75"}`}>
            <div className="text-right min-w-0">
              <p className="text-[#F3F4F6] font-bold text-xs sm:text-sm leading-tight truncate">{fixture.homeMember.displayName}</p>
              <p className="text-[#9CA3AF] text-[10px] sm:text-xs mt-0.5 truncate">{fixture.homeMember.teamName}</p>
              {fixture.status === "pending" && isCurrentMatchday && (
                <div className="flex justify-end mt-1">
                  <span className={`text-[9px] font-semibold px-1.5 py-0.5 rounded-full ${fixture.homeConfirmed ? "bg-[#22C55E]/15 text-[#22C55E]" : "bg-[#9CA3AF]/10 text-[#9CA3AF]"}`}>
                    {fixture.homeConfirmed ? "✓ Listo" : "Esperando"}
                  </span>
                </div>
              )}
              {fixture.status === "finished" && (fixture.homeYellow > 0 || fixture.homeRed > 0) && (
                <div className="flex justify-end gap-1.5 mt-1">
                  {fixture.homeYellow > 0 && <span className="text-[9px] flex items-center gap-0.5"><span className="w-2 h-2.5 bg-[#F59E0B] rounded-sm inline-block" />{fixture.homeYellow}</span>}
                  {fixture.homeRed > 0 && <span className="text-[9px] flex items-center gap-0.5"><span className="w-2 h-2.5 bg-[#EF4444] rounded-sm inline-block" />{fixture.homeRed}</span>}
                </div>
              )}
            </div>
            {fixture.homeMember.crestUrl ? (
              <img src={fixture.homeMember.crestUrl} alt={fixture.homeMember.teamName} className="w-8 h-8 sm:w-9 sm:h-9 lg:w-10 lg:h-10 object-contain shrink-0" />
            ) : (
              <div className="w-8 h-8 sm:w-9 sm:h-9 lg:w-10 lg:h-10 rounded-full bg-[#8B5CF6]/10 flex items-center justify-center shrink-0">
                <span className="text-[#8B5CF6] text-xs sm:text-sm font-bold">{fixture.homeMember.displayName.charAt(0)}</span>
              </div>
            )}
          </div>

          {/* Score / Status */}
          <div className="flex flex-col items-center gap-1 w-14 sm:w-16 lg:w-20 shrink-0">
            {fixture.status === "finished" ? (
              <div className="flex items-center gap-1.5 sm:gap-2">
                <span className="text-[#F3F4F6] text-xl sm:text-2xl font-black tabular-nums">{fixture.homeGoals}</span>
                <span className="text-[#9CA3AF] text-xs sm:text-sm font-medium">—</span>
                <span className="text-[#F3F4F6] text-xl sm:text-2xl font-black tabular-nums">{fixture.awayGoals}</span>
              </div>
            ) : (
              <div className="flex flex-col items-center gap-0.5">
                <StatusPill status={fixture.status} />
                {fixture.status === "pending" && isCurrentMatchday && (
                  <span className="text-[#9CA3AF] text-[9px]">vs</span>
                )}
              </div>
            )}
          </div>

          {/* Away */}
          <div className={`flex-1 flex items-center gap-2 lg:gap-3 min-w-0 ${isAway ? "opacity-100" : "opacity-75"}`}>
            {fixture.awayMember.crestUrl ? (
              <img src={fixture.awayMember.crestUrl} alt={fixture.awayMember.teamName} className="w-8 h-8 sm:w-9 sm:h-9 lg:w-10 lg:h-10 object-contain shrink-0" />
            ) : (
              <div className="w-8 h-8 sm:w-9 sm:h-9 lg:w-10 lg:h-10 rounded-full bg-[#8B5CF6]/10 flex items-center justify-center shrink-0">
                <span className="text-[#8B5CF6] text-xs sm:text-sm font-bold">{fixture.awayMember.displayName.charAt(0)}</span>
              </div>
            )}
            <div className="min-w-0">
              <p className="text-[#F3F4F6] font-bold text-xs sm:text-sm leading-tight truncate">{fixture.awayMember.displayName}</p>
              <p className="text-[#9CA3AF] text-[10px] sm:text-xs mt-0.5 truncate">{fixture.awayMember.teamName}</p>
              {fixture.status === "pending" && isCurrentMatchday && (
                <div className="mt-1">
                  <span className={`text-[9px] font-semibold px-1.5 py-0.5 rounded-full ${fixture.awayConfirmed ? "bg-[#22C55E]/15 text-[#22C55E]" : "bg-[#9CA3AF]/10 text-[#9CA3AF]"}`}>
                    {fixture.awayConfirmed ? "✓ Listo" : "Esperando"}
                  </span>
                </div>
              )}
              {fixture.status === "finished" && (fixture.awayYellow > 0 || fixture.awayRed > 0) && (
                <div className="flex gap-1.5 mt-1">
                  {fixture.awayYellow > 0 && <span className="text-[9px] flex items-center gap-0.5"><span className="w-2 h-2.5 bg-[#F59E0B] rounded-sm inline-block" />{fixture.awayYellow}</span>}
                  {fixture.awayRed > 0 && <span className="text-[9px] flex items-center gap-0.5"><span className="w-2 h-2.5 bg-[#EF4444] rounded-sm inline-block" />{fixture.awayRed}</span>}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Actions */}
        {isCurrentMatchday && fixture.status !== "finished" && (
          <div className="mt-2.5 sm:mt-3 lg:mt-4 pt-2.5 sm:pt-3 lg:pt-4 border-t border-white/4 flex flex-col sm:flex-row sm:items-center gap-1.5 lg:gap-2 sm:flex-wrap">
            {/* Confirm start */}
            {fixture.status === "pending" && isParticipant && (
              <button onClick={onConfirmStart} disabled={submitting || (isHome && fixture.homeConfirmed) || (isAway && fixture.awayConfirmed)}
                className="flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-semibold bg-[#22C55E]/10 border border-[#22C55E]/25 text-[#22C55E] hover:bg-[#22C55E]/20 transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                {(isHome && fixture.homeConfirmed) || (isAway && fixture.awayConfirmed) ? "Confirmado" : "Confirmar inicio"}
              </button>
            )}

            {/* Submit result — only the home (local) member can send it.
                Previously both teams could click at the same time and the
                second submission would race / get blocked. */}
            {fixture.status === "in_progress" && isHome && !hasPending && !fixture.postponeRequestedBy && (
              <button onClick={onOpenResult}
                className="flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-semibold bg-[#8B5CF6]/10 border border-[#8B5CF6]/25 text-[#8B5CF6] hover:bg-[#8B5CF6]/20 transition-colors cursor-pointer">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                Registrar resultado
              </button>
            )}
            {/* Visitor sees a hint that the home member is responsible. */}
            {fixture.status === "in_progress" && isAway && !hasPending && !fixture.postponeRequestedBy && (
              <span className="text-[#9CA3AF] text-[11px] sm:text-xs font-medium flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg bg-white/5 border border-white/10">
                <svg className="w-3 h-3 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                El local registra el resultado
              </span>
            )}

            {/* Pending result */}
            {hasPending && pendingIsMe && (
              <span className="text-[#F59E0B] text-[11px] sm:text-xs font-medium flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg bg-[#F59E0B]/10 border border-[#F59E0B]/20">
                <svg className="animate-pulse w-3 h-3 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                Esperando confirmación del rival
              </span>
            )}

            {/* Confirm or dispute result */}
            {canConfirmResult && (
              <div className="flex flex-col gap-1.5 sm:gap-2 w-full">
                <div className="flex items-center gap-1.5 sm:gap-2 flex-wrap">
                  <div className="flex items-center gap-1.5 px-2 sm:px-2.5 py-1.5 rounded-lg bg-[#F59E0B]/8 border border-[#F59E0B]/20">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#F59E0B" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                    <span className="text-[#F59E0B] text-[11px] sm:text-xs font-medium">
                      Pendiente: <span className="font-black">{fixture.pendingHomeGoals} – {fixture.pendingAwayGoals}</span>
                    </span>
                  </div>
                  {fixture.pendingCards?.length > 0 && (
                    <div className="flex items-center gap-1 flex-wrap">
                      {fixture.pendingCards.map((c, i) => (
                        <div key={i} className="flex items-center gap-1 px-1.5 sm:px-2 py-1 rounded-lg bg-[#131722] border border-white/6 text-[10px]">
                          <div className={`w-2 h-3 rounded-sm shrink-0 ${c.cardType === "yellow" ? "bg-[#F59E0B]" : "bg-[#EF4444]"}`} />
                          <span className="text-[#9CA3AF] truncate max-w-16 sm:max-w-20">{c.playerName}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
                <div className="flex items-center gap-1.5 sm:gap-2">
                  <button onClick={onOpenConfirm} disabled={submitting}
                    className="px-2.5 sm:px-3 py-1.5 rounded-lg bg-[#22C55E]/10 border border-[#22C55E]/25 text-[#22C55E] text-[11px] sm:text-xs font-semibold hover:bg-[#22C55E]/20 transition-colors cursor-pointer disabled:opacity-50 flex items-center gap-1">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                    Confirmar
                  </button>
                  <button onClick={onDisputeResult} disabled={submitting}
                    className="px-2 sm:px-2.5 py-1.5 rounded-lg bg-[#EF4444]/10 border border-[#EF4444]/25 text-[#EF4444] text-[11px] sm:text-xs font-medium hover:bg-[#EF4444]/20 transition-colors cursor-pointer disabled:opacity-50">
                    Disputar
                  </button>
                </div>
              </div>
            )}

            {/* ── Postpone actions ── */}
            {fixture.status !== "postponed" && isParticipant && !hasPending && (
              <>
                {postponeRequestedByMe && (
                  <div className="flex items-center gap-1.5 sm:gap-2 flex-wrap">
                    <span className="text-[#3B82F6] text-[11px] sm:text-xs font-medium flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg bg-[#3B82F6]/10 border border-[#3B82F6]/20">
                      <svg className="animate-pulse w-3 h-3 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                      Aplazamiento enviado
                    </span>
                    <button onClick={onCancelPostpone}
                      className="px-2 sm:px-2.5 py-1.5 rounded-lg bg-[#EF4444]/10 border border-[#EF4444]/25 text-[#EF4444] text-[11px] sm:text-xs font-medium hover:bg-[#EF4444]/20 transition-colors cursor-pointer">
                      Cancelar
                    </button>
                  </div>
                )}
                {postponeRequestedByRival && (
                  <button onClick={onPostponeRequest}
                    className="flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-semibold bg-[#3B82F6]/10 border border-[#3B82F6]/25 text-[#3B82F6] hover:bg-[#3B82F6]/20 transition-colors cursor-pointer">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                    Aceptar aplazamiento
                  </button>
                )}
                {!fixture.postponeRequestedBy && (
                  <button onClick={onPostponeRequest}
                    className="flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-medium bg-[#131722] border border-white/8 text-[#9CA3AF] hover:text-[#3B82F6] hover:border-[#3B82F6]/30 transition-colors cursor-pointer">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><line x1="8" y1="12" x2="16" y2="12"/></svg>
                    Solicitar aplazar
                  </button>
                )}
              </>
            )}

            {/* ── Reactivate actions ── */}
            {fixture.status === "postponed" && isParticipant && (
              <>
                {reactivateRequestedByMe && (
                  <div className="flex items-center gap-1.5 sm:gap-2 flex-wrap">
                    <span className="text-[#22C55E] text-[11px] sm:text-xs font-medium flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg bg-[#22C55E]/10 border border-[#22C55E]/20">
                      <svg className="animate-pulse w-3 h-3 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                      Reactivación enviada
                    </span>
                    <button onClick={onCancelReactivate}
                      className="px-2 sm:px-2.5 py-1.5 rounded-lg bg-[#EF4444]/10 border border-[#EF4444]/25 text-[#EF4444] text-[11px] sm:text-xs font-medium hover:bg-[#EF4444]/20 transition-colors cursor-pointer">
                      Cancelar
                    </button>
                  </div>
                )}
                {reactivateRequestedByRival && (
                  <button onClick={onReactivateRequest}
                    className="flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-semibold bg-[#22C55E]/10 border border-[#22C55E]/25 text-[#22C55E] hover:bg-[#22C55E]/20 transition-colors cursor-pointer">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                    Aceptar reactivación
                  </button>
                )}
                {!fixture.reactivateRequestedBy && (
                  <button onClick={onReactivateRequest}
                    className="flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-medium bg-[#131722] border border-white/8 text-[#9CA3AF] hover:text-[#22C55E] hover:border-[#22C55E]/30 transition-colors cursor-pointer">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M1 4v6h6"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>
                    Solicitar reactivar
                  </button>
                )}
              </>
            )}

            {/* Admin force buttons */}
            {isAdmin && fixture.status !== "postponed" && fixture.status !== "finished" && (
              <button onClick={onPostponeForce}
                className="sm:ml-auto flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-medium bg-[#131722] border border-white/8 text-[#9CA3AF] hover:text-[#3B82F6] hover:border-[#3B82F6]/30 transition-colors cursor-pointer">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><line x1="8" y1="12" x2="16" y2="12"/></svg>
                Forzar aplazar
              </button>
            )}
            {isAdmin && fixture.status === "postponed" && (
              <button onClick={onReactivateForce}
                className="sm:ml-auto flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-medium bg-[#131722] border border-white/8 text-[#9CA3AF] hover:text-[#22C55E] hover:border-[#22C55E]/30 transition-colors cursor-pointer">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M1 4v6h6"/><path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10"/></svg>
                Forzar reactivar
              </button>
            )}

            {/* Admin force validate */}
            {isAdmin && fixture.status === "in_progress" && (
              <button onClick={onForceValidate}
                className="flex items-center justify-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-lg text-[11px] sm:text-xs font-medium bg-[#131722] border border-white/8 text-[#9CA3AF] hover:text-[#F3F4F6] hover:border-white/20 transition-colors cursor-pointer">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>
                Forzar validar
              </button>
            )}
          </div>
        )}
      </div>
    </motion.div>
  );
}

// ── Result modal with player card search ──────────────────────────────────────
function ResultModal({ fixture, form, setForm, squads, myMemberId, submitting, mode, onSubmit, onClose }: {
  fixture: Fixture; form: ResultForm; setForm: (f: ResultForm) => void;
  squads: { home: SquadData | null; away: SquadData | null } | null;
  myMemberId: string;
  submitting: boolean; mode: "result" | "force" | "confirm"; onSubmit: () => void; onClose: () => void;
}) {
  const [search, setSearch] = useState("");

  const isForce = mode === "force";
  const isConfirm = mode === "confirm";

  // Admins see all players; participants only see their own squad
  const mySquad = squads?.home?.memberId === myMemberId ? squads?.home : squads?.away;
  const allPlayers: Array<SquadPlayer & { memberId: string; side: "home" | "away"; ownerName: string }> = isForce
    ? [
        ...(squads?.home?.players ?? []).filter(p => !p.suspended).map(p => ({ ...p, memberId: squads!.home!.memberId, side: "home" as const, ownerName: squads!.home!.displayName })),
        ...(squads?.away?.players ?? []).filter(p => !p.suspended).map(p => ({ ...p, memberId: squads!.away!.memberId, side: "away" as const, ownerName: squads!.away!.displayName })),
      ]
    : (mySquad?.players ?? []).filter(p => !p.suspended).map(p => ({ ...p, memberId: mySquad!.memberId, side: "home" as const, ownerName: mySquad!.displayName }));

  // Track cards per player in this match to enforce limits
  const cardsByPlayer = (playerId: string) => form.cards.filter(c => c.playerId === playerId);
  const playerHasRed = (playerId: string) => cardsByPlayer(playerId).some(c => c.cardType === "red");
  const playerCardCount = (playerId: string) => cardsByPlayer(playerId).length;

  const filtered = search.length >= 2
    ? allPlayers.filter(p => p.name.toLowerCase().includes(search.toLowerCase()))
    : [];

  const addCard = (player: typeof allPlayers[0], cardType: "yellow" | "red") => {
    if (playerHasRed(player.id)) return;
    const yellows = cardsByPlayer(player.id).filter(c => c.cardType === "yellow").length;
    if (yellows >= 2) return;

    if (cardType === "yellow" && yellows === 1) {
      // Double yellow → auto-convert to red
      const withoutFirstYellow = form.cards.filter(
        c => !(c.playerId === player.id && c.cardType === "yellow")
      );
      setForm({
        ...form,
        cards: [...withoutFirstYellow, { playerId: player.id, playerName: player.name, cardType: "red", memberId: player.memberId }],
      });
    } else {
      setForm({
        ...form,
        cards: [...form.cards, { playerId: player.id, playerName: player.name, cardType, memberId: player.memberId }],
      });
    }
    setSearch("");
  };

  const removeCard = (idx: number) => {
    setForm({ ...form, cards: form.cards.filter((_, i) => i !== idx) });
  };

  return (
    <div className="flex flex-col gap-5 max-h-[85vh] overflow-y-auto">
      <div>
        <p className="text-[#F3F4F6] font-bold text-base mb-0.5">
          {isForce ? "Validar partido (Admin)" : isConfirm ? "Confirmar resultado" : "Registrar resultado"}
        </p>
        <p className="text-[#9CA3AF] text-xs">
          {isForce
            ? `${fixture.homeMember.displayName} vs ${fixture.awayMember.displayName}`
            : isConfirm
              ? "Confirma el marcador y añade las tarjetas de tus jugadores."
              : "El rival deberá confirmar el resultado."}
        </p>
      </div>

      {/* Score — editable in result/force, read-only in confirm */}
      {isConfirm ? (
        <div className="flex items-center justify-center gap-4 py-3 bg-[#0D0F14] rounded-xl">
          <div className="text-right">
            <p className="text-[#9CA3AF] text-[10px]">{fixture.homeMember.displayName}</p>
            <p className="text-[#F3F4F6] text-3xl font-black tabular-nums">{fixture.pendingHomeGoals ?? 0}</p>
          </div>
          <span className="text-[#9CA3AF] text-xl font-bold">–</span>
          <div>
            <p className="text-[#9CA3AF] text-[10px]">{fixture.awayMember.displayName}</p>
            <p className="text-[#F3F4F6] text-3xl font-black tabular-nums">{fixture.pendingAwayGoals ?? 0}</p>
          </div>
        </div>
      ) : (
        <div className="grid grid-cols-[1fr_auto_1fr] gap-3 items-end">
          <NumberInput label={fixture.homeMember.displayName} value={form.homeGoals}
            onChange={(v) => setForm({ ...form, homeGoals: v })} />
          <div className="pb-2 text-[#9CA3AF] font-bold text-sm text-center">–</div>
          <NumberInput label={fixture.awayMember.displayName} value={form.awayGoals}
            onChange={(v) => setForm({ ...form, awayGoals: v })} />
        </div>
      )}

      {/* Card search */}
      <div className="bg-[#0D0F14] rounded-xl p-3 flex flex-col gap-3">
        <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider font-medium">
          {isForce ? "Tarjetas — cualquier jugador (admin)" : "Tarjetas — jugadores de tu plantilla"}
        </p>

        <div className="relative">
          <input
            type="text" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Nombre del jugador…"
            className="w-full bg-[#131722] border border-white/8 rounded-xl px-3 py-2 text-[#F3F4F6] text-sm focus:outline-none focus:border-[#8B5CF6]/50 placeholder-[#9CA3AF]/40"
          />
          {search.length > 0 && search.length < 2 && (
            <p className="text-[#9CA3AF] text-[10px] mt-1 px-1">Escribe al menos 2 caracteres…</p>
          )}

          {/* Dropdown results */}
          {filtered.length > 0 && (
            <div className="absolute top-full left-0 right-0 mt-1 bg-[#1A1F2E] border border-white/8 rounded-xl overflow-hidden z-10 shadow-xl max-h-48 overflow-y-auto">
              {filtered.map(p => {
                const hasRed = playerHasRed(p.id);
                const yellows = cardsByPlayer(p.id).filter(c => c.cardType === "yellow").length;
                const maxedOut = hasRed || yellows >= 2;
                return (
                <div key={`${p.id}-${p.side}`}
                  className={`flex items-center gap-3 px-3 py-2.5 transition-colors border-b border-white/4 last:border-0 ${maxedOut ? "opacity-40" : "hover:bg-[#8B5CF6]/10"}`}>
                  <div className="flex-1 min-w-0">
                    <p className="text-[#F3F4F6] text-xs font-semibold truncate">{p.name}</p>
                    <p className="text-[#9CA3AF] text-[10px]">{p.position} · {p.ownerName}
                      {maxedOut && <span className="text-[#EF4444] ml-1">(expulsado)</span>}
                    </p>
                  </div>
                  <div className="flex gap-1.5 shrink-0">
                    <button onClick={() => addCard(p, "yellow")}
                      disabled={maxedOut}
                      className="w-6 h-8 bg-[#F59E0B] rounded-sm hover:bg-[#D97706] transition-colors cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed"
                      title="Amarilla" />
                    <button onClick={() => addCard(p, "red")}
                      disabled={maxedOut}
                      className="w-6 h-8 bg-[#EF4444] rounded-sm hover:bg-[#DC2626] transition-colors cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed"
                      title="Roja" />
                  </div>
                </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Added cards list */}
        {form.cards.length > 0 && (
          <div className="flex flex-col gap-1.5 mt-1">
            {form.cards.map((c, idx) => (
              <div key={idx} className="flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg bg-[#131722] border border-white/5">
                <div className={`w-3 h-4 rounded-sm shrink-0 ${c.cardType === "yellow" ? "bg-[#F59E0B]" : "bg-[#EF4444]"}`} />
                <span className="text-[#F3F4F6] text-xs font-medium flex-1 truncate">{c.playerName}</span>
                <span className="text-[#9CA3AF] text-[10px]">
                  {c.cardType === "yellow" ? "Amarilla" : "Roja"}
                </span>
                <button onClick={() => removeCard(idx)}
                  className="text-[#9CA3AF] hover:text-[#EF4444] transition-colors cursor-pointer ml-1">
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                  </svg>
                </button>
              </div>
            ))}
          </div>
        )}

        {squads === null && (
          <p className="text-[#9CA3AF] text-[10px] text-center py-1">Cargando plantillas…</p>
        )}
      </div>

      <div className="flex gap-3">
        <button onClick={onClose}
          className="flex-1 px-4 py-2.5 rounded-xl border border-white/8 text-[#9CA3AF] text-sm font-medium cursor-pointer hover:bg-[#1A1F2E] transition-colors">
          Cancelar
        </button>
        <button onClick={onSubmit} disabled={submitting}
          className="flex-1 px-4 py-2.5 rounded-xl bg-[#8B5CF6] text-white text-sm font-semibold cursor-pointer hover:bg-[#7C3AED] transition-colors disabled:opacity-50">
          {submitting ? "Enviando…" : isForce ? "Forzar resultado" : isConfirm ? "Confirmar resultado" : "Enviar resultado"}
        </button>
      </div>
    </div>
  );
}
