"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import { getLastTournamentCode, getMemberToken, getAdminToken, getMemberId, saveMemberId, saveTournamentStatus } from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";
import type { RealtimeChannel } from "@supabase/supabase-js";
import IconAuction, { IconAuctionInitiateButton } from "../../Components/IconAuction";
import RollingNumber from "../../Components/RollingNumber";

// ── Types ─────────────────────────────────────────────────────────────────────

interface TurnInfo {
  id: string;
  memberId: string;
  memberName: string;
  teamName: string | null;
  teamCrestUrl: string | null;
  position: number;
  status: "pending" | "active" | "completed" | "skipped";
}

interface PlayerCard {
  playerId: string;
  playerName: string;
  headshotUrl: string | null;
  ovr: number;
  position: string;
  price: number;
  clause: number;
  teamId: string;
  teamName: string;
  ownerId: string;
  ownerName: string;
  clauseProtected: boolean;
}

interface MyStatus {
  memberId: string;
  budget: number;
  purchasesUsed: number;
  maxPurchases: number;
  myTeamId: string | null;
  myTeamName: string | null;
  teamClauseProtected: boolean;
  hasPendingOffer: boolean;
}

interface Offer {
  id: string;
  buyerId: string;
  buyerName: string;
  playerId: string;
  playerName: string;
  playerOvr: number | null;
  playerPosition: string;
  playerHeadshot: string | null;
  amount: number;
  createdAt: string;
}

interface MarketState {
  status: "pending" | "active" | "finished";
  session: {
    id: string;
    currentRound: number;
    totalRounds: number;
    allRoundDone: boolean;
  } | null;
  currentTurn: TurnInfo | null;
  isMyTurn: boolean;
  turns: TurnInfo[];
  myStatus: MyStatus;
  availablePlayers: PlayerCard[];
  recentTransfers: any[];
  incomingOffers: Offer[];
  allMembers: { id: string; displayName: string; teamName: string | null; teamCrestUrl: string | null; budget: number; purchasesUsed: number }[];
}

// ── Formatters ────────────────────────────────────────────────────────────────

function fmt(v: number) {
  if (!v || isNaN(v)) return "—";
  if (v >= 1_000_000) return `€${(v / 1_000_000).toFixed(0)}M`;
  if (v >= 1_000)     return `€${(v / 1_000).toFixed(0)}K`;
  return `€${v}`;
}

function ovrColor(ovr: number) {
  if (ovr >= 87) return { bg: "#22C55E", text: "#fff" };
  if (ovr >= 83) return { bg: "#84CC16", text: "#111" };
  if (ovr >= 79) return { bg: "#F59E0B", text: "#111" };
  return { bg: "#9CA3AF", text: "#fff" };
}

// ── Main Page ─────────────────────────────────────────────────────────────────

