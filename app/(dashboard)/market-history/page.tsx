"use client";

import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import { getLastTournamentCode, getMemberToken } from "@/lib/tokenStorage";

// ── Types ─────────────────────────────────────────────────────────────────────

interface SessionSummary {
  id: string;
  status: string;
  marketType: string;
  startedAt: string;
  finishedAt: string | null;
  closesAt: string | null;
  transferCount: number;
}

interface Transfer {
  id: string;
  transferType: string;
  amount: number;
  createdAt: string;
  buyerId: string | null;
  sellerId: string | null;
  buyerName: string;
  sellerName: string;
  sellerTeamName: string;
  playerName: string;
}

interface MemberSummary {
  id: string;
  displayName: string;
  teamName: string | null;
  teamCrestUrl: string | null;
  bought: Transfer[];
  sold: Transfer[];
  totalSpent: number;
}

interface SessionDetail {
  session: {
    id: string;
    status: string;
    marketType: string;
    startedAt: string;
    finishedAt: string | null;
  };
  stats: {
    totalTransfers: number;
    totalSpent: number;
    clauseCount: number;
    auctionCount: number;
    offerCount: number;
    biggestDeal: Transfer | null;
  };
  members: MemberSummary[];
  transfers: Transfer[];
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmt(amount: number) {
  if (amount >= 1_000_000_000) return `€${(amount / 1_000_000_000).toFixed(1)}B`;
  if (amount >= 1_000_000) return `€${Math.round(amount / 1_000_000)}M`;
  if (amount >= 1_000) return `€${Math.round(amount / 1_000)}K`;
  return `€${amount}`;
}

function sessionLabel(s: SessionSummary) {
  const type = s.marketType === "winter" ? "Mercado de Invierno" : "Mercado Regular";
  const date = new Date(s.startedAt).toLocaleDateString("es", {
    day: "numeric", month: "short", year: "numeric",
  });
  return `${type} · ${date}`;
}

function statusBadge(status: string) {
  if (status === "active") return (
    <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-[#22C55E] bg-[#22C55E]/10 px-2 py-0.5 rounded-full">
      <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E] animate-pulse" />
      Activo
    </span>
  );
  if (status === "finished") return (
    <span className="text-[10px] font-semibold text-[#9CA3AF] bg-white/5 px-2 py-0.5 rounded-full">
      Cerrado
    </span>
  );
  return null;
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function MarketHistoryPage() {
  const [sessions, setSessions] = useState<SessionSummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<SessionDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Fetch session list
  useEffect(() => {
    async function load() {
      const code = getLastTournamentCode();
      const token = code ? getMemberToken(code) : null;
      if (!code || !token) { setError("No hay torneo activo."); setLoading(false); return; }

      const res = await fetch(`/api/tournaments/${code}/market/history`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) { setError("No se pudo cargar el historial."); setLoading(false); return; }

      const data = await res.json();
      setSessions(data.sessions ?? []);
      if (data.sessions?.length > 0) setSelectedId(data.sessions[0].id);
      setLoading(false);
    }
    load();
  }, []);

  // Fetch session detail when selection changes
  useEffect(() => {
    if (!selectedId) return;
    async function loadDetail() {
      setLoadingDetail(true);
      setDetail(null);
      const code = getLastTournamentCode();
      const token = code ? getMemberToken(code) : null;
      if (!code || !token) return;

      const res = await fetch(
        `/api/tournaments/${code}/market/history?sessionId=${selectedId}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );
      if (res.ok) setDetail(await res.json());
      setLoadingDetail(false);
    }
    loadDetail();
  }, [selectedId]);

  if (loading) return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <div className="w-6 h-6 border-2 border-[#8B5CF6] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (error) return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <p className="text-[#9CA3AF] text-sm">{error}</p>
    </div>
  );

  if (sessions.length === 0) return (
    <div className="flex flex-col items-center justify-center min-h-[60vh] gap-3">
      <p className="text-[#F3F4F6] font-semibold">Sin historial de mercado</p>
      <p className="text-[#9CA3AF] text-sm text-center px-8">
        Todavía no se ha abierto ningún mercado en este torneo.
      </p>
    </div>
  );

  const selectedSession = sessions.find(s => s.id === selectedId);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="px-4 py-6 sm:p-8 max-w-5xl mx-auto"
    >
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-[#F3F4F6] text-2xl font-bold tracking-tight mb-1">
          Historial de Mercado
        </h1>
        <p className="text-[#9CA3AF] text-sm">
          Compras y ventas por ventana de fichajes
        </p>
      </div>

      {/* Session selector */}
      <div className="flex gap-2 flex-wrap mb-6">
        {sessions.map((s) => (
          <button
            key={s.id}
            onClick={() => setSelectedId(s.id)}
            className={`flex items-center gap-2 px-3 py-2 rounded-xl text-xs font-medium border transition-all ${
              selectedId === s.id
                ? "bg-[#8B5CF6]/15 border-[#8B5CF6]/40 text-[#C4B5FD]"
                : "bg-[#131722] border-white/6 text-[#9CA3AF] hover:border-white/15"
            }`}
          >
            <span>{s.marketType === "winter" ? "❄️" : "☀️"}</span>
            <span>{sessionLabel(s)}</span>
            {statusBadge(s.status)}
            <span className="text-[#6B7280]">{s.transferCount} fichajes</span>
          </button>
        ))}
      </div>

      {/* Detail */}
      <AnimatePresence mode="wait">
        {loadingDetail && (
          <motion.div
            key="loading"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="flex justify-center py-16"
          >
            <div className="w-6 h-6 border-2 border-[#8B5CF6] border-t-transparent rounded-full animate-spin" />
          </motion.div>
        )}

        {!loadingDetail && detail && (
          <motion.div
            key={selectedId}
            initial={{ opacity: 0, y: 8 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.25 }}
          >
            {/* Global stats */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mb-6">
              <div className="bg-[#131722] rounded-2xl border border-white/6 p-4 text-center">
                <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Transferencias</p>
                <p className="text-[#F3F4F6] text-xl font-bold">{detail.stats.totalTransfers}</p>
              </div>
              <div className="bg-[#131722] rounded-2xl border border-white/6 p-4 text-center">
                <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Total movido</p>
                <p className="text-[#22C55E] text-xl font-bold">{fmt(detail.stats.totalSpent)}</p>
              </div>
              <div className="bg-[#131722] rounded-2xl border border-white/6 p-4 text-center">
                <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Cláusulas</p>
                <p className="text-[#F59E0B] text-xl font-bold">{detail.stats.clauseCount}</p>
              </div>
              <div className="bg-[#131722] rounded-2xl border border-white/6 p-4 text-center">
                <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Subastas</p>
                <p className="text-[#8B5CF6] text-xl font-bold">{detail.stats.auctionCount}</p>
              </div>
            </div>

            {/* Biggest deal */}
            {detail.stats.biggestDeal && (
              <div className="bg-[#131722] rounded-2xl border border-[#8B5CF6]/20 p-4 sm:p-5 mb-6 flex items-center gap-4">
                <div className="w-12 h-12 rounded-2xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center shrink-0">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
                  </svg>
                </div>
                <div className="min-w-0 flex-1">
                  <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-0.5">Fichaje más caro</p>
                  <p className="text-[#F3F4F6] text-base font-bold truncate">{detail.stats.biggestDeal.playerName}</p>
                  <p className="text-[#9CA3AF] text-xs">
                    {detail.stats.biggestDeal.buyerName} ← {detail.stats.biggestDeal.sellerTeamName ?? "Subasta"}
                  </p>
                </div>
                <p className="text-[#22C55E] text-xl font-bold shrink-0">{fmt(detail.stats.biggestDeal.amount)}</p>
              </div>
            )}

            {/* Per-member breakdown */}
            <h2 className="text-[#F3F4F6] text-base font-semibold mb-3">Resumen por Mánager</h2>
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3 mb-8">
              {detail.members.map((m) => (
                <div
                  key={m.id}
                  className="bg-[#131722] rounded-2xl border border-white/6 p-4 flex flex-col gap-3"
                >
                  {/* Manager header */}
                  <div className="flex items-center gap-3">
                    {m.teamCrestUrl ? (
                      <img src={m.teamCrestUrl} alt={m.teamName ?? ""} className="w-8 h-8 object-contain shrink-0" />
                    ) : (
                      <div className="w-8 h-8 rounded-full bg-[#8B5CF6]/15 flex items-center justify-center shrink-0">
                        <span className="text-[#8B5CF6] text-xs font-bold">{m.displayName.charAt(0).toUpperCase()}</span>
                      </div>
                    )}
                    <div className="min-w-0 flex-1">
                      <p className="text-[#F3F4F6] text-sm font-semibold truncate">{m.displayName}</p>
                      {m.teamName && <p className="text-[#9CA3AF] text-[10px] truncate">{m.teamName}</p>}
                    </div>
                    {m.totalSpent > 0 && (
                      <p className="text-[#22C55E] text-xs font-bold shrink-0">{fmt(m.totalSpent)}</p>
                    )}
                  </div>

                  {/* Compras */}
                  {m.bought.length > 0 && (
                    <div className="flex flex-col gap-1">
                      <p className="text-[#6B7280] text-[9px] uppercase font-medium px-1">Compras</p>
                      {m.bought.map((t, i) => (
                        <div key={i} className="flex items-center justify-between text-[10px] bg-[#22C55E]/5 rounded-lg px-2.5 py-1.5">
                          <span className="text-[#F3F4F6] font-medium truncate">{t.playerName}</span>
                          <span className="text-[#22C55E] font-bold shrink-0 ml-2">{fmt(t.amount)}</span>
                        </div>
                      ))}
                    </div>
                  )}

                  {/* Ventas */}
                  {m.sold.length > 0 && (
                    <div className="flex flex-col gap-1">
                      <p className="text-[#6B7280] text-[9px] uppercase font-medium px-1">Ventas</p>
                      {m.sold.map((t, i) => (
                        <div key={i} className="flex items-center justify-between text-[10px] bg-[#EF4444]/5 rounded-lg px-2.5 py-1.5">
                          <span className="text-[#F3F4F6] font-medium truncate">{t.playerName}</span>
                          <span className="text-[#EF4444] font-bold shrink-0 ml-2">{fmt(t.amount)}</span>
                        </div>
                      ))}
                    </div>
                  )}

                  {m.bought.length === 0 && m.sold.length === 0 && (
                    <p className="text-[#4B5563] text-[10px] text-center py-2">Sin movimientos</p>
                  )}
                </div>
              ))}
            </div>

            {/* Full timeline */}
            {detail.transfers.length > 0 && (
              <>
                <h2 className="text-[#F3F4F6] text-base font-semibold mb-3">Todos los movimientos</h2>
                <div className="bg-[#131722] rounded-2xl border border-white/6 divide-y divide-white/4 overflow-hidden">
                  {detail.transfers.map((t, i) => (
                    <div key={i} className="flex items-center gap-3 px-4 py-3">
                      <div className={`w-1.5 h-1.5 rounded-full shrink-0 ${
                        t.transferType === "clause" ? "bg-[#F59E0B]" :
                        t.transferType === "icon_auction" ? "bg-[#8B5CF6]" :
                        "bg-[#22C55E]"
                      }`} />
                      <div className="min-w-0 flex-1">
                        <p className="text-[#F3F4F6] text-xs font-medium truncate">{t.playerName}</p>
                        <p className="text-[#6B7280] text-[10px]">
                          {t.buyerName} ← {t.sellerTeamName}
                        </p>
                      </div>
                      <p className="text-[#22C55E] text-xs font-bold shrink-0">{fmt(t.amount)}</p>
                      <p className="text-[#4B5563] text-[9px] shrink-0 hidden sm:block">
                        {new Date(t.createdAt).toLocaleDateString("es", { day: "numeric", month: "short" })}
                      </p>
                    </div>
                  ))}
                </div>
              </>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </motion.div>
  );
}
