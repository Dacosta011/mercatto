"use client";

import { useEffect, useState, useCallback, useRef } from "react";
import { useParams, useRouter } from "next/navigation";
import { motion, AnimatePresence } from "motion/react";
import Link from "next/link";
import Badge from "../../../Components/Badge";
import Button from "../../../Components/Button";
import { getAdminToken, getMemberToken, saveTournamentStatus, clearTournamentTokens, type TournamentStatus } from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";

interface Member {
  id: string;
  displayName: string;
  budget: number | null;
  team: { name: string; crestUrl: string | null } | null;
}

  interface Tournament {
    id: string;
    name: string;
    code: string;
    status: "lobby" | "draft" | "market" | "league" | "complete";
    createdAt: string;
    members: Member[];
  }

function formatBudget(value: number | null | undefined) {
  if (!value || isNaN(value)) return "—";
  return `€${(value / 1_000_000).toFixed(0)}M`;
}

function StatusBadge({ status }: { status: Tournament["status"] }) {
  const map: Record<
    Tournament["status"],
    { label: string; status: "active" | "pending" | "complete" | "draft" }
  > = {
    lobby: { label: "Lobby abierto", status: "active" },
    draft: { label: "Draft", status: "pending" },
    market: { label: "Mercado", status: "assigned" as any },
    league: { label: "Liga activa", status: "assigned" as any },
    complete: { label: "Finalizado", status: "complete" },
  };
  const cfg = map[status];
  return <Badge status={cfg.status} label={cfg.label} />;
}

// ── AdminAction card ──────────────────────────────────────────────────────────
interface AdminActionProps {
  icon: React.ReactNode;
  label: string;
  description: string;
  color: string;
  glow?: boolean;
  available: boolean;
  unavailableReason?: string;
  loading?: boolean;
  danger?: boolean;
  href?: string;
  confirmKey?: string;
  confirmAction?: string | null;
  setConfirmAction?: (key: string | null) => void;
  onClick?: () => void;
}

function AdminAction({
  icon, label, description, color, glow, available, unavailableReason,
  loading, danger, href, confirmKey, confirmAction, setConfirmAction, onClick,
}: AdminActionProps) {
  const isConfirming = !!confirmKey && confirmAction === confirmKey;
  const needsConfirm = danger && !!confirmKey;

  const handleClick = () => {
    if (!available || loading) return;
    if (needsConfirm && !isConfirming) {
      setConfirmAction?.(confirmKey!);
      setTimeout(() => setConfirmAction?.(null), 4000);
      return;
    }
    onClick?.();
  };

  const inner = (
    <div
      className={`relative flex flex-col gap-3 p-4 rounded-2xl border transition-all duration-200 h-full
        ${available
          ? isConfirming
            ? "bg-[#EF4444]/8 border-[#EF4444]/40 cursor-pointer"
            : "bg-[#131722] border-white/6 hover:bg-[#1A1F2E] hover:border-white/10 cursor-pointer"
          : "bg-[#0D0F14] border-white/4 opacity-50 cursor-not-allowed"
        }`}
      style={glow && available ? { boxShadow: `0 0 20px ${color}18` } : undefined}
    >
      {/* Icon */}
      <div className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0 transition-all duration-200"
        style={{ background: `${color}18`, color: available ? color : "#6B7280", border: `1px solid ${color}25` }}>
        {loading ? (
          <span className="w-4 h-4 border border-current border-t-transparent rounded-full animate-spin" />
        ) : icon}
      </div>

      {/* Text */}
      <div className="flex-1 min-w-0">
        <p className="text-[#F3F4F6] text-sm font-semibold leading-tight mb-0.5">
          {isConfirming ? "¿Confirmar?" : label}
        </p>
        <p className="text-[10px] leading-relaxed" style={{ color: available ? "#9CA3AF" : "#6B7280" }}>
          {isConfirming ? "Esta acción no se puede deshacer fácilmente" : unavailableReason ?? description}
        </p>
      </div>

      {/* Status dot */}
      {!available && (
        <div className="absolute top-3 right-3 w-2 h-2 rounded-full bg-[#374151]" />
      )}
      {available && !isConfirming && (
        <div className="absolute top-3 right-3 w-2 h-2 rounded-full animate-pulse"
          style={{ background: color, boxShadow: `0 0 6px ${color}` }} />
      )}
      {isConfirming && (
        <div className="absolute top-3 right-3 w-2 h-2 rounded-full bg-[#EF4444] animate-ping" />
      )}
    </div>
  );

  if (href && available) {
    return <Link href={href} className="h-full">{inner}</Link>;
  }

  return <div onClick={handleClick}>{inner}</div>;
}

