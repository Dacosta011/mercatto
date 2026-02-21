"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "motion/react";
import { getLastTournamentCode, getMemberToken, getAdminToken } from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";
import type { RealtimeChannel } from "@supabase/supabase-js";

// ── Types ──────────────────────────────────────────────────────────────────────
interface MemberInfo { id: string; displayName: string; teamName: string }
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
interface SquadPlayer { id: string; name: string; position: string; ovr: number }
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
        type="number" min={0} max={20} value={value}
        onChange={(e) => onChange(e.target.value)}
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
  const channelRef = useRef<RealtimeChannel | null>(null);
  const fetchingRef = useRef(false);

  useEffect(() => {
    const c = getLastTournamentCode();
    const t = c ? getMemberToken(c) : null;
    const at = c ? getAdminToken(c) : null;
    setCode(c); setToken(t); setAdminToken(at);
  }, []);

  const prevMatchdayRef = useRef<number | null>(null);
  const wasFinishedRef  = useRef(false);

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

      // Redirect all users to standings when league finishes
      if (d.status === "finished" && !wasFinishedRef.current) {
        wasFinishedRef.current = true;
        setTimeout(() => router.push("/table"), 1800);
      }

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
              homeGoals: parseInt(form.homeGoals) || 0,
              awayGoals: parseInt(form.awayGoals) || 0,
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
          homeGoals: parseInt(form.homeGoals) || 0,
          awayGoals: parseInt(form.awayGoals) || 0,
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
      className="p-8 max-w-5xl mx-auto">

      {/* Header */}
      <div className="flex items-start justify-between mb-8 gap-4">
        <div>
          <p className="text-[#9CA3AF] text-xs uppercase tracking-widest font-medium mb-1">Calendario</p>
          <h1 className="text-[#F3F4F6] text-2xl font-bold tracking-tight">{data.tournamentName}</h1>
          <div className="flex items-center gap-3 mt-2">
            <span className="text-[#9CA3AF] text-sm">
              Fecha <span className="text-[#F3F4F6] font-bold">{session.currentMatchday}</span> de <span className="text-[#F3F4F6] font-bold">{session.totalMatchdays}</span>
            </span>
            {data.status === "finished" && (
              <>
                <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#8B5CF6]/15 text-[#8B5CF6]">FINALIZADA</span>
                <span className="text-[10px] text-[#9CA3AF] animate-pulse">Redirigiendo a clasificación…</span>
              </>
            )}
          </div>
        </div>

        <div className="flex items-center gap-3">
          {/* My discipline pills */}
          {myDiscipline.yellows > 0 && (
            <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#F59E0B]/10 border border-[#F59E0B]/20">
              <div className="w-3 h-4 bg-[#F59E0B] rounded-sm" />
              <span className="text-[#F59E0B] text-xs font-bold">{myDiscipline.yellows}</span>
              <span className="text-[#9CA3AF] text-[10px]">amarillas</span>
            </div>
          )}
          {myDiscipline.suspended && (
            <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#EF4444]/10 border border-[#EF4444]/20">
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>
              </svg>
              <span className="text-[#EF4444] text-xs font-bold">SANCIONADO</span>
            </div>
          )}

          {/* Admin: close matchday */}
          {isAdmin && data.status !== "finished" && displayMatchday === session.currentMatchday && (
            <button onClick={closeMatchday} disabled={!currentMatchdayFinished || closingMatchday}
              className="flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold border transition-all duration-200 cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
              style={currentMatchdayFinished
                ? { background: "#8B5CF615", borderColor: "#8B5CF640", color: "#8B5CF6" }
                : { background: "#1A1F2E", borderColor: "#ffffff10", color: "#9CA3AF" }}>
              {closingMatchday
                ? <><svg className="animate-spin w-3 h-3" viewBox="0 0 24 24" fill="none"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/></svg>Cerrando…</>
                : <><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                  {session.currentMatchday >= session.totalMatchdays ? "Finalizar Liga" : "Cerrar Fecha"}</>
              }
            </button>
          )}
        </div>
      </div>

      {/* Matchday selector */}
      <div className="flex items-center gap-2 mb-6 overflow-x-auto pb-2">
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
        <div className="mb-5 flex items-center gap-3 px-4 py-3 rounded-xl bg-[#131722] border border-white/5">
          <div className="w-7 h-7 rounded-lg bg-[#9CA3AF]/10 flex items-center justify-center shrink-0">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/>
            </svg>
          </div>
          <span className="text-[#9CA3AF] text-sm">Descansa esta fecha: <span className="text-[#F3F4F6] font-semibold">{restForDay.displayName}</span> <span className="text-[#9CA3AF]/60">({restForDay.teamName})</span></span>
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
            isCurrentMatchday={displayMatchday === session.currentMatchday && data.status !== "finished"}
            submitting={submitting}
            onConfirmStart={() => confirmStart(fixture.id)}
            onOpenResult={() => openResultModal(fixture, "result")}
            onOpenConfirm={() => openResultModal(fixture, "confirm")}
            onDisputeResult={() => submitResult(fixture.id, "dispute")}
            onForceValidate={() => openResultModal(fixture, "force")}
          />
        ))}
      </div>

      {/* Modals */}
      <AnimatePresence>
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
  fixture, myMemberId, isAdmin, isCurrentMatchday, submitting,
  onConfirmStart, onOpenResult, onOpenConfirm, onDisputeResult, onForceValidate,
}: {
  fixture: Fixture; myMemberId: string; isAdmin: boolean; isCurrentMatchday: boolean; submitting: boolean;
  onConfirmStart: () => void; onOpenResult: () => void;
  onOpenConfirm: () => void; onDisputeResult: () => void; onForceValidate: () => void;
}) {
  const isHome = fixture.homeMember.id === myMemberId;
  const isAway = fixture.awayMember.id === myMemberId;
  const isParticipant = isHome || isAway;
  const hasPending = !!fixture.resultSubmitterId;
  const pendingIsMe = fixture.resultSubmitterId === myMemberId;
  const canConfirmResult = hasPending && !pendingIsMe && isParticipant;

  const borderColor = fixture.status === "in_progress" ? "#F59E0B40" : fixture.status === "finished" ? "#22C55E20" : "#ffffff08";

  return (
    <motion.div layout className="bg-[#131722] rounded-2xl border overflow-hidden transition-colors duration-300"
      style={{ borderColor }}>
      {/* Top stripe for in_progress */}
      {fixture.status === "in_progress" && <div className="h-0.5 bg-[#F59E0B]" />}
      {fixture.status === "finished" && <div className="h-0.5 bg-[#22C55E]" />}

      <div className="p-5">
        {/* Match header */}
        <div className="flex items-center gap-4">
          {/* Home */}
          <div className={`flex-1 text-right ${isHome ? "opacity-100" : "opacity-75"}`}>
            <p className="text-[#F3F4F6] font-bold text-sm leading-tight">{fixture.homeMember.displayName}</p>
            <p className="text-[#9CA3AF] text-xs mt-0.5">{fixture.homeMember.teamName}</p>
            {fixture.status === "pending" && isCurrentMatchday && (
              <div className="flex justify-end mt-1">
                <span className={`text-[9px] font-semibold px-1.5 py-0.5 rounded-full ${fixture.homeConfirmed ? "bg-[#22C55E]/15 text-[#22C55E]" : "bg-[#9CA3AF]/10 text-[#9CA3AF]"}`}>
                  {fixture.homeConfirmed ? "✓ Listo" : "Esperando"}
                </span>
              </div>
            )}
            {/* Card indicators */}
            {fixture.status === "finished" && (fixture.homeYellow > 0 || fixture.homeRed > 0) && (
              <div className="flex justify-end gap-1.5 mt-1">
                {fixture.homeYellow > 0 && <span className="text-[9px] flex items-center gap-0.5"><span className="w-2 h-2.5 bg-[#F59E0B] rounded-sm inline-block" />{fixture.homeYellow}</span>}
                {fixture.homeRed > 0 && <span className="text-[9px] flex items-center gap-0.5"><span className="w-2 h-2.5 bg-[#EF4444] rounded-sm inline-block" />{fixture.homeRed}</span>}
              </div>
            )}
          </div>

          {/* Score / Status */}
          <div className="flex flex-col items-center gap-1 w-20 shrink-0">
            {fixture.status === "finished" ? (
              <div className="flex items-center gap-2">
                <span className="text-[#F3F4F6] text-2xl font-black tabular-nums">{fixture.homeGoals}</span>
                <span className="text-[#9CA3AF] text-sm font-medium">—</span>
                <span className="text-[#F3F4F6] text-2xl font-black tabular-nums">{fixture.awayGoals}</span>
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
          <div className={`flex-1 ${isAway ? "opacity-100" : "opacity-75"}`}>
            <p className="text-[#F3F4F6] font-bold text-sm leading-tight">{fixture.awayMember.displayName}</p>
            <p className="text-[#9CA3AF] text-xs mt-0.5">{fixture.awayMember.teamName}</p>
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

        {/* Actions */}
        {isCurrentMatchday && fixture.status !== "finished" && (
          <div className="mt-4 pt-4 border-t border-white/4 flex items-center gap-2 flex-wrap">
            {/* Confirm start */}
            {fixture.status === "pending" && isParticipant && (
              <button onClick={onConfirmStart} disabled={submitting || (isHome && fixture.homeConfirmed) || (isAway && fixture.awayConfirmed)}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-[#22C55E]/10 border border-[#22C55E]/25 text-[#22C55E] hover:bg-[#22C55E]/20 transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                {(isHome && fixture.homeConfirmed) || (isAway && fixture.awayConfirmed) ? "Confirmado" : "Confirmar inicio"}
              </button>
            )}

            {/* Submit result */}
            {fixture.status === "in_progress" && isParticipant && !hasPending && (
              <button onClick={onOpenResult}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold bg-[#8B5CF6]/10 border border-[#8B5CF6]/25 text-[#8B5CF6] hover:bg-[#8B5CF6]/20 transition-colors cursor-pointer">
                <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
                Registrar resultado
              </button>
            )}

            {/* Pending result — waiting confirmation */}
            {hasPending && pendingIsMe && (
              <span className="text-[#F59E0B] text-xs font-medium flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[#F59E0B]/10 border border-[#F59E0B]/20">
                <svg className="animate-pulse w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                Esperando confirmación del rival
              </span>
            )}

            {/* Confirm or dispute result */}
            {canConfirmResult && (
              <div className="flex flex-col gap-2 w-full">
                {/* Score + cards submitted by first player */}
                <div className="flex items-center gap-2 flex-wrap">
                  <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg bg-[#F59E0B]/8 border border-[#F59E0B]/20">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#F59E0B" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
                    <span className="text-[#F59E0B] text-xs font-medium">
                      Resultado pendiente: <span className="font-black">{fixture.pendingHomeGoals} – {fixture.pendingAwayGoals}</span>
                    </span>
                  </div>

                  {/* Cards already registered by first player */}
                  {fixture.pendingCards?.length > 0 && (
                    <div className="flex items-center gap-1 flex-wrap">
                      {fixture.pendingCards.map((c, i) => (
                        <div key={i} className="flex items-center gap-1 px-2 py-1 rounded-lg bg-[#131722] border border-white/6 text-[10px]">
                          <div className={`w-2 h-3 rounded-sm shrink-0 ${c.cardType === "yellow" ? "bg-[#F59E0B]" : "bg-[#EF4444]"}`} />
                          <span className="text-[#9CA3AF] truncate max-w-20">{c.playerName}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>

                {/* Action buttons */}
                <div className="flex items-center gap-2">
                  <button onClick={onOpenConfirm} disabled={submitting}
                    className="px-3 py-1.5 rounded-lg bg-[#22C55E]/10 border border-[#22C55E]/25 text-[#22C55E] text-xs font-semibold hover:bg-[#22C55E]/20 transition-colors cursor-pointer disabled:opacity-50 flex items-center gap-1">
                    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                    Confirmar + mis tarjetas
                  </button>
                  <button onClick={onDisputeResult} disabled={submitting}
                    className="px-2.5 py-1.5 rounded-lg bg-[#EF4444]/10 border border-[#EF4444]/25 text-[#EF4444] text-xs font-medium hover:bg-[#EF4444]/20 transition-colors cursor-pointer disabled:opacity-50">
                    ✗ Disputar
                  </button>
                </div>
              </div>
            )}

            {/* Admin force validate */}
            {isAdmin && fixture.status === "in_progress" && (
              <button onClick={onForceValidate}
                className="ml-auto flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium bg-[#131722] border border-white/8 text-[#9CA3AF] hover:text-[#F3F4F6] hover:border-white/20 transition-colors cursor-pointer">
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
        ...(squads?.home?.players ?? []).map(p => ({ ...p, memberId: squads!.home!.memberId, side: "home" as const, ownerName: squads!.home!.displayName })),
        ...(squads?.away?.players ?? []).map(p => ({ ...p, memberId: squads!.away!.memberId, side: "away" as const, ownerName: squads!.away!.displayName })),
      ]
    : (mySquad?.players ?? []).map(p => ({ ...p, memberId: mySquad!.memberId, side: "home" as const, ownerName: mySquad!.displayName }));

  const filtered = search.length >= 2
    ? allPlayers.filter(p => p.name.toLowerCase().includes(search.toLowerCase()))
    : [];

  const addCard = (player: typeof allPlayers[0], cardType: "yellow" | "red") => {
    setForm({
      ...form,
      cards: [...form.cards, { playerId: player.id, playerName: player.name, cardType, memberId: player.memberId }],
    });
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
              {filtered.map(p => (
                <div key={`${p.id}-${p.side}`}
                  className="flex items-center gap-3 px-3 py-2.5 hover:bg-[#8B5CF6]/10 transition-colors border-b border-white/4 last:border-0">
                  <div className="flex-1 min-w-0">
                    <p className="text-[#F3F4F6] text-xs font-semibold truncate">{p.name}</p>
                    <p className="text-[#9CA3AF] text-[10px]">{p.position} · {p.ownerName}</p>
                  </div>
                  <div className="flex gap-1.5 shrink-0">
                    <button onClick={() => addCard(p, "yellow")}
                      className="w-6 h-8 bg-[#F59E0B] rounded-sm hover:bg-[#D97706] transition-colors cursor-pointer"
                      title="Amarilla" />
                    <button onClick={() => addCard(p, "red")}
                      className="w-6 h-8 bg-[#EF4444] rounded-sm hover:bg-[#DC2626] transition-colors cursor-pointer"
                      title="Roja" />
                  </div>
                </div>
              ))}
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
