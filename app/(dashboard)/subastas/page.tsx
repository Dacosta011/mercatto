"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  getLastTournamentCode,
  getMemberToken,
  getAdminToken,
} from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { playSound } from "@/lib/sounds";

// ── Types ─────────────────────────────────────────────────────────────────────

interface AuctionIcon {
  id: string;
  name: string;
  ovr: number;
  position: string;
  nation: string;
  headshotUrl: string | null;
}

interface Auction {
  id: string;
  phase: "pending" | "active" | "finished";
  startsAt: string | null;
  endsAt: string | null;
  minBid: number;
  highestBid: number;
  highestBidderId: string | null;
  highestBidderName: string | null;
  winnerId: string | null;
  winnerName: string | null;
  finalAmount: number | null;
  icon: AuctionIcon | null;
  isMyBid: boolean;
  timeRemainingMs: number | null;
}

interface BidEntry {
  id: string;
  memberId: string;
  memberName: string;
  amount: number;
  createdAt: string;
  isMe: boolean;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmt(v: number) {
  if (!v || isNaN(v)) return "—";
  if (v >= 1_000_000) return `€${(v / 1_000_000).toFixed(1)}M`;
  if (v >= 1_000) return `€${(v / 1_000).toFixed(0)}K`;
  return `€${v}`;
}

function ovrColor(ovr: number) {
  if (ovr >= 87) return { bg: "#22C55E", text: "#fff" };
  if (ovr >= 83) return { bg: "#84CC16", text: "#111" };
  if (ovr >= 79) return { bg: "#F59E0B", text: "#111" };
  return { bg: "#9CA3AF", text: "#fff" };
}

function useCountdown(endsAt: string | null) {
  const [ms, setMs] = useState(0);
  useEffect(() => {
    if (!endsAt) return;
    const tick = () =>
      setMs(Math.max(0, new Date(endsAt).getTime() - Date.now()));
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [endsAt]);

  if (!endsAt || ms <= 0) return { text: "Finalizada", urgent: false, warning: false };
  const totalSec = Math.floor(ms / 1000);
  const h = Math.floor(totalSec / 3600);
  const m = Math.floor((totalSec % 3600) / 60);
  const s = totalSec % 60;
  const text =
    h > 0
      ? `${h}h ${m}m ${s}s`
      : m > 0
        ? `${m}m ${s}s`
        : `${s}s`;
  return { text, urgent: ms < 2 * 60 * 1000, warning: ms < 10 * 60 * 1000 };
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function SubastasPage() {
  const [code, setCode] = useState<string | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [adminToken, setAdminToken] = useState<string | null>(null);
  const [auctions, setAuctions] = useState<Auction[]>([]);
  const [myBudget, setMyBudget] = useState(0);
  const [myIconSlotUsed, setMyIconSlotUsed] = useState(false);
  const [loading, setLoading] = useState(true);
  const [modal, setModal] = useState<
    null | "create" | { type: "auction"; auction: Auction }
  >(null);
  const channelRef = useRef<RealtimeChannel | null>(null);

  useEffect(() => {
    const c = getLastTournamentCode();
    const t = c ? getMemberToken(c) : null;
    const a = c ? getAdminToken(c) : null;
    setCode(c);
    setToken(t);
    setAdminToken(a);
  }, []);

  const [fetchError, setFetchError] = useState<string | null>(null);

  const fetchAuctions = useCallback(async () => {
    if (!code || !token) return;
    try {
      const res = await fetch(`/api/tournaments/${code}/auctions`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) {
        const errData = await res.json().catch(() => ({}));
        setFetchError(errData.error ?? `Error ${res.status}`);
        return;
      }
      setFetchError(null);
      const data = await res.json();
      setAuctions(data.auctions ?? []);
      setMyBudget(data.myBudget ?? 0);
      setMyIconSlotUsed(data.myIconSlotUsed ?? false);
    } catch {
      setFetchError("Error de conexión.");
    } finally {
      setLoading(false);
    }
  }, [code, token]);

  useEffect(() => {
    fetchAuctions();
  }, [fetchAuctions]);

  // Realtime subscription
  useEffect(() => {
    if (!code || !token) return;
    const sb = getBrowserClient();

    channelRef.current = sb
      .channel("subastas-live")
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "icon_auctions" },
        () => fetchAuctions()
      )
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "icon_bids" },
        () => fetchAuctions()
      )
      .subscribe();

    return () => {
      channelRef.current?.unsubscribe();
    };
  }, [code, token, fetchAuctions]);

  if (!code || !token) {
    return (
      <div className="min-h-screen flex items-center justify-center p-8">
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-10 max-w-sm w-full text-center">
          <p className="text-3xl mb-3">🔒</p>
          <p className="text-[#F3F4F6] font-semibold">Sin sesión</p>
          <p className="text-[#9CA3AF] text-sm mt-1">
            Únete a un torneo para acceder a las subastas.
          </p>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="w-10 h-10 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          <p className="text-[#9CA3AF] text-sm">Cargando subastas…</p>
        </div>
      </div>
    );
  }

  const activeAuctions = auctions.filter((a) => a.phase === "active");
  const pendingAuctions = auctions.filter((a) => a.phase === "pending");
  const finishedAuctions = auctions.filter((a) => a.phase === "finished");

  return (
    <div className="min-h-screen bg-[#0D0F14] p-6">
      <div className="max-w-6xl mx-auto">
        {/* Header */}
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-[#F3F4F6] text-2xl font-bold tracking-tight flex items-center gap-3">
              <svg
                width="28"
                height="28"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#8B5CF6"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
              </svg>
              Subastas de Íconos
            </h1>
            <p className="text-[#9CA3AF] text-sm mt-1">
              Puja por leyendas del fútbol. Las subastas son estilo eBay con
              protección anti-sniping.
            </p>
          </div>
          <div className="flex items-center gap-4">
            {/* My budget */}
            <div className="bg-[#131722] rounded-xl border border-white/8 px-4 py-2.5">
              <p className="text-[#6B7280] text-[10px] uppercase font-medium">
                Presupuesto
              </p>
              <p className="text-[#F3F4F6] text-base font-bold">{fmt(myBudget)}</p>
            </div>
            <div className="bg-[#131722] rounded-xl border border-white/8 px-4 py-2.5">
              <p className="text-[#6B7280] text-[10px] uppercase font-medium">
                Slot ícono
              </p>
              <p
                className={`text-base font-bold ${myIconSlotUsed ? "text-[#EF4444]" : "text-[#22C55E]"}`}
              >
                {myIconSlotUsed ? "Usado" : "Disponible"}
              </p>
            </div>
            {adminToken && (
              <button
                onClick={() => setModal("create")}
                className="px-5 py-2.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white font-semibold text-sm transition-colors cursor-pointer flex items-center gap-2"
              >
                <svg
                  width="14"
                  height="14"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <line x1="12" y1="5" x2="12" y2="19" />
                  <line x1="5" y1="12" x2="19" y2="12" />
                </svg>
                Nueva Subasta
              </button>
            )}
          </div>
        </div>

        {/* Active Auctions */}
        {activeAuctions.length > 0 && (
          <section className="mb-10">
            <h2 className="text-[#F3F4F6] text-lg font-semibold mb-4 flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-[#22C55E] animate-pulse" />
              Subastas Activas
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5">
              {activeAuctions.map((a) => (
                <AuctionCard
                  key={a.id}
                  auction={a}
                  onEnter={() => setModal({ type: "auction", auction: a })}
                />
              ))}
            </div>
          </section>
        )}

        {/* Upcoming */}
        {pendingAuctions.length > 0 && (
          <section className="mb-10">
            <h2 className="text-[#F3F4F6] text-lg font-semibold mb-4 flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-[#F59E0B]" />
              Próximas Subastas
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5">
              {pendingAuctions.map((a) => (
                <AuctionCard key={a.id} auction={a} />
              ))}
            </div>
          </section>
        )}

        {/* Finished */}
        {finishedAuctions.length > 0 && (
          <section className="mb-10">
            <h2 className="text-[#9CA3AF] text-lg font-semibold mb-4">
              Subastas Finalizadas
            </h2>
            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5">
              {finishedAuctions.map((a) => (
                <AuctionCard key={a.id} auction={a} />
              ))}
            </div>
          </section>
        )}

        {/* Error state */}
        {fetchError && (
          <div className="mb-6 rounded-2xl bg-[#EF4444]/10 border border-[#EF4444]/20 p-5">
            <p className="text-[#EF4444] text-sm font-semibold mb-1">Error al cargar subastas</p>
            <p className="text-[#EF4444]/70 text-xs">{fetchError}</p>
          </div>
        )}

        {/* Empty state */}
        {!fetchError && auctions.length === 0 && (
          <div className="flex flex-col items-center justify-center py-24">
            <div className="w-20 h-20 rounded-3xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center mb-6">
              <svg
                width="36"
                height="36"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#8B5CF6"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
              </svg>
            </div>
            <h2 className="text-[#F3F4F6] text-xl font-bold mb-2">
              No hay subastas activas
            </h2>
            <p className="text-[#9CA3AF] text-sm text-center max-w-md">
              El administrador puede programar subastas de íconos durante el
              mercado. Cuando una subasta comience, aparecerá aquí.
            </p>
          </div>
        )}
      </div>

      {/* ── Modals ─────────────────────────────────────────────────────────────── */}
      <AnimatePresence>
        {modal === "create" && adminToken && (
          <CreateAuctionModal
            code={code}
            token={adminToken}
            onClose={() => setModal(null)}
            onCreated={() => {
              setModal(null);
              fetchAuctions();
            }}
          />
        )}

        {modal && typeof modal === "object" && modal.type === "auction" && (
          <AuctionDetailModal
            code={code}
            token={token}
            auction={modal.auction}
            myBudget={myBudget}
            myIconSlotUsed={myIconSlotUsed}
            onClose={() => setModal(null)}
            onBidPlaced={fetchAuctions}
          />
        )}
      </AnimatePresence>
    </div>
  );
}

// ── Auction Card ──────────────────────────────────────────────────────────────

function AuctionCard({
  auction: a,
  onEnter,
}: {
  auction: Auction;
  onEnter?: () => void;
}) {
  const icon = a.icon;
  const col = icon ? ovrColor(icon.ovr) : { bg: "#9CA3AF", text: "#fff" };
  const isActive = a.phase === "active";
  const isFinished = a.phase === "finished";
  const countdown = useCountdown(isActive ? a.endsAt : null);

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.2 }}
      className={`rounded-2xl border p-5 transition-colors ${
        isActive
          ? "bg-[#131722] border-[#8B5CF6]/30 shadow-[0_0_30px_rgba(139,92,246,0.08)]"
          : isFinished
            ? "bg-[#0D0F14] border-white/4 opacity-70"
            : "bg-[#131722] border-white/8"
      }`}
    >
      {/* Icon header */}
      {icon && (
        <div className="flex items-center gap-4 mb-4">
          <div className="w-20 h-20 rounded-2xl bg-linear-to-b from-[#8B5CF6]/10 to-transparent border border-white/8 overflow-hidden flex items-center justify-center shrink-0">
            {icon.headshotUrl ? (
              <img
                src={icon.headshotUrl}
                alt={icon.name}
                className="w-full h-full object-contain object-bottom"
              />
            ) : (
              <span
                className="text-3xl font-black"
                style={{ color: col.bg }}
              >
                {icon.ovr}
              </span>
            )}
          </div>
          <div className="min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <span
                className="px-2 py-0.5 rounded-lg text-xs font-black"
                style={{ background: col.bg, color: col.text }}
              >
                {icon.ovr}
              </span>
              <span className="px-2 py-0.5 rounded-lg text-xs font-bold bg-white/8 text-[#F3F4F6]">
                {icon.position}
              </span>
            </div>
            <p className="text-[#F3F4F6] text-lg font-bold truncate">
              {icon.name}
            </p>
            <p className="text-[#9CA3AF] text-xs">{icon.nation}</p>
          </div>
        </div>
      )}

      {/* Stats */}
      <div className="grid grid-cols-2 gap-3 mb-4">
        <div className="rounded-xl bg-[#0D0F14] border border-white/6 px-3 py-2.5">
          <p className="text-[#6B7280] text-[10px] uppercase font-medium">
            Puja mínima
          </p>
          <p className="text-[#F3F4F6] text-sm font-bold mt-0.5">
            {fmt(a.minBid)}
          </p>
        </div>
        <div className="rounded-xl bg-[#0D0F14] border border-white/6 px-3 py-2.5">
          <p className="text-[#6B7280] text-[10px] uppercase font-medium">
            {isFinished ? "Precio final" : "Puja más alta"}
          </p>
          <p
            className={`text-sm font-bold mt-0.5 ${
              a.isMyBid ? "text-[#8B5CF6]" : "text-[#22C55E]"
            }`}
          >
            {isFinished
              ? fmt(a.finalAmount ?? 0)
              : a.highestBid > 0
                ? fmt(a.highestBid)
                : "Sin pujas"}
          </p>
          {a.highestBidderName && !isFinished && (
            <p className="text-[#6B7280] text-[10px] mt-0.5 truncate">
              por {a.isMyBid ? "Ti" : a.highestBidderName}
            </p>
          )}
        </div>
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between">
        {isActive && (
          <>
            <div className="flex items-center gap-2">
              <span
                className={`w-2 h-2 rounded-full ${countdown.urgent ? "bg-[#EF4444]" : "bg-[#22C55E]"} animate-pulse`}
              />
              <span
                className={`text-xs font-semibold ${
                  countdown.urgent
                    ? "text-[#EF4444]"
                    : countdown.warning
                      ? "text-[#F59E0B]"
                      : "text-[#22C55E]"
                }`}
              >
                {countdown.text}
              </span>
            </div>
            <button
              onClick={onEnter}
              className="px-4 py-2 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white text-sm font-semibold transition-colors cursor-pointer"
            >
              Entrar a subasta
            </button>
          </>
        )}
        {a.phase === "pending" && (
          <span className="text-[#F59E0B] text-xs font-semibold">
            Próximamente
          </span>
        )}
        {isFinished && (
          <div className="flex items-center justify-between w-full">
            <span className="text-[#9CA3AF] text-xs">
              Ganador:{" "}
              <span className="text-[#F3F4F6] font-semibold">
                {a.winnerName ?? "Sin ganador"}
              </span>
            </span>
            {a.finalAmount ? (
              <span className="text-[#22C55E] text-sm font-bold">
                {fmt(a.finalAmount)}
              </span>
            ) : null}
          </div>
        )}
      </div>

      {/* "Your highest bid" indicator */}
      {isActive && a.isMyBid && (
        <div className="mt-3 rounded-lg bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 px-3 py-2 text-center">
          <p className="text-[#8B5CF6] text-xs font-semibold">
            Tienes la puja más alta
          </p>
        </div>
      )}
    </motion.div>
  );
}