export default function LobbyPage() {
  const { code } = useParams<{ code: string }>();
  const router = useRouter();
  const [tournament, setTournament] = useState<Tournament | null>(null);
  const [adminToken, setAdminToken] = useState<string | null>(null);
  // memberId confirmando eliminación (doble click)
  const [confirmDelete, setConfirmDelete] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);
  const [endingTournament, setEndingTournament] = useState(false);

  const [startingMarket, setStartingMarket] = useState(false);
  const [startingFreshMarket, setStartingFreshMarket] = useState(false);
  const [startingLeague, setStartingLeague] = useState(false);
  const [resettingMarket, setResettingMarket] = useState(false);
  const [resettingLeague, setResettingLeague] = useState(false);
  const [confirmAction, setConfirmAction] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [refreshing, setRefreshing] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);
  const [myMemberId, setMyMemberId] = useState<string | null>(null);

  const fetchTournament = useCallback(
    async (silent = false) => {
      if (!silent) setLoading(true);
      else setRefreshing(true);

      try {
        const res = await fetch(`/api/tournaments/${code}`);
        const data = await res.json();

        if (!res.ok) {
          setError(data.error ?? "No se pudo cargar el torneo.");
          return;
        }

        setTournament(data);
        setError("");

        if (data.status) {
          saveTournamentStatus(code, data.status as TournamentStatus);
        }
      } catch {
        setError("Error de conexión. Comprueba tu internet.");
      } finally {
        setLoading(false);
        setRefreshing(false);
      }
    },
    [code]
  );

  // Detectar si el usuario es admin o miembro de este torneo
  useEffect(() => {
    const token = getAdminToken(code);
    setIsAdmin(!!token);
    setAdminToken(token);
    const memberToken = getMemberToken(code);
    if (memberToken) setMyMemberId(memberToken);
  }, [code]);

  // Eliminar participante
  const handleDeleteMember = async (memberId: string) => {
    if (confirmDelete !== memberId) {
      setConfirmDelete(memberId);
      setTimeout(() => setConfirmDelete(null), 3000);
      return;
    }
    setConfirmDelete(null);
    setDeletingId(memberId);
    try {
      await fetch(`/api/tournaments/${code}/members/${memberId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${adminToken}` },
      });
      setTournament((t) =>
        t ? { ...t, members: t.members.filter((m) => m.id !== memberId) } : t
      );
    } finally {
      setDeletingId(null);
    }
  };

  // Iniciar liga/torneo
  const handleStartLeague = async () => {
    if (!adminToken) return;
    setStartingLeague(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/league/start`, {
        method: "POST",
        headers: { Authorization: `Bearer ${adminToken}` },
      });
      if (res.ok) {
        saveTournamentStatus(code, "league");
        router.push("/calendar");
      }
    } finally {
      setStartingLeague(false);
    }
  };

  // Iniciar mercado (continúa donde terminó el anterior)
  const handleStartMarket = async () => {
    if (!adminToken) return;
    setStartingMarket(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/market/start`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${adminToken}` },
        body: JSON.stringify({}),
      });
      if (res.ok) {
        saveTournamentStatus(code, "market");
        router.push("/market");
      }
    } finally {
      setStartingMarket(false);
    }
  };

  // Iniciar mercado desde cero (recalcula presupuestos)
  const handleStartFreshMarket = async () => {
    if (!adminToken) return;
    setStartingFreshMarket(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/market/start`, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${adminToken}` },
        body: JSON.stringify({ resetBudgets: true }),
      });
      if (res.ok) {
        saveTournamentStatus(code, "market");
        router.push("/market");
      }
    } finally {
      setStartingFreshMarket(false);
    }
  };

  // Reiniciar mercado
  const handleResetMarket = async () => {
    if (!adminToken) return;
    setResettingMarket(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/market/reset`, {
        method: "POST",
        headers: { Authorization: `Bearer ${adminToken}` },
      });
      if (res.ok) {
        saveTournamentStatus(code, "lobby");
        setTournament((t) => (t ? { ...t, status: "lobby" } : t));
      }
    } finally { setResettingMarket(false); setConfirmAction(null); }
  };

  // Reiniciar liga
  const handleResetLeague = async () => {
    if (!adminToken) return;
    setResettingLeague(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/league/reset`, {
        method: "POST",
        headers: { Authorization: `Bearer ${adminToken}` },
      });
      if (res.ok) {
        saveTournamentStatus(code, "lobby");
        setTournament((t) => (t ? { ...t, status: "lobby" } : t));
      }
    } finally { setResettingLeague(false); setConfirmAction(null); }
  };

  // Finalizar torneo
  const handleEndTournament = async () => {
    setEndingTournament(true);
    try {
      const res = await fetch(`/api/tournaments/${code}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${adminToken}` },
        body: JSON.stringify({ status: "complete" }),
      });
      if (res.ok) {
        saveTournamentStatus(code, "complete");
        setTournament((t) => (t ? { ...t, status: "complete" } : t));
      }
    } finally {
      setEndingTournament(false);
      setConfirmAction(null);
    }
  };

  // Carga inicial
  useEffect(() => {
    fetchTournament();
  }, [fetchTournament]);

  // ── Supabase Realtime: re-fetch lobby on any relevant DB change ──────────
  useEffect(() => {
    if (!tournament?.id) return;

    const supabase = getBrowserClient();
    const onDbChange = () => fetchTournament(true);

    const channel = supabase
      .channel(`lobby:${tournament.id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "members",     filter: `tournament_id=eq.${tournament.id}` }, onDbChange)
      .on("postgres_changes", { event: "*", schema: "public", table: "assignments" }, onDbChange)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "tournaments", filter: `id=eq.${tournament.id}` }, onDbChange)
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tournament?.id]);

  // ── Loading ────────────────────────────────────────────────────────────────
  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <div className="w-10 h-10 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          <p className="text-[#9CA3AF] text-sm">Cargando torneo…</p>
        </div>
      </div>
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────
  if (error || !tournament) {
    return (
      <div className="min-h-screen flex items-center justify-center p-6">
        <div className="text-center max-w-sm">
          <div className="w-14 h-14 rounded-2xl bg-[#EF4444]/10 border border-[#EF4444]/20 flex items-center justify-center mx-auto mb-4">
            <svg
              width="22"
              height="22"
              viewBox="0 0 24 24"
              fill="none"
              stroke="#EF4444"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
          </div>
          <p className="text-[#F3F4F6] font-semibold mb-1">
            {error || "Torneo no encontrado"}
          </p>
          <p className="text-[#9CA3AF] text-sm mb-6">
            Código: <span className="font-mono text-[#F3F4F6]">{code}</span>
          </p>
          <Link href="/join">
            <Button variant="primary" size="md">
              Intentar con otro código
            </Button>
          </Link>
        </div>
      </div>
    );
  }

  const assigned = tournament.members.filter((m) => m.team !== null).length;
  const total = tournament.members.length;
  const progress = total > 0 ? (assigned / total) * 100 : 0;

  // ── Main ───────────────────────────────────────────────────────────────────
  return (
    <div className="p-8 max-w-5xl mx-auto">
      {/* Header */}
      <div className="flex items-start justify-between mb-8 gap-4">
        <div>
          <div className="flex items-center gap-3 mb-1.5 flex-wrap">
            <h1 className="text-[#F3F4F6] text-2xl font-bold tracking-tight">
              {tournament.name}
            </h1>
            <StatusBadge status={tournament.status} />
            {isAdmin && (
              <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium bg-[#8B5CF6]/10 text-[#8B5CF6] border border-[#8B5CF6]/20">
                <svg
                  width="10"
                  height="10"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
                </svg>
                Admin
              </span>
            )}
          </div>
          <div className="flex items-center gap-3">
            <p className="text-[#9CA3AF] text-sm">
              {assigned} de {total} equipos asignados
            </p>
            <span className="text-[#9CA3AF]/30">·</span>
            <p className="text-[#9CA3AF] text-sm font-mono tracking-wider">
              {tournament.code}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2 shrink-0">
          <button
            onClick={() => fetchTournament(true)}
            disabled={refreshing}
            className="flex items-center gap-2 px-3 py-2 rounded-xl bg-[#131722] border border-white/6 hover:bg-[#1A1F2E] text-[#9CA3AF] hover:text-[#F3F4F6] text-xs font-medium transition-all duration-200 disabled:opacity-50 cursor-pointer"
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={refreshing ? "animate-spin" : ""}>
              <polyline points="23 4 23 10 17 10" /><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10" />
            </svg>
            Actualizar
          </button>
          <button
            onClick={() => { clearTournamentTokens(code); router.replace("/"); }}
            className="flex items-center gap-2 px-3 py-2 rounded-xl bg-[#131722] border border-[#EF4444]/20 hover:bg-[#EF4444]/10 text-[#EF4444]/70 hover:text-[#EF4444] text-xs font-medium transition-all duration-200 cursor-pointer"
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/>
            </svg>
            Salir
          </button>
        </div>
      </div>

      {/* Progress card */}
      <div className="mb-6 bg-[#131722] rounded-2xl p-5 border border-white/[0.04]">
        <div className="flex items-center justify-between mb-3">
          <span className="text-[#9CA3AF] text-xs uppercase tracking-wider font-medium">
            Progreso del draft
          </span>
          <span className="text-[#F3F4F6] text-sm font-semibold tabular-nums">
            {Math.round(progress)}%
          </span>
        </div>
        <div className="h-1.5 bg-[#0D0F14] rounded-full overflow-hidden">
          <motion.div
            className="h-full bg-linear-to-r from-[#8B5CF6] to-[#6D28D9] rounded-full"
            initial={{ width: 0 }}
            animate={{ width: `${progress}%` }}
            transition={{ duration: 0.8, ease: "easeOut" }}
          />
        </div>
        <div className="flex gap-6 mt-3">
          <span className="text-[#9CA3AF] text-xs">
            <span className="text-[#22C55E] font-semibold">{assigned}</span>{" "}
            asignados
          </span>
          <span className="text-[#9CA3AF] text-xs">
            <span className="text-yellow-400 font-semibold">
              {total - assigned}
            </span>{" "}
            pendientes
          </span>
          <span className="text-[#9CA3AF] text-xs">
            <span className="text-[#F3F4F6] font-semibold">{total}</span>{" "}
            participantes
          </span>
        </div>
      </div>

      {/* ── Admin Control Panel ──────────────────────────────────────────── */}
      {isAdmin && (
        <div className="mb-6">
          {/* Panel header */}
          <div className="flex items-center gap-3 mb-4">
            <div className="w-7 h-7 rounded-lg flex items-center justify-center shrink-0"
              style={{ background: "linear-gradient(135deg,#7C3AED,#8B5CF6)", boxShadow: "0 0 12px #8B5CF640" }}>
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
              </svg>
            </div>
            <div>
              <p className="text-[#F3F4F6] text-sm font-bold">Panel de Control</p>
              <p className="text-[#9CA3AF] text-[10px]">Acciones exclusivas de administrador</p>
            </div>
          </div>

          <div className="grid grid-cols-2 lg:grid-cols-3 gap-3">
            {/* Iniciar Mercado */}
            <AdminAction
              icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/></svg>}
              label="Iniciar Mercado"
              description="Abre las rondas de fichajes"
              color="#22C55E"
              available={tournament.status === "lobby" && tournament.members.every(m => m.team !== null)}
              unavailableReason={
                tournament.status !== "lobby" ? "Solo en fase lobby" :
                !tournament.members.every(m => m.team !== null) ? "Todos deben tener equipo" : undefined
              }
              loading={startingMarket}
              onClick={handleStartMarket}
            />

            {/* Mercado desde cero (recalcula presupuestos) */}
            <AdminAction
              icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>}
              label="Mercado desde Cero"
              description="Recalcula presupuestos e inicia un mercado limpio"
              color="#F59E0B"
              available={tournament.status === "lobby" && tournament.members.every(m => m.team !== null)}
              unavailableReason={
                tournament.status !== "lobby" ? "Solo en fase lobby" :
                !tournament.members.every(m => m.team !== null) ? "Todos deben tener equipo" : undefined
              }
              loading={startingFreshMarket}
              danger
              confirmKey="fresh-market"
              confirmAction={confirmAction}
              setConfirmAction={setConfirmAction}
              onClick={handleStartFreshMarket}
            />

            {/* Reiniciar Mercado */}
            <AdminAction
              icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>}
              label="Reiniciar Mercado"
              description="Borra el mercado actual y vuelve al lobby"
              color="#F59E0B"
              available={tournament.status === "market"}
              unavailableReason={tournament.status !== "market" ? "Solo durante el mercado" : undefined}
              loading={resettingMarket}
              danger
              confirmKey="reset-market"
              confirmAction={confirmAction}
              setConfirmAction={setConfirmAction}
              onClick={handleResetMarket}
            />

            {/* Iniciar Torneo */}
            <AdminAction
              icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="5 3 19 12 5 21 5 3"/></svg>}
              label="Iniciar Torneo"
              description="Genera el calendario de liga"
              color="#8B5CF6"
              glow
              available={(tournament.status === "lobby" || tournament.status === "market") && tournament.members.every(m => m.team !== null)}
              unavailableReason={
                tournament.status === "league" ? "Liga ya iniciada" :
                !tournament.members.every(m => m.team !== null) ? "Todos deben tener equipo" : undefined
              }
              loading={startingLeague}
              onClick={handleStartLeague}
            />

            {/* Reiniciar Liga */}
            <AdminAction
              icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.65"/></svg>}
              label="Reiniciar Liga"
              description="Borra la liga y vuelve al lobby"
              color="#F59E0B"
              available={tournament.status === "league"}
              unavailableReason={tournament.status !== "league" ? "Solo durante la liga" : undefined}
              loading={resettingLeague}
              danger
              confirmKey="reset-league"
              confirmAction={confirmAction}
              setConfirmAction={setConfirmAction}
              onClick={handleResetLeague}
            />

            {/* Finalizar Torneo */}
            <AdminAction
              icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/></svg>}
              label="Finalizar Torneo"
              description="Cierra el torneo definitivamente"
              color="#EF4444"
              available={true}
              loading={endingTournament}
              danger
              confirmKey="end-tournament"
              confirmAction={confirmAction}
              setConfirmAction={setConfirmAction}
              onClick={handleEndTournament}
            />
          </div>
        </div>
      )}

      {/* Participants table */}
      <div className="bg-[#131722] rounded-2xl border border-white/[0.04] overflow-hidden">
        {/* Toolbar */}
        <div className="px-6 py-4 border-b border-white/[0.04] flex items-center justify-between gap-4">
          <h2 className="text-[#F3F4F6] text-sm font-semibold">
            Participantes
          </h2>
          <div className="flex items-center gap-2">
            {refreshing && (
              <span className="text-[#9CA3AF] text-xs flex items-center gap-1.5">
                <span className="w-3 h-3 border border-[#9CA3AF]/30 border-t-[#9CA3AF] rounded-full animate-spin" />
                Actualizando…
              </span>
            )}
            <button
              onClick={() => {
                navigator.clipboard.writeText(
                  `${window.location.origin}/join?code=${tournament.code}`
                );
              }}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[#0D0F14] border border-white/[0.06] hover:border-[#8B5CF6]/30 text-[#9CA3AF] hover:text-[#F3F4F6] text-xs font-medium transition-all duration-200 cursor-pointer"
            >
              <svg
                width="12"
                height="12"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" />
                <polyline points="16 6 12 2 8 6" />
                <line x1="12" y1="2" x2="12" y2="15" />
              </svg>
              Invitar
            </button>
          </div>
        </div>

        {/* Column headers */}
        <div className={`grid px-6 py-3 border-b border-white/[0.04] ${isAdmin ? "grid-cols-[2fr_2fr_1.5fr_1fr_auto]" : "grid-cols-[2fr_2fr_1.5fr_1fr]"}`}>
          {["Nombre", "Equipo", "Presupuesto", "Estado", ...(isAdmin ? [""] : [])].map((col, i) => (
            <span key={i} className="text-[#9CA3AF] text-[11px] font-semibold uppercase tracking-wider">
              {col}
            </span>
          ))}
        </div>

        {/* Rows */}
        <AnimatePresence initial={false}>
          {tournament.members.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-16 text-center">
              <div className="w-12 h-12 rounded-2xl bg-[#0D0F14] border border-white/[0.04] flex items-center justify-center mb-3">
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="#9CA3AF"
                  strokeWidth="1.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                  <circle cx="9" cy="7" r="4" />
                  <line x1="19" y1="8" x2="19" y2="14" />
                  <line x1="22" y1="11" x2="16" y2="11" />
                </svg>
              </div>
              <p className="text-[#F3F4F6] text-sm font-medium">
                Aún no hay participantes
              </p>
              <p className="text-[#9CA3AF] text-xs mt-1">
                Comparte el código{" "}
                <span className="font-mono text-[#8B5CF6]">
                  {tournament.code}
                </span>{" "}
                para que se unan
              </p>
            </div>
          ) : (
            <div className="divide-y divide-white/[0.03]">
              {tournament.members.map((member, idx) => (
                <motion.div
                  key={member.id}
                  initial={{ opacity: 0, y: -8 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, x: -10 }}
                  transition={{ duration: 0.25, delay: idx * 0.03 }}
                  className={`grid px-6 py-4 hover:bg-[#1A1F2E]/50 transition-colors duration-150 items-center
                    ${isAdmin ? "grid-cols-[2fr_2fr_1.5fr_1fr_auto]" : "grid-cols-[2fr_2fr_1.5fr_1fr]"}`}
                >
                  {/* Name */}
                  <div className="flex items-center gap-3">
                    <div className="w-7 h-7 rounded-full bg-linear-to-br from-[#8B5CF6]/20 to-[#6D28D9]/20 border border-[#8B5CF6]/15 flex items-center justify-center shrink-0">
                      <span className="text-[#8B5CF6] text-xs font-semibold">
                        {member.displayName.charAt(0).toUpperCase()}
                      </span>
                    </div>
                    <span className="text-[#F3F4F6] text-sm font-medium">
                      {member.displayName}
                    </span>
                  </div>

                  {/* Team */}
                  <div className="flex items-center gap-2">
                    {member.team?.crestUrl && (
                      <img src={member.team.crestUrl} alt={member.team.name} className="w-5 h-5 object-contain shrink-0" />
                    )}
                    <span className={`text-sm ${member.team ? "text-[#F3F4F6]" : "text-[#9CA3AF]/40 italic"}`}>
                      {member.team?.name ?? "Sin asignar"}
                    </span>
                  </div>

                  {/* Budget */}
                  <span className={`text-sm font-medium ${member.budget ? "text-[#22C55E]" : "text-[#9CA3AF]/40"}`}>
                    {formatBudget(member.budget)}
                  </span>

                  {/* Status */}
                  <div>
                    <Badge
                      status={member.team ? "assigned" : "pending"}
                      label={member.team ? "Asignado" : "Pendiente"}
                    />
                  </div>

                  {/* Delete — solo admin */}
                  {isAdmin && (
                    <button
                      onClick={() => handleDeleteMember(member.id)}
                      disabled={deletingId === member.id}
                      title={confirmDelete === member.id ? "Haz clic de nuevo para confirmar" : "Eliminar participante"}
                      className={`w-7 h-7 rounded-lg flex items-center justify-center transition-all duration-150 cursor-pointer ml-2
                        ${confirmDelete === member.id
                          ? "bg-[#EF4444]/20 text-[#EF4444] border border-[#EF4444]/40"
                          : "bg-transparent hover:bg-[#EF4444]/10 text-[#9CA3AF]/40 hover:text-[#EF4444] border border-transparent hover:border-[#EF4444]/20"
                        } disabled:opacity-40`}
                    >
                      {deletingId === member.id ? (
                        <span className="w-3 h-3 border border-current border-t-transparent rounded-full animate-spin" />
                      ) : confirmDelete === member.id ? (
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                          <polyline points="20 6 9 17 4 12" />
                        </svg>
                      ) : (
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                          <polyline points="3 6 5 6 21 6" />
                          <path d="M19 6l-1 14H6L5 6" />
                          <path d="M10 11v6M14 11v6" />
                          <path d="M9 6V4h6v2" />
                        </svg>
                      )}
                    </button>
                  )}
                </motion.div>
              ))}
            </div>
          )}
        </AnimatePresence>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-white/[0.04] flex items-center justify-between">
          {isAdmin && (
            <span className="text-[#9CA3AF] text-xs flex items-center gap-1.5">
              <svg
                width="11"
                height="11"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#8B5CF6"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
              </svg>
              Eres el administrador de este torneo
            </span>
          )}
        </div>
      </div>
    </div>
  );
}