export default function MarketPage() {
  const [code,        setCode]        = useState<string | null>(null);
  const [token,       setToken]       = useState<string | null>(null);
  const [adminToken,  setAdminToken]  = useState<string | null>(null);
  const [data,        setData]        = useState<MarketState | null>(null);
  const [loading,     setLoading]     = useState(true);
  const [error,       setError]       = useState("");
  const [modal,       setModal]       = useState<"clause" | "offer" | "offers" | "round_end" | null>(null);
  const [selectedPlayer, setSelectedPlayer] = useState<PlayerCard | null>(null);
  const [offerAmount, setOfferAmount] = useState("");
  const [actionLoading, setActionLoading] = useState(false);
  const [actionMsg, setActionMsg] = useState("");
  const [posFilter,  setPosFilter]  = useState("ALL");
  const [teamFilter, setTeamFilter] = useState("ALL");
  const [searchQ,    setSearchQ]    = useState("");
  const [showIconAuction, setShowIconAuction] = useState(false);
  const [roundAuctionDone, setRoundAuctionDone] = useState(false);
  const [myMemberId, setMyMemberId] = useState<string | null>(null);
  const [showSummary, setShowSummary] = useState(false);

  // Realtime
  const channelRef      = useRef<RealtimeChannel | null>(null);
  const sessionIdRef    = useRef<string | null>(null);
  const prevDataRef     = useRef<MarketState | null>(null);   // for toast diffing
  const fetchingRef     = useRef(false);                      // debounce concurrent fetches
  const pendingFetchRef = useRef(false);                      // queue fetch if one is in-flight
  const adminTokenRef   = useRef<string | null>(null);        // stable ref for fetchData

  // Toasts
  interface Toast { id: number; type: "info" | "success" | "warning" | "turn"; message: string; sub?: string }
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastIdRef = useRef(0);

  const pushToast = useCallback((type: Toast["type"], message: string, sub?: string) => {
    const id = ++toastIdRef.current;
    setToasts((prev) => [...prev.slice(-4), { id, type, message, sub }]);
    setTimeout(() => setToasts((prev) => prev.filter((t) => t.id !== id)), 5000);
  }, []);

  // Load tokens from localStorage
  useEffect(() => {
    const c = getLastTournamentCode();
    const t = c ? getMemberToken(c) : null;
    const a = c ? getAdminToken(c)  : null;
    const m = c ? getMemberId(c)    : null;
    setCode(c);
    setToken(t);
    setAdminToken(a);
    setMyMemberId(m);
    adminTokenRef.current = a;
  }, []);

  const fetchData = useCallback(async (silent = false) => {
    if (!code || !token) return;
    if (fetchingRef.current) { pendingFetchRef.current = true; return; }
    fetchingRef.current = true;

    if (!silent) setLoading(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/market`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (!res.ok) { setError("Error al cargar el mercado."); return; }
      const d: MarketState = await res.json();

      // ── Toast diff against previous snapshot (stored in ref, never state) ──
      const prev = prevDataRef.current;
      if (prev && d.status === "active") {
        const myId = d.myStatus.memberId;

        // My turn just became active
        if (d.isMyTurn && !prev.isMyTurn) {
          pushToast("turn", "¡Es tu turno!", "Compra, ofrece o pasa el turno");
        }

        // New activity entry (transfer, rejection, skip…)
        const prevNewestId = prev.recentTransfers[0]?.id;
        const newNewestId  = d.recentTransfers[0]?.id;
        if (newNewestId && newNewestId !== prevNewestId) {
          const newest = d.recentTransfers[0];
          const myDisplayName = d.allMembers.find(m => m.id === myId)?.displayName;

          if (newest.transferType === "rejected") {
            // Only notify the two parties involved
            if (newest.buyerName === myDisplayName) {
              pushToast("warning", `Oferta rechazada`, `${newest.sellerName} rechazó tu oferta por ${newest.playerName}`);
            } else if (newest.sellerName === myDisplayName) {
              pushToast("info", `Oferta rechazada`, `Rechazaste la oferta de ${newest.buyerName} por ${newest.playerName}`);
            }
          } else if (newest.transferType === "skip") {
            // No toast for skips — not relevant info for others
          } else {
            // clause or accepted offer
            if (newest.buyerName === myDisplayName) {
              pushToast("success", `Compraste a ${newest.playerName}`, fmt(newest.amount));
            } else if (newest.sellerTeamName === d.myStatus.myTeamName) {
              pushToast("warning", `Perdiste a ${newest.playerName}`, `${fmt(newest.amount)} recibidos`);
            } else {
              pushToast("info", `Transferencia: ${newest.playerName}`, `${newest.buyerName} ← ${newest.sellerTeamName}`);
            }
          }
        }

        // New incoming offer
        const prevOfferIds = new Set(prev.incomingOffers.map(o => o.id));
        const newOffer = d.incomingOffers.find(o => !prevOfferIds.has(o.id));
        if (newOffer) {
          pushToast("warning", `Oferta por ${newOffer.playerName}`, `${newOffer.buyerName} ofrece ${fmt(newOffer.amount)}`);
        }
      }

      prevDataRef.current = d;
      setData(d);
      setError("");

      if (code) saveTournamentStatus(code, "market");
      if (code && d.myStatus?.memberId) {
        setMyMemberId(d.myStatus.memberId);
        saveMemberId(code, d.myStatus.memberId);
      }

      // Store session id so the realtime channel can subscribe
      if (d.session?.id) sessionIdRef.current = d.session.id;

      // Check icon auction status
      let auctionActive = false;
      const authToken = token ?? adminTokenRef.current;
      if (d.session?.id && authToken) {
        try {
          const iaRes = await fetch(`/api/tournaments/${code}/market/icon-auction`, {
            headers: { Authorization: `Bearer ${authToken}` },
          });
          if (iaRes.ok) {
            const ia = await iaRes.json();
            const phase = ia?.auction?.phase ?? null;
            const done = phase === "finished" || phase === "skipped";
            setRoundAuctionDone(done);
            if (phase && phase !== "finished" && phase !== "skipped") {
              auctionActive = true;
              setShowIconAuction(true);
              setModal(null);
            }
          }
        } catch { /* icon auction check failed, non-blocking */ }
      }

      if (!auctionActive) {
        if (d.session?.allRoundDone && (d.status === "active" || d.status === "finished")) {
          setShowSummary((prev) => {
            if (!prev) setModal("round_end");
            return prev;
          });
          setRoundAuctionDone(false);
        } else {
          setShowSummary(false);
          setModal((prev) => prev === "round_end" ? null : prev);
        }
      }
    } catch { setError("Error de conexión."); }
    finally {
      fetchingRef.current = false;
      setLoading(false);
      if (pendingFetchRef.current) {
        pendingFetchRef.current = false;
        fetchData(true);
      }
    }
  }, [code, token, pushToast]);

  // ── Realtime subscription ──────────────────────────────────────────────────
  useEffect(() => {
    if (!code || !token) return;

    const supabase = getBrowserClient();
    const setupChannel = (sessionId: string) => {
      if (channelRef.current) supabase.removeChannel(channelRef.current);

      const onDbChange = () => fetchData(true);

      channelRef.current = supabase
        .channel(`market:${sessionId}`)
        .on("postgres_changes", { event: "*",      schema: "public", table: "market_turns",     filter: `session_id=eq.${sessionId}` }, onDbChange)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "market_transfers", filter: `session_id=eq.${sessionId}` }, onDbChange)
        .on("postgres_changes", { event: "*",      schema: "public", table: "market_offers",    filter: `session_id=eq.${sessionId}` }, onDbChange)
        .on("postgres_changes", { event: "UPDATE", schema: "public", table: "market_sessions",  filter: `id=eq.${sessionId}`         }, onDbChange)
        .on("postgres_changes", { event: "INSERT", schema: "public", table: "icon_auctions",    filter: `session_id=eq.${sessionId}` }, onDbChange)
        .on("postgres_changes", { event: "UPDATE", schema: "public", table: "icon_auctions",    filter: `session_id=eq.${sessionId}` }, onDbChange)
        .subscribe();
    };

    // Initial load → then set up realtime once sessionId is known
    fetchData(false).then(() => {
      if (sessionIdRef.current) setupChannel(sessionIdRef.current);
    });

    return () => {
      if (channelRef.current) {
        supabase.removeChannel(channelRef.current);
        channelRef.current = null;
      }
    };
  // fetchData is stable (useCallback with [code, token, pushToast])
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [code, token]);

  // ── Actions ───────────────────────────────────────────────────────────────
  const doClause = async () => {
    if (!selectedPlayer || !code || !token) return;
    setActionLoading(true);
    setActionMsg("");
    const res = await fetch(`/api/tournaments/${code}/market/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ type: "clause", playerId: selectedPlayer.playerId }),
    });
    const d = await res.json();
    if (!res.ok) {
      setActionMsg(d.error ?? "Error al ejecutar la acción.");
      setActionLoading(false);
      if (res.status === 409) fetchData(true); // session expired — refresh
      return;
    }
    setModal(null);
    setSelectedPlayer(null);
    setActionLoading(false);
    // Double-fetch: immediate + delayed to ensure team_players propagation
    fetchData(true);
    setTimeout(() => fetchData(true), 1200);
  };

  const doOffer = async () => {
    if (!selectedPlayer || !code || !token) return;
    const amount = parseInt(offerAmount.replace(/\D/g, "")) * 1_000_000;
    if (!amount || amount <= 0) { setActionMsg("Ingresa un monto válido."); return; }
    setActionLoading(true);
    const res = await fetch(`/api/tournaments/${code}/market/offer`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ playerId: selectedPlayer.playerId, amount }),
    });
    const d = await res.json();
    if (!res.ok) { setActionMsg(d.error); setActionLoading(false); return; }
    setModal(null);
    setOfferAmount("");
    fetchData(true);
    setActionLoading(false);
  };

  const doSkip = async () => {
    if (!code || !token) return;
    setActionLoading(true);
    const res = await fetch(`/api/tournaments/${code}/market/action`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ type: "skip" }),
    });
    if (!res.ok) {
      const d = await res.json().catch(() => ({}));
      setActionMsg(d.error ?? "Error al pasar turno.");
      setActionLoading(false);
      fetchData(true);
      return;
    }
    setModal(null);
    fetchData(true);
    setActionLoading(false);
  };

  const doNextRound = async () => {
    if (!code || !adminToken) return;
    setActionLoading(true);
    await fetch(`/api/tournaments/${code}/market/next-round`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${adminToken}` },
    });
    setModal(null);
    fetchData(true);
    setActionLoading(false);
  };

  const [respondingOfferId, setRespondingOfferId] = useState<string | null>(null);

  const respondOffer = async (offerId: string, action: "accept" | "reject") => {
    if (!code || !token || respondingOfferId) return;
    setRespondingOfferId(offerId);
    try {
      await fetch(`/api/tournaments/${code}/market/offer/${offerId}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
        body: JSON.stringify({ action }),
      });
      setModal(null);
      fetchData(true);
    } finally {
      setRespondingOfferId(null);
    }
  };

  // ── Guard states ──────────────────────────────────────────────────────────
  if (!code || !token) {
    return (
      <div className="min-h-screen flex items-center justify-center p-8">
        <EmptyCard icon="🔒" title="Sin sesión" sub="Únete a un torneo para acceder al mercado." />
      </div>
    );
  }

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="flex flex-col items-center gap-3">
        <div className="w-10 h-10 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
        <p className="text-[#9CA3AF] text-sm">Cargando mercado…</p>
      </div>
    </div>
  );

  if (error) return (
    <div className="min-h-screen flex items-center justify-center p-8">
      <EmptyCard icon="⚠️" title="Error" sub={error} />
    </div>
  );

  // Market not started
  if (!data || data.status === "pending") {
    return <MarketPending code={code} adminToken={adminToken} onStarted={() => fetchData()} />;
  }

  // Market finished — show summary after round_end modal is acknowledged
  if (data.status === "finished" && showSummary) {
    return (
      <MarketFinished
        data={data}
        code={code}
        adminToken={adminToken}
        onReset={() => { setShowSummary(false); setData(null); setLoading(true); fetchData(); }}
      />
    );
  }

  // Filter players
  const positions = ["ALL", "GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LW", "RW", "ST", "CF"];
  const uniqueTeams = ["ALL", ...Array.from(new Set(data.availablePlayers.map((p) => p.teamName))).sort()];
  const filtered = data.availablePlayers.filter((p) => {
    const matchPos  = posFilter  === "ALL" || p.position === posFilter;
    const matchTeam = teamFilter === "ALL" || p.teamName === teamFilter;
    const matchSearch = !searchQ || p.playerName.toLowerCase().includes(searchQ.toLowerCase()) ||
      p.teamName.toLowerCase().includes(searchQ.toLowerCase()) ||
      p.ownerName.toLowerCase().includes(searchQ.toLowerCase());
    return matchPos && matchTeam && matchSearch;
  });

  const isAdmin = !!adminToken;

  return (
    <div className="flex flex-col h-full">
      {/* ── Header ── */}
      <div className={`shrink-0 px-6 pt-6 pb-4 transition-all duration-500 ${
        data.isMyTurn ? "bg-[#8B5CF6]/5 border-b border-[#8B5CF6]/20" : "border-b border-white/5"
      }`}>
        <div className="flex items-start justify-between gap-4 flex-wrap">
          <div className="flex items-center gap-4">
            {/* Round badge */}
            <div className="bg-[#131722] border border-white/8 rounded-2xl px-4 py-2.5 text-center shrink-0">
              <p className="text-[#9CA3AF] text-[9px] uppercase tracking-widest">Ronda</p>
              <p className="text-[#F3F4F6] text-lg font-bold leading-tight">
                {data.session?.currentRound}/{data.session?.totalRounds}
              </p>
            </div>
            <div>
              <div className="flex items-center gap-2">
                {data.isMyTurn
                  ? <span className="inline-flex items-center gap-1.5 text-[#8B5CF6] text-xs font-semibold px-2.5 py-1 rounded-full bg-[#8B5CF6]/10 border border-[#8B5CF6]/25">
                      <span className="w-1.5 h-1.5 rounded-full bg-[#8B5CF6] animate-pulse" />
                      ¡Es tu turno!
                    </span>
                  : data.currentTurn
                    ? <span className="text-[#9CA3AF] text-sm">
                        Turno de <span className="text-[#F3F4F6] font-semibold">{data.currentTurn.memberName}</span>
                      </span>
                    : <span className="text-[#9CA3AF] text-sm">Esperando siguiente ronda…</span>
                }
              </div>
              {data.isMyTurn && (
                <p className="text-[#9CA3AF] text-xs mt-0.5">
                  {data.myStatus.hasPendingOffer
                    ? "Esperando respuesta a tu oferta…"
                    : "Compra una cláusula, haz una oferta o pasa el turno"}
                </p>
              )}
            </div>
          </div>

          {/* Actions */}
          <div className="flex items-center gap-2">
            {/* Realtime indicator */}
            <div className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-xl bg-[#22C55E]/8 border border-[#22C55E]/20">
              <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E] animate-pulse" />
              <span className="text-[#22C55E] text-[10px] font-semibold">En vivo</span>
            </div>
            {data.myStatus.hasPendingOffer && (
              <div className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-[#F59E0B]/10 border border-[#F59E0B]/20">
                <svg className="animate-pulse w-3 h-3 text-[#F59E0B]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
                </svg>
                <span className="text-[#F59E0B] text-xs font-medium">Oferta enviada</span>
              </div>
            )}
            {data.incomingOffers.length > 0 && (
              <button onClick={() => setModal("offers")}
                className="relative flex items-center gap-2 px-3 py-2 rounded-xl bg-[#F59E0B]/10 border border-[#F59E0B]/25 text-[#F59E0B] text-xs font-medium hover:bg-[#F59E0B]/15 transition-colors cursor-pointer">
                <BellIcon />
                {data.incomingOffers.length} oferta{data.incomingOffers.length > 1 ? "s" : ""}
              </button>
            )}
            {data.isMyTurn && !data.myStatus.hasPendingOffer && (
              <button onClick={doSkip} disabled={actionLoading}
                className="px-4 py-2 rounded-xl border border-white/10 text-[#9CA3AF] hover:text-[#F3F4F6] hover:border-white/20 text-xs font-medium transition-all cursor-pointer disabled:opacity-40">
                Pasar turno
              </button>
            )}
          </div>
        </div>

        {/* Turn order strip */}
        <div className="flex items-center gap-2 mt-4 overflow-x-auto pb-1">
          {data.turns.map((t) => (
            <TurnChip key={t.id} turn={t} isMe={t.memberId === data.myStatus.memberId} />
          ))}
        </div>
      </div>

      {/* ── Body ── */}
      <div className="flex-1 flex gap-0 min-h-0 overflow-hidden">

        {/* Left: Player marketplace */}
        <div className="flex-1 flex flex-col min-h-0 border-r border-white/5">
          {/* Filters */}
          <div className="shrink-0 px-6 py-3 flex flex-col gap-2.5 border-b border-white/5">
            {/* Row 1: search + position pills */}
            <div className="flex items-center gap-3">
              <div className="relative flex-1 max-w-xs">
                <svg className="absolute left-3 top-1/2 -translate-y-1/2 text-[#9CA3AF]" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/>
                </svg>
                <input
                  value={searchQ}
                  onChange={(e) => setSearchQ(e.target.value)}
                  placeholder="Buscar jugador, equipo o dueño…"
                  className="w-full bg-[#131722] border border-white/8 rounded-xl pl-8 pr-3 py-2 text-xs text-[#F3F4F6] placeholder:text-[#9CA3AF]/50 focus:outline-none focus:border-[#8B5CF6]/50"
                />
              </div>
              <div className="flex items-center gap-1 overflow-x-auto">
                {positions.map((pos) => (
                  <button key={pos} onClick={() => setPosFilter(pos)}
                    className={`px-2.5 py-1 rounded-lg text-[10px] font-semibold shrink-0 transition-colors cursor-pointer ${
                      posFilter === pos
                        ? "bg-[#8B5CF6] text-white"
                        : "bg-[#131722] text-[#9CA3AF] hover:bg-[#1A1F2E] border border-white/6"
                    }`}>
                    {pos}
                  </button>
                ))}
              </div>
            </div>
            {/* Row 2: team filter */}
            <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5">
              <span className="text-[#9CA3AF] text-[10px] font-semibold uppercase tracking-wider shrink-0 mr-1">Equipo</span>
              {uniqueTeams.map((team) => (
                <button key={team} onClick={() => setTeamFilter(team)}
                  className={`px-2.5 py-1 rounded-lg text-[10px] font-semibold shrink-0 transition-colors cursor-pointer whitespace-nowrap ${
                    teamFilter === team
                      ? "bg-[#8B5CF6]/20 text-[#8B5CF6] border border-[#8B5CF6]/40"
                      : "bg-[#131722] text-[#9CA3AF] hover:bg-[#1A1F2E] border border-white/6"
                  }`}>
                  {team === "ALL" ? "Todos" : team}
                </button>
              ))}
            </div>
          </div>

          {/* Grid */}
          <div className="flex-1 overflow-y-auto px-6 py-4">
            {filtered.length === 0 ? (
              <div className="flex items-center justify-center h-40">
                <p className="text-[#9CA3AF]/40 text-sm">No hay jugadores disponibles.</p>
              </div>
            ) : (
              <div className="grid grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4 gap-3">
                {filtered.map((p) => (
                  <PlayerMarketCard
                    key={p.playerId}
                    player={p}
                    canAct={data.isMyTurn && data.myStatus.purchasesUsed < 3 && !data.myStatus.hasPendingOffer}
                    onClause={() => { setSelectedPlayer(p); setModal("clause"); setActionMsg(""); }}
                    onOffer={() => { setSelectedPlayer(p); setModal("offer"); setActionMsg(""); setOfferAmount(""); }}
                  />
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Right: My status panel */}
        <div className="w-72 shrink-0 flex flex-col gap-4 p-5 overflow-y-auto">
          {/* Budget card */}
          <div className="bg-[#131722] rounded-2xl border border-white/6 p-4">
            <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-3">Mi presupuesto</p>
            <p className="text-[#22C55E] text-2xl font-bold mb-1">
              <RollingNumber value={data.myStatus.budget} format={fmt} />
            </p>
            <div className="h-1.5 rounded-full bg-white/5 mb-3">
              <div className="h-full rounded-full bg-[#22C55E]"
                style={{ width: `${Math.min(100, (data.myStatus.budget / 400_000_000) * 100)}%` }} />
            </div>
            <div className="flex items-center justify-between text-xs">
              <span className="text-[#9CA3AF]">Compras</span>
              <div className="flex gap-1">
                {[0,1,2].map((i) => (
                  <div key={i} className={`w-2.5 h-2.5 rounded-full border ${
                    i < data.myStatus.purchasesUsed
                      ? "bg-[#8B5CF6] border-[#8B5CF6]"
                      : "bg-transparent border-white/20"
                  }`} />
                ))}
              </div>
              <span className="text-[#9CA3AF]">{data.myStatus.purchasesUsed}/3</span>
            </div>
          </div>

          {/* Clause protection */}
          <div className={`rounded-2xl border p-4 ${
            data.myStatus.teamClauseProtected
              ? "bg-[#3B82F6]/8 border-[#3B82F6]/25"
              : "bg-[#131722] border-white/6"
          }`}>
            <div className="flex items-center gap-2">
              {data.myStatus.teamClauseProtected
                ? <ShieldIcon filled />
                : <ShieldIcon />
              }
              <div>
                <p className="text-[#F3F4F6] text-xs font-semibold">
                  {data.myStatus.teamClauseProtected ? "Equipo protegido" : "Sin protección"}
                </p>
                <p className="text-[#9CA3AF] text-[10px] mt-0.5">
                  {data.myStatus.teamClauseProtected
                    ? "No pueden robarte jugadores por cláusula"
                    : "Tu equipo puede perder 1 jugador por cláusula"}
                </p>
              </div>
            </div>
          </div>

          {/* Participants */}
          <div className="bg-[#131722] rounded-2xl border border-white/6 p-4">
            <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-3">Participantes</p>
            <div className="flex flex-col gap-3">
              {data.allMembers.map((m) => {
                const isMe = m.id === data.myStatus.memberId;
                return (
                  <div key={m.id} className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      {m.teamCrestUrl ? (
                        <img src={m.teamCrestUrl} alt={m.teamName ?? ""} className="w-6 h-6 object-contain shrink-0" />
                      ) : (
                        <div className={`w-6 h-6 rounded-full flex items-center justify-center shrink-0 ${
                          isMe ? "bg-[#8B5CF6]/20" : "bg-white/8"
                        }`}>
                          <span className={`text-[9px] font-bold ${isMe ? "text-[#8B5CF6]" : "text-[#9CA3AF]"}`}>
                            {m.displayName.slice(0, 1).toUpperCase()}
                          </span>
                        </div>
                      )}
                      <div className="min-w-0">
                        <p className={`text-xs font-semibold truncate leading-tight ${
                          isMe ? "text-[#8B5CF6]" : "text-[#F3F4F6]"
                        }`}>
                          {m.displayName}{isMe ? " (tú)" : ""}
                        </p>
                        {m.teamName && (
                          <p className="text-[#9CA3AF] text-[10px] truncate">{m.teamName}</p>
                        )}
                      </div>
                    </div>
                    <div className="text-right shrink-0">
                      <p className="text-[#22C55E] text-[10px] font-semibold">{fmt(m.budget)}</p>
                      <p className="text-[#9CA3AF] text-[9px]">{m.purchasesUsed}/3</p>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          {/* History moved to full-width bottom panel */}
        </div>
      </div>

      {/* ── Transfer History Panel ── */}
      {data.recentTransfers.length > 0 && (
        <div className="shrink-0 border-t border-white/5 bg-[#0D0F14]/60">
          <div className="px-6 py-4">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <div className="w-7 h-7 rounded-lg bg-[#8B5CF6]/15 border border-[#8B5CF6]/25 flex items-center justify-center">
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>
                  </svg>
                </div>
                <div>
                  <p className="text-[#F3F4F6] text-sm font-bold">Historial de transferencias</p>
                  <p className="text-[#9CA3AF] text-[10px]">{data.recentTransfers.length} movimiento{data.recentTransfers.length !== 1 ? "s" : ""} en este mercado</p>
                </div>
              </div>
            </div>
            <div className="flex gap-3 overflow-x-auto pb-2">
              {data.recentTransfers.map((t: any) => (
                <TransferHistoryCard key={t.id} transfer={t} />
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ── Toast notifications ── */}
      <div className="fixed bottom-6 right-6 z-[60] flex flex-col gap-2 pointer-events-none">
        <AnimatePresence mode="popLayout">
          {toasts.map((t) => (
            <motion.div
              key={t.id}
              layout
              initial={{ opacity: 0, x: 60, scale: 0.9 }}
              animate={{ opacity: 1, x: 0, scale: 1 }}
              exit={{ opacity: 0, x: 60, scale: 0.9 }}
              transition={{ duration: 0.25, ease: "easeOut" }}
              className={`flex items-start gap-3 px-4 py-3 rounded-2xl border shadow-2xl backdrop-blur-sm min-w-[240px] max-w-xs ${
                t.type === "turn"    ? "bg-[#8B5CF6]/90 border-[#8B5CF6] text-white" :
                t.type === "success" ? "bg-[#131722] border-[#22C55E]/50 text-[#F3F4F6]" :
                t.type === "warning" ? "bg-[#131722] border-[#F59E0B]/50 text-[#F3F4F6]" :
                                       "bg-[#131722] border-white/15 text-[#F3F4F6]"
              }`}>
              <div className={`w-2 h-2 rounded-full shrink-0 mt-1.5 ${
                t.type === "turn"    ? "bg-white animate-pulse" :
                t.type === "success" ? "bg-[#22C55E]" :
                t.type === "warning" ? "bg-[#F59E0B]" :
                                       "bg-[#8B5CF6]"
              }`} />
              <div className="min-w-0">
                <p className="text-sm font-semibold leading-tight">{t.message}</p>
                {t.sub && <p className={`text-xs mt-0.5 ${t.type === "turn" ? "text-white/70" : "text-[#9CA3AF]"}`}>{t.sub}</p>}
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>

      {/* ── Modals ── */}
      <AnimatePresence>
        {/* Clause confirmation */}
        {modal === "clause" && selectedPlayer && (
          <Modal onClose={() => setModal(null)}>
            <div className="flex flex-col gap-5">
              <div className="flex items-center gap-4">
                {/* Headshot */}
                <div className="w-16 h-16 rounded-2xl overflow-hidden shrink-0 bg-[#0D0F14] flex items-center justify-center"
                  style={{ border: `1.5px solid ${ovrColor(selectedPlayer.ovr).bg}44` }}>
                  {selectedPlayer.headshotUrl ? (
                    <img src={selectedPlayer.headshotUrl} alt={selectedPlayer.playerName}
                      className="w-full h-full object-contain object-bottom" />
                  ) : (
                    <span className="font-black text-lg" style={{ color: ovrColor(selectedPlayer.ovr).bg }}>
                      {selectedPlayer.ovr}
                    </span>
                  )}
                </div>
                <div>
                  <p className="text-[#9CA3AF] text-xs uppercase tracking-widest mb-1">Pagar cláusula</p>
                  <h2 className="text-[#F3F4F6] text-xl font-bold leading-tight">{selectedPlayer.playerName}</h2>
                  <p className="text-[#9CA3AF] text-sm">{selectedPlayer.teamName} · {selectedPlayer.ownerName}</p>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <StatBox label="OVR" value={selectedPlayer.ovr.toString()} />
                <StatBox label="Cláusula" value={fmt(selectedPlayer.clause)} highlight />
                <StatBox label="Tu presupuesto" value={fmt(data.myStatus.budget)} />
                <StatBox label="Presupuesto restante" value={fmt(data.myStatus.budget - selectedPlayer.clause)} />
              </div>
              {selectedPlayer.clauseProtected && (
                <div className="flex items-center gap-2 bg-[#EF4444]/10 border border-[#EF4444]/20 rounded-xl px-3 py-2.5">
                  <ShieldIcon />
                  <span className="text-[#EF4444] text-xs font-medium">Este equipo ya está protegido. No puedes pagar la cláusula.</span>
                </div>
              )}
              {data.myStatus.budget < selectedPlayer.clause && (
                <div className="bg-[#EF4444]/10 border border-[#EF4444]/20 rounded-xl px-3 py-2.5">
                  <span className="text-[#EF4444] text-xs font-medium">Presupuesto insuficiente.</span>
                </div>
              )}
              {actionMsg && <p className="text-[#EF4444] text-xs">{actionMsg}</p>}
              <div className="flex gap-3">
                <button onClick={() => setModal(null)}
                  className="flex-1 py-3 rounded-xl border border-white/10 text-[#9CA3AF] hover:text-[#F3F4F6] text-sm font-medium transition-colors cursor-pointer">
                  Cancelar
                </button>
                <button onClick={doClause}
                  disabled={actionLoading || selectedPlayer.clauseProtected || data.myStatus.budget < selectedPlayer.clause}
                  className="flex-1 py-3 rounded-xl bg-[#EF4444] hover:bg-[#DC2626] text-white text-sm font-semibold transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed">
                  {actionLoading ? "Procesando…" : `Pagar ${fmt(selectedPlayer.clause)}`}
                </button>
              </div>
            </div>
          </Modal>
        )}

        {/* Offer modal */}
        {modal === "offer" && selectedPlayer && (
          <Modal onClose={() => setModal(null)}>
            <div className="flex flex-col gap-5">
              <div className="flex items-center gap-4">
                <div className="w-16 h-16 rounded-2xl overflow-hidden shrink-0 bg-[#0D0F14] flex items-center justify-center"
                  style={{ border: `1.5px solid ${ovrColor(selectedPlayer.ovr).bg}44` }}>
                  {selectedPlayer.headshotUrl ? (
                    <img src={selectedPlayer.headshotUrl} alt={selectedPlayer.playerName}
                      className="w-full h-full object-contain object-bottom" />
                  ) : (
                    <span className="font-black text-lg" style={{ color: ovrColor(selectedPlayer.ovr).bg }}>
                      {selectedPlayer.ovr}
                    </span>
                  )}
                </div>
                <div>
                  <p className="text-[#9CA3AF] text-xs uppercase tracking-widest mb-1">Hacer oferta</p>
                  <h2 className="text-[#F3F4F6] text-xl font-bold leading-tight">{selectedPlayer.playerName}</h2>
                  <p className="text-[#9CA3AF] text-sm">{selectedPlayer.teamName} · {selectedPlayer.ownerName}</p>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <StatBox label="OVR" value={selectedPlayer.ovr.toString()} />
                <StatBox label="Precio referencia" value={fmt(selectedPlayer.price)} />
                <StatBox label="Tu presupuesto" value={fmt(data.myStatus.budget)} />
              </div>
              <div>
                <label className="text-[#9CA3AF] text-xs font-medium block mb-2">Monto de la oferta (en millones €)</label>
                <div className="flex items-center gap-2">
                  <span className="text-[#9CA3AF] text-sm font-medium">€</span>
                  <input
                    type="number"
                    value={offerAmount}
                    onChange={(e) => setOfferAmount(e.target.value)}
                    placeholder="Ej: 45"
                    className="flex-1 bg-[#0D0F14] border border-white/10 rounded-xl px-3 py-2.5 text-[#F3F4F6] text-sm focus:outline-none focus:border-[#8B5CF6]/60 placeholder:text-[#9CA3AF]/40"
                  />
                  <span className="text-[#9CA3AF] text-sm font-medium">M</span>
                </div>
              </div>
              {actionMsg && <p className="text-[#EF4444] text-xs">{actionMsg}</p>}
              <div className="flex gap-3">
                <button onClick={() => setModal(null)}
                  className="flex-1 py-3 rounded-xl border border-white/10 text-[#9CA3AF] hover:text-[#F3F4F6] text-sm font-medium transition-colors cursor-pointer">
                  Cancelar
                </button>
                <button onClick={doOffer} disabled={actionLoading}
                  className="flex-1 py-3 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white text-sm font-semibold transition-colors cursor-pointer disabled:opacity-40">
                  {actionLoading ? "Enviando…" : "Enviar oferta"}
                </button>
              </div>
            </div>
          </Modal>
        )}

        {/* Incoming offers */}
        {modal === "offers" && (
          <Modal onClose={() => setModal(null)}>
            <div className="flex flex-col gap-4">
              <div>
                <p className="text-[#F3F4F6] font-bold text-lg">Ofertas recibidas</p>
                <p className="text-[#9CA3AF] text-xs mt-0.5">Puedes aceptar o rechazar en cualquier momento</p>
              </div>
              {data.incomingOffers.length === 0
                ? <p className="text-[#9CA3AF] text-sm">No tienes ofertas pendientes.</p>
                : data.incomingOffers.map((o) => (
                  <div key={o.id} className="bg-[#0D0F14] rounded-2xl p-4 flex items-center gap-4">
                    {/* Headshot or OVR badge */}
                    <div className="w-14 h-14 rounded-xl overflow-hidden shrink-0 bg-[#131722] flex items-center justify-center"
                      style={{ border: `1.5px solid ${o.playerOvr ? ovrColor(o.playerOvr).bg : "#9CA3AF"}33` }}>
                      {o.playerHeadshot ? (
                        <img src={o.playerHeadshot} alt={o.playerName}
                          className="w-full h-full object-contain object-bottom" />
                      ) : o.playerOvr ? (
                        <span className="font-black text-base" style={{ color: ovrColor(o.playerOvr).bg }}>{o.playerOvr}</span>
                      ) : null}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-[#F3F4F6] text-sm font-semibold leading-tight">{o.playerName}</p>
                      <p className="text-[#9CA3AF] text-xs">{o.playerPosition} · oferta de <span className="text-[#F3F4F6] font-medium">{o.buyerName}</span></p>
                      <p className="text-[#22C55E] text-sm font-bold mt-0.5">{fmt(o.amount)}</p>
                    </div>
                    <div className="flex flex-col gap-1.5 shrink-0">
                      <button onClick={() => respondOffer(o.id, "accept")}
                        disabled={!!respondingOfferId}
                        className="px-3 py-1.5 rounded-lg bg-[#22C55E] text-white text-xs font-semibold hover:bg-[#16A34A] transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-1.5 min-w-[72px]">
                        {respondingOfferId === o.id ? (
                          <svg className="animate-spin w-3 h-3" viewBox="0 0 24 24" fill="none">
                            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/>
                          </svg>
                        ) : "Aceptar"}
                      </button>
                      <button onClick={() => respondOffer(o.id, "reject")}
                        disabled={!!respondingOfferId}
                        className="px-3 py-1.5 rounded-lg border border-[#EF4444]/30 text-[#EF4444] text-xs font-medium hover:bg-[#EF4444]/10 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-1.5 min-w-[72px]">
                        {respondingOfferId === o.id ? (
                          <svg className="animate-spin w-3 h-3" viewBox="0 0 24 24" fill="none">
                            <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/>
                            <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/>
                          </svg>
                        ) : "Rechazar"}
                      </button>
                    </div>
                  </div>
                ))
              }
            </div>
          </Modal>
        )}

        {/* Round end */}
        {modal === "round_end" && data.session && (
          <Modal onClose={() => { setModal(null); if (data.status === "finished") setShowSummary(true); }}>
            <div className="flex flex-col items-center gap-5 text-center">
              <div className="w-16 h-16 rounded-2xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/25 flex items-center justify-center">
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z"/>
                </svg>
              </div>
              <div>
                <h2 className="text-[#F3F4F6] text-2xl font-bold">Fin de Ronda {data.session.currentRound}</h2>
                <p className="text-[#9CA3AF] text-sm mt-1">
                  {data.session.currentRound < data.session.totalRounds
                    ? `Quedan ${data.session.totalRounds - data.session.currentRound} rondas más.`
                    : "¡Mercado completado!"}
                </p>
              </div>
              <div className="w-full bg-[#0D0F14] rounded-xl p-4 text-left">
                <p className="text-[#9CA3AF] text-xs uppercase tracking-wider mb-2">Transferencias en esta ronda</p>
                <p className="text-[#F3F4F6] text-sm font-semibold">
                  {data.recentTransfers.filter((t: any) => t.transferType !== "skip").length} transacciones
                </p>
              </div>
              {isAdmin && (
                <div className="w-full flex flex-col gap-3">
                  <IconAuctionInitiateButton
                    code={code}
                    adminToken={adminToken!}
                    currentRound={data.session.currentRound}
                    auctionDone={roundAuctionDone}
                    onStarted={() => { setShowIconAuction(true); setModal(null); }}
                  />
                  {data.session.currentRound < data.session.totalRounds ? (
                    <button onClick={doNextRound} disabled={actionLoading}
                      className="w-full py-3.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white font-semibold text-sm transition-colors cursor-pointer disabled:opacity-40">
                      {actionLoading ? "Iniciando…" : `Iniciar Ronda ${data.session.currentRound + 1}`}
                    </button>
                  ) : (
                    <button onClick={() => { setShowSummary(true); setModal(null); }}
                      className="w-full py-3.5 rounded-xl bg-[#22C55E] hover:bg-[#16A34A] text-white font-semibold text-sm transition-colors cursor-pointer">
                      Ver Resumen del Mercado
                    </button>
                  )}
                </div>
              )}
              {!isAdmin && (
                <p className="text-[#9CA3AF] text-xs">
                  {data.session.currentRound < data.session.totalRounds
                    ? "Esperando que el administrador inicie la siguiente ronda."
                    : "Esperando que el administrador cierre el mercado."}
                </p>
              )}
            </div>
          </Modal>
        )}
      </AnimatePresence>

      {/* Icon Auction full-screen overlay */}
      {showIconAuction && data?.session?.id && (
        <IconAuction
          code={code}
          token={token}
          adminToken={adminToken}
          myMemberId={myMemberId ?? ""}
          sessionId={data.session.id}
          currentRound={data.session.currentRound}
          onFinished={() => {
            setShowIconAuction(false);
            setRoundAuctionDone(true);
            fetchData(true);
          }}
        />
      )}
    </div>
  );
}

// ── Sub-components ─────────────────────────────────────────────────────────────

function PlayerMarketCard({ player, canAct, onClause, onOffer }: {
  player: PlayerCard;
  canAct: boolean;
  onClause: () => void;
  onOffer: () => void;
}) {
  const col = ovrColor(player.ovr);
  const [imgError, setImgError] = useState(false);

  return (
    <div className={`bg-[#131722] rounded-2xl border transition-all duration-200 flex flex-col overflow-hidden ${
      player.clauseProtected
        ? "border-[#3B82F6]/30"
        : "border-white/6 hover:border-white/14 hover:bg-[#161C2A]"
    }`}>
      {/* Hero: headshot + OVR badge */}
      <div className="relative h-36 bg-[#0D0F14] overflow-hidden flex items-end justify-center">
        {/* Gradient background */}
        <div className="absolute inset-0"
          style={{ background: `radial-gradient(ellipse at 50% 0%, ${col.bg}18 0%, transparent 70%)` }} />

        {/* Headshot */}
        {player.headshotUrl && !imgError ? (
          <img
            src={player.headshotUrl}
            alt={player.playerName}
            onError={() => setImgError(true)}
            className="h-full object-contain object-bottom relative z-10 drop-shadow-lg"
          />
        ) : (
          <div className="w-16 h-16 rounded-full mb-4 flex items-center justify-center relative z-10"
            style={{ background: col.bg + "22", border: `2px solid ${col.bg}44` }}>
            <span className="text-xl font-black" style={{ color: col.bg }}>
              {player.playerName.charAt(0)}
            </span>
          </div>
        )}

        {/* OVR chip — top left */}
        <div className="absolute top-2.5 left-2.5 z-20 px-2 py-1 rounded-lg font-black text-xs leading-none"
          style={{ background: col.bg, color: col.text }}>
          {player.ovr}
        </div>

        {/* Position chip — top right */}
        <div className="absolute top-2.5 right-2.5 z-20 px-2 py-1 rounded-lg font-bold text-[10px] leading-none bg-black/50 text-[#F3F4F6] border border-white/10">
          {player.position}
        </div>

        {/* Shield — bottom right if protected */}
        {player.clauseProtected && (
          <div className="absolute bottom-2.5 right-2.5 z-20 flex items-center gap-1 px-1.5 py-1 rounded-lg bg-[#3B82F6]/20 border border-[#3B82F6]/40">
            <ShieldIcon size={9} filled />
            <span className="text-[#3B82F6] text-[9px] font-bold">Protegido</span>
          </div>
        )}
      </div>

      {/* Info */}
      <div className="p-3 flex flex-col gap-2.5 flex-1">
        {/* Name + team */}
        <div className="min-w-0">
          <p className="text-[#F3F4F6] text-sm font-bold leading-tight truncate">{player.playerName}</p>
          <p className="text-[#9CA3AF] text-[10px] truncate mt-0.5">{player.teamName}</p>
        </div>

        {/* Owner */}
        <div className="flex items-center gap-1.5">
          <div className="w-4 h-4 rounded-full bg-[#8B5CF6]/20 flex items-center justify-center shrink-0">
            <span className="text-[7px] font-bold text-[#8B5CF6]">{player.ownerName[0]}</span>
          </div>
          <span className="text-[#9CA3AF] text-[10px]">{player.ownerName}</span>
        </div>

        {/* Prices */}
        <div className="grid grid-cols-2 gap-1.5">
          <div className="bg-[#0D0F14] rounded-xl px-2.5 py-2">
            <p className="text-[#9CA3AF] text-[9px] uppercase tracking-wider mb-0.5">Precio</p>
            <p className="text-[#F3F4F6] text-xs font-bold">{fmt(player.price)}</p>
          </div>
          <div className="bg-[#0D0F14] rounded-xl px-2.5 py-2">
            <p className="text-[9px] uppercase tracking-wider mb-0.5"
              style={{ color: player.clauseProtected ? "#3B82F6" : "#EF4444" }}>
              Cláusula
            </p>
            <p className="text-xs font-bold"
              style={{ color: player.clauseProtected ? "#3B82F6" : "#F3F4F6" }}>
              {fmt(player.clause)}
            </p>
          </div>
        </div>

        {/* Actions */}
        <div className="flex gap-1.5 mt-auto">
          <button onClick={onOffer} disabled={!canAct}
            className="flex-1 py-2 rounded-xl border border-[#8B5CF6]/30 text-[#8B5CF6] text-[10px] font-semibold hover:bg-[#8B5CF6]/10 transition-colors cursor-pointer disabled:opacity-25 disabled:cursor-not-allowed">
            Ofrecer
          </button>
          <button onClick={onClause} disabled={!canAct || player.clauseProtected}
            className="flex-1 py-2 rounded-xl bg-[#EF4444]/10 border border-[#EF4444]/25 text-[#EF4444] text-[10px] font-semibold hover:bg-[#EF4444]/20 transition-colors cursor-pointer disabled:opacity-25 disabled:cursor-not-allowed">
            Cláusula
          </button>
        </div>
      </div>
    </div>
  );
}

function TransferHistoryCard({ transfer: t }: { transfer: any }) {
  const isClause   = t.transferType === "clause";
  const isRejected = t.transferType === "rejected";
  const isSkip     = t.transferType === "skip";

  const accentColor  = isRejected ? "#F59E0B" : isClause ? "#EF4444" : isSkip ? "#6B7280" : "#22C55E";
  const accentBg     = isRejected ? "#F59E0B15" : isClause ? "#EF444415" : isSkip ? "#6B728015" : "#22C55E15";
  const accentBorder = isRejected ? "#F59E0B30" : isClause ? "#EF444430" : isSkip ? "#6B728030" : "#22C55E30";

  const badgeLabel = isRejected ? "RECHAZADA" : isClause ? "CLÁUSULA" : isSkip ? "PASE" : "OFERTA";

  return (
    <div className="shrink-0 w-56 bg-[#131722] rounded-2xl border border-white/6 overflow-hidden flex flex-col">
      <div className="h-0.5" style={{ background: accentColor }} />

      <div className="p-4 flex flex-col gap-3 flex-1">
        {/* Badge + amount */}
        <div className="flex items-center justify-between">
          <span className="text-[10px] font-bold px-2 py-1 rounded-full"
            style={{ background: accentBg, border: `1px solid ${accentBorder}`, color: accentColor }}>
            {badgeLabel}
          </span>
          {!isSkip && (
            <span className="text-sm font-black" style={{ color: isRejected ? "#9CA3AF" : accentColor }}>
              {isRejected && <span className="line-through opacity-60">{fmt(t.amount)}</span>}
              {!isRejected && fmt(t.amount)}
            </span>
          )}
        </div>

        {/* Player name */}
        <div>
          <p className={`text-sm font-bold leading-tight truncate ${isRejected ? "text-[#6B7280] line-through" : "text-[#F3F4F6]"}`}>
            {t.playerName !== "—" ? t.playerName : <span className="text-[#4B5563] italic text-xs">Sin jugador</span>}
          </p>
        </div>

        {/* Flow rows */}
        <div className="flex flex-col gap-1.5 mt-auto">
          {isRejected ? (
            <>
              {/* Ofertante */}
              <div className="flex items-center gap-2">
                <div className="w-5 h-5 rounded-full bg-[#F59E0B]/15 flex items-center justify-center shrink-0">
                  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="#F59E0B" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/>
                  </svg>
                </div>
                <div className="min-w-0">
                  <p className="text-[#9CA3AF] text-[9px] uppercase tracking-wider leading-none">Ofertante</p>
                  <p className="text-[#9CA3AF] text-xs font-semibold truncate leading-tight mt-0.5">{t.buyerName}</p>
                </div>
              </div>
              {/* Rechazado por */}
              <div className="flex items-center gap-2">
                <div className="w-5 h-5 rounded-full bg-[#6B7280]/15 flex items-center justify-center shrink-0">
                  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12"/>
                  </svg>
                </div>
                <div className="min-w-0">
                  <p className="text-[#9CA3AF] text-[9px] uppercase tracking-wider leading-none">Rechazado por</p>
                  <p className="text-[#9CA3AF] text-xs font-semibold truncate leading-tight mt-0.5">{t.sellerName}</p>
                </div>
              </div>
            </>
          ) : isSkip ? (
            <div className="flex items-center gap-2">
              <div className="w-5 h-5 rounded-full bg-[#6B7280]/15 flex items-center justify-center shrink-0">
                <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="5 12 12 5 19 12"/><line x1="12" y1="19" x2="12" y2="5"/>
                </svg>
              </div>
              <div className="min-w-0">
                <p className="text-[#9CA3AF] text-[9px] uppercase tracking-wider leading-none">Turno pasado por</p>
                <p className="text-[#9CA3AF] text-xs font-semibold truncate leading-tight mt-0.5">{t.buyerName}</p>
              </div>
            </div>
          ) : (
            <>
              <div className="flex items-center gap-2">
                <div className="w-5 h-5 rounded-full bg-[#EF4444]/15 flex items-center justify-center shrink-0">
                  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/>
                  </svg>
                </div>
                <div className="min-w-0">
                  <p className="text-[#9CA3AF] text-[9px] uppercase tracking-wider leading-none">Vendedor</p>
                  <p className="text-[#F3F4F6] text-xs font-semibold truncate leading-tight mt-0.5">{t.sellerTeamName}</p>
                </div>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-5 h-5 rounded-full bg-[#22C55E]/15 flex items-center justify-center shrink-0">
                  <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12"/>
                  </svg>
                </div>
                <div className="min-w-0">
                  <p className="text-[#9CA3AF] text-[9px] uppercase tracking-wider leading-none">Comprador</p>
                  <p className="text-[#F3F4F6] text-xs font-semibold truncate leading-tight mt-0.5">{t.buyerName}</p>
                </div>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function TurnChip({ turn, isMe }: { turn: TurnInfo; isMe: boolean }) {
  const done = turn.status === "completed" || turn.status === "skipped";
  const color = turn.status === "active"
    ? "border-[#8B5CF6] bg-[#8B5CF6]/10 text-[#8B5CF6]"
    : done
    ? "border-white/5 bg-white/3 text-[#9CA3AF]/40"
    : "border-white/8 bg-[#131722] text-[#9CA3AF]";

  return (
    <div className={`flex items-center gap-2 px-3 py-2 rounded-xl border shrink-0 transition-all duration-300 ${color}`}>
      {turn.status === "active" && <span className="w-1.5 h-1.5 rounded-full bg-[#8B5CF6] animate-pulse shrink-0" />}
      {turn.status === "completed" && <CheckIcon size={10} />}
      {turn.status === "skipped" && <span className="text-[9px] opacity-60">—</span>}
      {turn.teamCrestUrl && (
        <img src={turn.teamCrestUrl} alt={turn.teamName ?? ""} className="w-4 h-4 object-contain shrink-0" />
      )}
      <div className={`flex flex-col leading-none ${done ? "opacity-50" : ""}`}>
        <span className={`text-xs font-medium whitespace-nowrap ${done ? "line-through" : ""}`}>
          {turn.memberName}{isMe ? " (tú)" : ""}
        </span>
        {turn.teamName && (
          <span className="text-[9px] mt-0.5 opacity-70 whitespace-nowrap">{turn.teamName}</span>
        )}
      </div>
    </div>
  );
}

function Modal({ children, onClose }: { children: React.ReactNode; onClose: () => void }) {
  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="fixed inset-0 z-50 flex items-center justify-center p-6 bg-black/60 backdrop-blur-sm"
      onClick={onClose}
    >
      <motion.div
        initial={{ opacity: 0, scale: 0.95, y: 12 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.95 }}
        transition={{ duration: 0.2 }}
        className="bg-[#131722] rounded-3xl border border-white/10 p-7 w-full max-w-md shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </motion.div>
    </motion.div>
  );
}

function MarketPending({ code, adminToken, onStarted }: { code: string; adminToken: string | null; onStarted: () => void }) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const start = async () => {
    if (!adminToken) return;
    setLoading(true);
    const res = await fetch(`/api/tournaments/${code}/market/start`, {
      method: "POST",
      headers: { Authorization: `Bearer ${adminToken}` },
    });
    const d = await res.json();
    if (!res.ok) { setError(d.error); setLoading(false); return; }
    onStarted();
    setLoading(false);
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-8">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="bg-[#131722] rounded-3xl border border-white/8 p-10 max-w-md w-full text-center flex flex-col items-center gap-6"
      >
        <div className="w-20 h-20 rounded-3xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center">
          <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <line x1="12" y1="1" x2="12" y2="23"/><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"/>
          </svg>
        </div>
        <div>
          <h1 className="text-[#F3F4F6] text-2xl font-bold mb-2">Mercado de Fichajes</h1>
          <p className="text-[#9CA3AF] text-sm leading-relaxed">
            El mercado aún no ha comenzado. {adminToken ? "Inicia el mercado cuando todos estén listos." : "El administrador debe iniciar el mercado."}
          </p>
        </div>
        {error && <p className="text-[#EF4444] text-sm">{error}</p>}
        {adminToken ? (
          <button onClick={start} disabled={loading}
            className="w-full py-4 rounded-2xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white font-bold text-sm shadow-lg shadow-[#8B5CF6]/25 transition-all cursor-pointer disabled:opacity-50">
            {loading ? "Iniciando…" : "Iniciar Mercado"}
          </button>
        ) : (
          <div className="flex items-center gap-2 text-[#9CA3AF] text-sm">
            <div className="w-2 h-2 rounded-full bg-[#F59E0B] animate-pulse" />
            Esperando al administrador…
          </div>
        )}
      </motion.div>
    </div>
  );
}

function MarketFinished({ data, code, adminToken, onReset }: {
  data: MarketState;
  code: string;
  adminToken: string | null;
  onReset: () => void;
}) {
  const [resetting, setResetting] = useState(false);
  const [closing, setClosing] = useState(false);
  const [actionError, setActionError] = useState("");

  const doReset = async () => {
    if (!adminToken) return;
    setResetting(true);
    setActionError("");
    const res = await fetch(`/api/tournaments/${code}/market/reset`, {
      method: "POST",
      headers: { Authorization: `Bearer ${adminToken}` },
    });
    if (!res.ok) {
      const d = await res.json();
      setActionError(d.error ?? "Error al reiniciar.");
      setResetting(false);
      return;
    }
    onReset();
  };

  const doClose = async () => {
    if (!adminToken) return;
    setClosing(true);
    setActionError("");
    const res = await fetch(`/api/tournaments/${code}/market/close`, {
      method: "POST",
      headers: { Authorization: `Bearer ${adminToken}` },
    });
    if (!res.ok) {
      const d = await res.json();
      setActionError(d.error ?? "Error al cerrar.");
      setClosing(false);
    }
  };

  const realTransfers = data.recentTransfers.filter(
    (t: any) => t.transferType === "clause" || t.transferType === "offer" || t.transferType === "icon_auction"
  );
  const totalSpent = realTransfers.reduce((s: number, t: any) => s + (t.amount ?? 0), 0);

  const transfersByMember: Record<string, { bought: any[]; sold: any[] }> = {};
  for (const m of data.allMembers) transfersByMember[m.id] = { bought: [], sold: [] };
  for (const t of realTransfers) {
    if (t.buyerId && transfersByMember[t.buyerId]) transfersByMember[t.buyerId].bought.push(t);
    if (t.sellerId && transfersByMember[t.sellerId]) transfersByMember[t.sellerId].sold.push(t);
  }

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      className="p-8 max-w-5xl mx-auto"
    >
      {/* Hero */}
      <div className="text-center mb-10">
        <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-[#22C55E]/10 border border-[#22C55E]/20 mb-4">
          <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="20 6 9 17 4 12"/>
          </svg>
        </div>
        <h1 className="text-[#F3F4F6] text-3xl font-bold tracking-tight mb-2">Mercado Completado</h1>
        <p className="text-[#9CA3AF] text-sm">
          {data.session?.totalRounds} rondas · {realTransfers.length} transferencias · {fmt(totalSpent)} en movimientos
        </p>
      </div>

      {/* Stats row */}
      <div className="grid grid-cols-3 gap-4 mb-8">
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 text-center">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Transferencias</p>
          <p className="text-[#F3F4F6] text-2xl font-bold">{realTransfers.length}</p>
        </div>
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 text-center">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Total movido</p>
          <p className="text-[#22C55E] text-2xl font-bold">{fmt(totalSpent)}</p>
        </div>
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 text-center">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Rondas jugadas</p>
          <p className="text-[#8B5CF6] text-2xl font-bold">{data.session?.totalRounds ?? 3}</p>
        </div>
      </div>

      {/* Per-member cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
        {data.allMembers.map((m) => {
          const tx = transfersByMember[m.id] ?? { bought: [], sold: [] };
          return (
            <div key={m.id} className="bg-[#131722] rounded-2xl border border-white/6 p-5 flex flex-col gap-3">
              <div className="flex items-center gap-3">
                {m.teamCrestUrl ? (
                  <img src={m.teamCrestUrl} alt={m.teamName ?? ""} className="w-8 h-8 object-contain shrink-0" />
                ) : (
                  <div className="w-8 h-8 rounded-full bg-[#8B5CF6]/15 flex items-center justify-center shrink-0">
                    <span className="text-[#8B5CF6] text-xs font-bold">{m.displayName.charAt(0).toUpperCase()}</span>
                  </div>
                )}
                <div className="min-w-0">
                  <p className="text-[#F3F4F6] text-sm font-semibold truncate">{m.displayName}</p>
                  {m.teamName && <p className="text-[#9CA3AF] text-[10px] truncate">{m.teamName}</p>}
                </div>
                <span className="ml-auto text-[#22C55E] text-sm font-bold shrink-0">{fmt(m.budget)}</span>
              </div>

              <div className="flex gap-4 text-xs">
                <div className="flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-[#22C55E]" />
                  <span className="text-[#9CA3AF]">{tx.bought.length} fichajes</span>
                </div>
                <div className="flex items-center gap-1.5">
                  <span className="w-2 h-2 rounded-full bg-[#EF4444]" />
                  <span className="text-[#9CA3AF]">{tx.sold.length} ventas</span>
                </div>
              </div>

              {tx.bought.length > 0 && (
                <div className="flex flex-col gap-1">
                  {tx.bought.map((t: any, i: number) => (
                    <div key={i} className="flex items-center justify-between text-[10px] bg-[#22C55E]/5 rounded-lg px-2 py-1.5">
                      <span className="text-[#F3F4F6] font-medium truncate">{t.playerName}</span>
                      <span className="text-[#22C55E] font-bold shrink-0 ml-2">{fmt(t.amount)}</span>
                    </div>
                  ))}
                </div>
              )}
              {tx.sold.length > 0 && (
                <div className="flex flex-col gap-1">
                  {tx.sold.map((t: any, i: number) => (
                    <div key={i} className="flex items-center justify-between text-[10px] bg-[#EF4444]/5 rounded-lg px-2 py-1.5">
                      <span className="text-[#F3F4F6] font-medium truncate">{t.playerName}</span>
                      <span className="text-[#EF4444] font-bold shrink-0 ml-2">{fmt(t.amount)}</span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* Transfer timeline */}
      {realTransfers.length > 0 && (
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-6 mb-8">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-4">Historial de transferencias</p>
          <div className="flex flex-col gap-2">
            {realTransfers.map((t: any, i: number) => (
              <div key={i} className="flex items-center gap-3 text-xs py-2 border-b border-white/3 last:border-0">
                <span className={`w-1.5 h-1.5 rounded-full shrink-0 ${
                  t.transferType === "clause" ? "bg-[#EF4444]" :
                  t.transferType === "icon_auction" ? "bg-[#F59E0B]" :
                  "bg-[#8B5CF6]"
                }`} />
                <span className="text-[#F3F4F6] font-medium flex-1 truncate">{t.playerName}</span>
                <span className="text-[#9CA3AF] shrink-0">
                  {t.buyerName} ← {t.sellerName}
                </span>
                <span className={`font-bold shrink-0 ${
                  t.transferType === "clause" ? "text-[#EF4444]" : "text-[#22C55E]"
                }`}>{fmt(t.amount)}</span>
                <span className="text-[#4B5563] text-[9px] uppercase shrink-0">
                  {t.transferType === "clause" ? "cláusula" : t.transferType === "icon_auction" ? "ícono" : "oferta"}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Admin actions */}
      {adminToken && (
        <div className="flex flex-col items-center gap-3 max-w-md mx-auto">
          {actionError && <p className="text-[#EF4444] text-xs">{actionError}</p>}
          <button onClick={doClose} disabled={closing}
            className="w-full py-3.5 rounded-2xl bg-[#22C55E] hover:bg-[#16A34A] text-white font-semibold text-sm transition-colors cursor-pointer disabled:opacity-40">
            {closing ? "Cerrando…" : "Cerrar Mercado y volver al Lobby"}
          </button>
          <button onClick={doReset} disabled={resetting}
            className="w-full flex items-center justify-center gap-2 py-2.5 rounded-2xl
              border border-[#F59E0B]/20 bg-transparent text-[#F59E0B]/60
              hover:bg-[#F59E0B]/8 hover:text-[#F59E0B]
              text-xs font-medium transition-all cursor-pointer disabled:opacity-40">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="1 4 1 10 7 10"/><path d="M3.51 15a9 9 0 1 0 .49-3.51"/>
            </svg>
            {resetting ? "Reiniciando…" : "Reiniciar Mercado (testing)"}
          </button>
        </div>
      )}
      {!adminToken && (
        <p className="text-center text-[#9CA3AF] text-sm">Esperando que el administrador cierre el mercado.</p>
      )}
    </motion.div>
  );
}

function StatBox({ label, value, highlight }: { label: string; value: string; highlight?: boolean }) {
  return (
    <div className="bg-[#0D0F14] rounded-xl px-3 py-2.5">
      <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mb-1">{label}</p>
      <p className={`text-sm font-bold ${highlight ? "text-[#EF4444]" : "text-[#F3F4F6]"}`}>{value}</p>
    </div>
  );
}

function EmptyCard({ icon, title, sub }: { icon: string; title: string; sub: string }) {
  return (
    <div className="bg-[#131722] rounded-2xl border border-white/6 p-10 max-w-sm w-full text-center">
      <p className="text-3xl mb-3">{icon}</p>
      <p className="text-[#F3F4F6] font-semibold">{title}</p>
      <p className="text-[#9CA3AF] text-sm mt-1">{sub}</p>
    </div>
  );
}

function ShieldIcon({ size = 14, filled = false }: { size?: number; filled?: boolean }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill={filled ? "#3B82F6" : "none"}
      stroke={filled ? "#3B82F6" : "#9CA3AF"} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
    </svg>
  );
}

function CheckIcon({ size = 12 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="20 6 9 17 4 12"/>
    </svg>
  );
}

function BellIcon() {
  return (
    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/>
    </svg>
  );
}