// ── Create Auction Modal (Admin) ──────────────────────────────────────────────

function CreateAuctionModal({
  code,
  token,
  onClose,
  onCreated,
}: {
  code: string;
  token: string;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [icons, setIcons] = useState<AuctionIcon[]>([]);
  const [selectedIcon, setSelectedIcon] = useState<string | null>(null);
  const [minBid, setMinBid] = useState("5");
  const [durationMin, setDurationMin] = useState("120");
  const [search, setSearch] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function loadIcons() {
      try {
        const res = await fetch(`/api/tournaments/${code}/icons`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) return;
        const data = await res.json();
        setIcons(data.icons ?? []);
      } catch {
        /* silent */
      }
    }
    loadIcons();
  }, [code, token]);

  const filtered = icons.filter(
    (i) =>
      i.name.toLowerCase().includes(search.toLowerCase()) ||
      i.position.toLowerCase().includes(search.toLowerCase())
  );

  async function handleCreate() {
    if (!selectedIcon) return;
    setSubmitting(true);
    setError(null);
    try {
      const res = await fetch(`/api/tournaments/${code}/auctions`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          iconId: selectedIcon,
          minBid: Number(minBid) * 1_000_000,
          durationMinutes: Number(durationMin),
        }),
      });
      if (!res.ok) {
        const data = await res.json();
        setError(data.error ?? "Error al crear subasta.");
        return;
      }
      onCreated();
    } catch {
      setError("Error de conexión.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4"
      onClick={onClose}
    >
      <motion.div
        initial={{ scale: 0.95, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        exit={{ scale: 0.95, opacity: 0 }}
        className="bg-[#131722] rounded-2xl border border-white/8 w-full max-w-lg max-h-[85vh] flex flex-col overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-6 py-5 border-b border-white/6">
          <h2 className="text-[#F3F4F6] text-lg font-bold">
            Programar Subasta
          </h2>
          <p className="text-[#9CA3AF] text-sm mt-1">
            Selecciona un ícono y configura la subasta.
          </p>
        </div>

        <div className="px-6 py-5 space-y-5 overflow-y-auto flex-1">
          {/* Search icons */}
          <div>
            <label className="text-[#9CA3AF] text-xs font-medium uppercase mb-2 block">
              Seleccionar Ícono
            </label>
            <input
              type="text"
              placeholder="Buscar ícono…"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full px-4 py-2.5 rounded-xl bg-[#0D0F14] border border-white/8 text-[#F3F4F6] text-sm placeholder-[#4B5563] focus:outline-none focus:border-[#8B5CF6]/50"
            />
          </div>

          {/* Icons grid */}
          <div className="grid grid-cols-2 gap-2 max-h-56 overflow-y-auto pr-1">
            {filtered.map((icon) => {
              const col = ovrColor(icon.ovr);
              const sel = selectedIcon === icon.id;
              return (
                <button
                  key={icon.id}
                  onClick={() => setSelectedIcon(icon.id)}
                  className={`flex items-center gap-3 p-3 rounded-xl border text-left transition-all cursor-pointer ${
                    sel
                      ? "bg-[#8B5CF6]/10 border-[#8B5CF6]/40"
                      : "bg-[#0D0F14] border-white/6 hover:border-white/12"
                  }`}
                >
                  <div className="w-10 h-10 rounded-lg bg-[#131722] border border-white/8 flex items-center justify-center shrink-0">
                    {icon.headshotUrl ? (
                      <img
                        src={icon.headshotUrl}
                        alt={icon.name}
                        className="w-full h-full object-contain rounded-lg"
                      />
                    ) : (
                      <span
                        className="text-sm font-black"
                        style={{ color: col.bg }}
                      >
                        {icon.ovr}
                      </span>
                    )}
                  </div>
                  <div className="min-w-0">
                    <p className="text-[#F3F4F6] text-xs font-semibold truncate">
                      {icon.name}
                    </p>
                    <div className="flex items-center gap-1 mt-0.5">
                      <span
                        className="px-1.5 py-0.5 rounded text-[10px] font-bold"
                        style={{ background: col.bg, color: col.text }}
                      >
                        {icon.ovr}
                      </span>
                      <span className="text-[#9CA3AF] text-[10px]">
                        {icon.position}
                      </span>
                    </div>
                  </div>
                  {sel && (
                    <svg
                      className="w-5 h-5 text-[#8B5CF6] shrink-0 ml-auto"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      strokeWidth="2.5"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  )}
                </button>
              );
            })}
            {filtered.length === 0 && (
              <p className="col-span-2 text-[#9CA3AF] text-sm text-center py-4">
                No se encontraron íconos.
              </p>
            )}
          </div>

          {/* Config */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="text-[#9CA3AF] text-xs font-medium uppercase mb-2 block">
                Puja mínima (M€)
              </label>
              <input
                type="number"
                min={0}
                value={minBid}
                onChange={(e) => setMinBid(e.target.value)}
                className="w-full px-4 py-2.5 rounded-xl bg-[#0D0F14] border border-white/8 text-[#F3F4F6] text-sm focus:outline-none focus:border-[#8B5CF6]/50"
              />
            </div>
            <div>
              <label className="text-[#9CA3AF] text-xs font-medium uppercase mb-2 block">
                Duración (min)
              </label>
              <input
                type="number"
                min={10}
                value={durationMin}
                onChange={(e) => setDurationMin(e.target.value)}
                className="w-full px-4 py-2.5 rounded-xl bg-[#0D0F14] border border-white/8 text-[#F3F4F6] text-sm focus:outline-none focus:border-[#8B5CF6]/50"
              />
            </div>
          </div>

          {error && (
            <div className="rounded-xl bg-[#EF4444]/10 border border-[#EF4444]/20 px-4 py-3">
              <p className="text-[#EF4444] text-sm">{error}</p>
            </div>
          )}
        </div>

        <div className="px-6 py-4 border-t border-white/6 flex justify-end gap-3">
          <button
            onClick={onClose}
            className="px-5 py-2.5 rounded-xl bg-white/5 hover:bg-white/8 text-[#9CA3AF] text-sm font-semibold transition-colors cursor-pointer"
          >
            Cancelar
          </button>
          <button
            onClick={handleCreate}
            disabled={!selectedIcon || submitting}
            className="px-5 py-2.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] disabled:opacity-40 text-white text-sm font-semibold transition-colors cursor-pointer"
          >
            {submitting ? "Creando…" : "Crear Subasta"}
          </button>
        </div>
      </motion.div>
    </motion.div>
  );
}

// ── Auction Detail Modal (Bidding) ────────────────────────────────────────────

function AuctionDetailModal({
  code,
  token,
  auction,
  myBudget,
  myIconSlotUsed,
  onClose,
  onBidPlaced,
}: {
  code: string;
  token: string;
  auction: Auction;
  myBudget: number;
  myIconSlotUsed: boolean;
  onClose: () => void;
  onBidPlaced: () => void;
}) {
  const [detail, setDetail] = useState<Auction>(auction);
  const [bids, setBids] = useState<BidEntry[]>([]);
  const [bidAmount, setBidAmount] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);
  const countdown = useCountdown(detail.endsAt);

  const fetchDetail = useCallback(async () => {
    try {
      const res = await fetch(
        `/api/tournaments/${code}/auctions/${auction.id}`,
        { headers: { Authorization: `Bearer ${token}` } }
      );
      if (!res.ok) return;
      const data = await res.json();
      setDetail(data.auction);
      setBids(data.bids ?? []);
    } catch {
      /* silent */
    }
  }, [code, token, auction.id]);

  useEffect(() => {
    fetchDetail();
  }, [fetchDetail]);

  // Realtime polling for active auctions
  useEffect(() => {
    if (detail.phase !== "active") return;
    const id = setInterval(fetchDetail, 5000);
    return () => clearInterval(id);
  }, [detail.phase, fetchDetail]);

  const icon = detail.icon;
  const col = icon ? ovrColor(icon.ovr) : { bg: "#9CA3AF", text: "#fff" };
  const minNext = Math.max(detail.minBid, detail.highestBid + 1_000_000);
  const canBid = !myIconSlotUsed && detail.phase === "active" && !detail.isMyBid;

  async function handleBid() {
    const amount = Number(bidAmount) * 1_000_000;
    if (!amount || amount <= 0) return;
    setSubmitting(true);
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await fetch(
        `/api/tournaments/${code}/auctions/${auction.id}/bid`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ amount }),
        }
      );
      const data = await res.json();
      if (!res.ok) {
        setError(data.error ?? "Error al pujar.");
        return;
      }
      setSuccessMsg(
        data.antiSnipeExtended
          ? `Puja de €${bidAmount}M registrada. Anti-sniping: se extendió el tiempo.`
          : `Puja de €${bidAmount}M registrada.`
      );
      playSound("success");
      setBidAmount("");
      onBidPlaced();
      fetchDetail();
    } catch {
      setError("Error de conexión.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4"
      onClick={onClose}
    >
      <motion.div
        initial={{ scale: 0.95, opacity: 0 }}
        animate={{ scale: 1, opacity: 1 }}
        exit={{ scale: 0.95, opacity: 0 }}
        className="bg-[#131722] rounded-2xl border border-white/8 w-full max-w-md max-h-[85vh] flex flex-col overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="px-6 py-5 border-b border-white/6">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              {icon && (
                <div className="w-14 h-14 rounded-xl bg-linear-to-b from-[#8B5CF6]/10 to-transparent border border-white/8 overflow-hidden flex items-center justify-center shrink-0">
                  {icon.headshotUrl ? (
                    <img
                      src={icon.headshotUrl}
                      alt={icon.name}
                      className="w-full h-full object-contain object-bottom"
                    />
                  ) : (
                    <span
                      className="text-xl font-black"
                      style={{ color: col.bg }}
                    >
                      {icon.ovr}
                    </span>
                  )}
                </div>
              )}
              <div>
                <p className="text-[#F3F4F6] text-lg font-bold">
                  {icon?.name ?? "Subasta"}
                </p>
                <div className="flex items-center gap-2 mt-0.5">
                  {icon && (
                    <>
                      <span
                        className="px-2 py-0.5 rounded-lg text-xs font-black"
                        style={{ background: col.bg, color: col.text }}
                      >
                        {icon.ovr}
                      </span>
                      <span className="text-[#9CA3AF] text-xs">
                        {icon.position} · {icon.nation}
                      </span>
                    </>
                  )}
                </div>
              </div>
            </div>
            <button
              onClick={onClose}
              className="w-8 h-8 rounded-lg bg-white/5 hover:bg-white/10 flex items-center justify-center cursor-pointer"
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#9CA3AF"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <line x1="18" y1="6" x2="6" y2="18" />
                <line x1="6" y1="6" x2="18" y2="18" />
              </svg>
            </button>
          </div>
        </div>

        <div className="px-6 py-5 space-y-4 overflow-y-auto flex-1">
          {/* Timer */}
          {detail.phase === "active" && (
            <div
              className={`rounded-xl border px-4 py-3 text-center ${
                countdown.urgent
                  ? "bg-[#EF4444]/10 border-[#EF4444]/30"
                  : countdown.warning
                    ? "bg-[#F59E0B]/10 border-[#F59E0B]/30"
                    : "bg-[#22C55E]/10 border-[#22C55E]/30"
              }`}
            >
              <p className="text-[#6B7280] text-[10px] uppercase font-medium mb-1">
                Tiempo restante
              </p>
              <p
                className={`text-2xl font-bold tabular-nums ${
                  countdown.urgent
                    ? "text-[#EF4444]"
                    : countdown.warning
                      ? "text-[#F59E0B]"
                      : "text-[#22C55E]"
                }`}
              >
                {countdown.text}
              </p>
              {countdown.urgent && (
                <p className="text-[#EF4444] text-xs mt-1 font-medium">
                  Anti-sniping activo: pujas extienden +2 min
                </p>
              )}
            </div>
          )}

          {/* Current highest bid */}
          <div className="rounded-xl bg-[#0D0F14] border border-white/6 p-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <p className="text-[#6B7280] text-[10px] uppercase font-medium">
                  {detail.phase === "finished" ? "Precio final" : "Puja más alta"}
                </p>
                <p className="text-[#22C55E] text-xl font-bold mt-1">
                  {detail.highestBid > 0
                    ? fmt(detail.phase === "finished" ? (detail.finalAmount ?? detail.highestBid) : detail.highestBid)
                    : "Sin pujas"}
                </p>
                {detail.highestBidderName && (
                  <p className="text-[#9CA3AF] text-xs mt-0.5">
                    por{" "}
                    <span className="text-[#F3F4F6] font-semibold">
                      {detail.isMyBid ? "Ti" : detail.highestBidderName}
                    </span>
                  </p>
                )}
              </div>
              <div>
                <p className="text-[#6B7280] text-[10px] uppercase font-medium">
                  Tu presupuesto
                </p>
                <p className="text-[#F3F4F6] text-xl font-bold mt-1">
                  {fmt(myBudget)}
                </p>
              </div>
            </div>
          </div>

          {/* Bid input */}
          {canBid && (
            <div className="space-y-3">
              <label className="text-[#9CA3AF] text-xs font-medium uppercase">
                Tu puja (M€)
              </label>
              <div className="flex items-center gap-3">
                <input
                  type="number"
                  min={Math.ceil(minNext / 1_000_000)}
                  max={Math.floor(myBudget / 1_000_000)}
                  value={bidAmount}
                  onChange={(e) => setBidAmount(e.target.value)}
                  placeholder={`Min. €${Math.ceil(minNext / 1_000_000)}M`}
                  className="flex-1 px-4 py-3 rounded-xl bg-[#0D0F14] border border-white/8 text-[#F3F4F6] text-sm placeholder-[#4B5563] focus:outline-none focus:border-[#8B5CF6]/50"
                />
                <button
                  onClick={handleBid}
                  disabled={submitting || !bidAmount}
                  className="px-6 py-3 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] disabled:opacity-40 text-white font-semibold text-sm transition-colors cursor-pointer shrink-0"
                >
                  {submitting ? "Pujando…" : "Pujar"}
                </button>
              </div>
              {/* Quick bid buttons */}
              <div className="flex gap-2">
                {[
                  Math.ceil(minNext / 1_000_000),
                  Math.ceil(minNext / 1_000_000) + 5,
                  Math.ceil(minNext / 1_000_000) + 10,
                ]
                  .filter((v) => v * 1_000_000 <= myBudget)
                  .map((v) => (
                    <button
                      key={v}
                      onClick={() => setBidAmount(String(v))}
                      className="px-3 py-1.5 rounded-lg bg-white/5 hover:bg-white/8 text-[#9CA3AF] hover:text-[#F3F4F6] text-xs font-semibold transition-colors cursor-pointer"
                    >
                      €{v}M
                    </button>
                  ))}
              </div>
            </div>
          )}

          {/* Status messages */}
          {detail.isMyBid && detail.phase === "active" && (
            <div className="rounded-xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 px-4 py-3 text-center">
              <p className="text-[#8B5CF6] text-sm font-semibold">
                Tienes la puja más alta. ¡Espera a que termine la subasta!
              </p>
            </div>
          )}

          {myIconSlotUsed && detail.phase === "active" && (
            <div className="rounded-xl bg-[#EF4444]/10 border border-[#EF4444]/20 px-4 py-3 text-center">
              <p className="text-[#EF4444] text-sm">
                Ya usaste tu slot de ícono en este mercado.
              </p>
            </div>
          )}

          {detail.phase === "finished" && (
            <div className="rounded-xl bg-white/5 border border-white/8 px-4 py-3 text-center">
              <p className="text-[#9CA3AF] text-sm">
                Subasta finalizada.{" "}
                {detail.winnerName ? (
                  <>
                    Ganador:{" "}
                    <span className="text-[#F3F4F6] font-semibold">
                      {detail.winnerName}
                    </span>
                  </>
                ) : (
                  "Sin ganador."
                )}
              </p>
            </div>
          )}

          {error && (
            <div className="rounded-xl bg-[#EF4444]/10 border border-[#EF4444]/20 px-4 py-3">
              <p className="text-[#EF4444] text-sm">{error}</p>
            </div>
          )}

          {successMsg && (
            <div className="rounded-xl bg-[#22C55E]/10 border border-[#22C55E]/20 px-4 py-3">
              <p className="text-[#22C55E] text-sm">{successMsg}</p>
            </div>
          )}

          {/* Bid history */}
          {bids.length > 0 && (
            <div>
              <h3 className="text-[#9CA3AF] text-xs font-medium uppercase mb-3">
                Historial de pujas
              </h3>
              <div className="space-y-2 max-h-48 overflow-y-auto">
                {bids.map((b, i) => (
                  <div
                    key={b.id}
                    className={`flex items-center justify-between px-3 py-2.5 rounded-xl ${
                      i === 0
                        ? "bg-[#8B5CF6]/10 border border-[#8B5CF6]/20"
                        : "bg-[#0D0F14] border border-white/4"
                    }`}
                  >
                    <div className="flex items-center gap-2">
                      {i === 0 && (
                        <svg
                          width="14"
                          height="14"
                          viewBox="0 0 24 24"
                          fill="#8B5CF6"
                          stroke="none"
                        >
                          <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
                        </svg>
                      )}
                      <span
                        className={`text-sm font-semibold ${b.isMe ? "text-[#8B5CF6]" : "text-[#F3F4F6]"}`}
                      >
                        {b.isMe ? "Tú" : b.memberName}
                      </span>
                    </div>
                    <div className="text-right">
                      <span className="text-[#22C55E] text-sm font-bold">
                        {fmt(b.amount)}
                      </span>
                      <p className="text-[#6B7280] text-[10px]">
                        {new Date(b.createdAt).toLocaleTimeString("es-ES", {
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </motion.div>
    </motion.div>
  );
}
