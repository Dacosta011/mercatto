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

function timeAgo(input?: string | null) {
  if (!input) return "Hace unos segundos";
  const ts = new Date(input).getTime();
  if (Number.isNaN(ts)) return "Hace unos segundos";
  const delta = Math.max(0, Date.now() - ts);
  const minutes = Math.floor(delta / 60000);
  if (minutes < 1) return "Hace unos segundos";
  if (minutes < 60) return `Hace ${minutes} minuto${minutes > 1 ? "s" : ""}`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `Hace ${hours} hora${hours > 1 ? "s" : ""}`;
  const days = Math.floor(hours / 24);
  return `Hace ${days} día${days > 1 ? "s" : ""}`;
}

const FABRIZIO_IMG = "https://pbs.twimg.com/profile_images/1741753635158024192/j0m8Ucvv_400x400.jpg";

function pickRandom<T>(arr: T[], id: string): T {
  let hash = 0;
  for (let i = 0; i < id.length; i++) hash = ((hash << 5) - hash + id.charCodeAt(i)) | 0;
  return arr[Math.abs(hash) % arr.length];
}

function insiderCopy(transfer: any) {
  const id = transfer.id ?? "";
  const p = transfer.playerName;
  const b = transfer.buyerName;
  const s = transfer.sellerName;
  const st = transfer.sellerTeamName;
  const a = fmt(transfer.amount);

  if (transfer.transferType === "clause") {
    return pickRandom([
      { type: "🚨 BREAKING", headline: `${b} activa la cláusula de ${p} por ${a}. Here we go! ✅`, context: `${st} queda protegido por cláusula. Movimiento confirmado. 🔴🔵` },
      { type: "🚨 EXCLUSIVA", headline: `BOMBAZO. ${p} se va con ${b} por ${a}. Cláusula pagada. 💣`, context: `${st} no pudo retenerlo. Protección de cláusula activada para el equipo. ✅` },
      { type: "🚨 CONFIRMED", headline: `${p} a ${b} por ${a}, cláusula activada. Done deal. 🤝`, context: `${st} recibe el dinero de la cláusula. Here we go confirmed! ✅` },
    ], id);
  }

  if (transfer.transferType === "pending_offer") {
    return pickRandom([
      { type: "🔄 OFERTA ENVIADA", headline: `${b} presenta oferta formal de ${a} por ${p}. ⏳`, context: `${s} tiene la decisión. Negociaciones en curso... 🔜` },
      { type: "📋 NUEVA OFERTA", headline: `Oferta de ${a} de ${b} por ${p} está sobre la mesa. 📝`, context: `Pendiente de respuesta de ${s}. Mercatto en vivo. ⏳` },
      { type: "💰 OFERTA FORMAL", headline: `${b} quiere a ${p} y ofrece ${a}. Esperando respuesta. 🔔`, context: `${s} debe decidir. Todos los ojos puestos en este movimiento. 👀` },
    ], id);
  }

  if (transfer.transferType === "rejected") {
    return pickRandom([
      { type: "❌ OFERTA RECHAZADA", headline: `${s} dice NO a ${b} por ${p}. Oferta rechazada. ❌`, context: `La propuesta de ${a} no fue suficiente. El jugador se queda. 🔒` },
      { type: "🚫 RECHAZADA", headline: `Nada que hacer. ${s} rechaza la oferta de ${b} por ${p}. ❌`, context: `${a} no convenció. Sin acuerdo entre las partes. ⛔` },
      { type: "❌ NO DEAL", headline: `${s} no acepta ${a} por ${p}. Oferta de ${b} descartada.`, context: `Las negociaciones no prosperaron. El mercado sigue abierto. 🔄` },
    ], id);
  }

  if (transfer.transferType === "icon_auction") {
    return pickRandom([
      { type: "🌟 LEYENDA DE VUELTA", headline: `¡${p} SALE DEL RETIRO! 🔥 ${b} lo convence de volver. ${a} por la leyenda. Here we go! ✅`, context: `Increíble. Una leyenda regresa al fútbol. ${b} hace historia con este fichaje. 🏆👑` },
      { type: "👑 REGRESO LEGENDARIO", headline: `LOCURA TOTAL. ${p} deja la jubilación para jugar con ${b}. ${a} 💰🤯`, context: `Nadie lo esperaba. El retiro puede esperar cuando llama ${b}. Leyenda viva. ⚽🔥` },
      { type: "🔥 BOMBAZO HISTÓRICO", headline: `${p} vuelve a las canchas. ${b} paga ${a} por traer de vuelta a la leyenda. DONE DEAL! 🤝`, context: `Se colgó los botines... y los descolgó. El fútbol recupera a un grande. Welcome back! 🎉👏` },
    ], id);
  }

  if (transfer.transferType === "skip") {
    return pickRandom([
      { type: "⏭ TURNO PASADO", headline: `${b} decide pasar su turno. Sin movimientos. ⏭`, context: "Estrategia de espera. El mercado continúa. 🔄" },
      { type: "⏸ SIN MOVIMIENTO", headline: `${b} pasa. No hay fichaje en este turno. 🤔`, context: "A veces no hacer nada también es una decisión. El mercado sigue. ⏳" },
    ], id);
  }

  return pickRandom([
    { type: "✅ HERE WE GO", headline: `${b} y ${s} cierran a ${p} por ${a}. Here we go! ✅🤝`, context: `Negociación completada con éxito. Deal done. Confirmed. ✅` },
    { type: "🤝 DEAL DONE", headline: `${p} a ${b} por ${a}. Acuerdo total con ${s}. Done deal! 🔥`, context: `Fichaje confirmado. ${b} refuerza su plantilla. Here we go! ✅` },
    { type: "✅ FICHAJE OFICIAL", headline: `OFICIAL: ${p} fichado por ${b}. ${a} al equipo de ${s}. 💰`, context: `Todo cerrado. Documentos firmados. Welcome! 🎉` },
  ], id);
}

// ── Main Page ─────────────────────────────────────────────────────────────────

export default function MarketPage() {
  const [code,        setCode]        = useState<string | null>(null);
  const [token,       setToken]       = useState<string | null>(null);
  const [adminToken,  setAdminToken]  = useState<string | null>(null);
  const [data,        setData]        = useState<MarketState | null>(null);
  const [loading,     setLoading]     = useState(true);
  const [error,       setError]       = useState("");
  const [modal,       setModal]       = useState<"clause" | "offer" | "offers" | null>(null);
  const [selectedPlayer, setSelectedPlayer] = useState<PlayerCard | null>(null);
  const [offerAmount, setOfferAmount] = useState("");
  const [actionLoading, setActionLoading] = useState(false);
  const [actionMsg, setActionMsg] = useState("");
  const [posFilter,  setPosFilter]  = useState("TODOS");
  const [teamFilter, setTeamFilter] = useState("ALL");
  const [searchQ,    setSearchQ]    = useState("");
  const [showIconAuction, setShowIconAuction] = useState(false);
  const [roundAuctionDone, setRoundAuctionDone] = useState(false);
  const [myMemberId, setMyMemberId] = useState<string | null>(null);
  const [showSummary, setShowSummary] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [turnElapsed, setTurnElapsed] = useState(0);

  // Realtime
  const channelRef      = useRef<RealtimeChannel | null>(null);
  const sessionIdRef    = useRef<string | null>(null);
  const prevDataRef     = useRef<MarketState | null>(null);   // for toast diffing
  const fetchingRef     = useRef(false);                      // debounce concurrent fetches
  const pendingFetchRef = useRef(false);                      // queue fetch if one is in-flight
  const adminTokenRef   = useRef<string | null>(null);        // stable ref for fetchData
  const feedRef = useRef<HTMLDivElement | null>(null);

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
            if (newest.transferType === "clause") {
              pushToast("warning", "Cláusula activada", `${newest.playerName} por ${fmt(newest.amount)}`);
            } else if (newest.buyerName === myDisplayName) {
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

        if (d.session && prev.session && d.session.currentRound > prev.session.currentRound) {
          pushToast("info", "Nueva ronda iniciada", `Ronda ${d.session.currentRound}`);
        }

        if (d.session?.allRoundDone && !prev.session?.allRoundDone) {
          pushToast("turn", "Ronda finalizada", "El administrador decidirá el siguiente paso");
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
          if (d.status === "finished" && !adminTokenRef.current) {
            setShowSummary(true);
          }
          setRoundAuctionDone(false);
        } else {
          setShowSummary(false);
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
    if (!selectedPlayer || !code || !token || !data) return;
    const raw = parseInt(offerAmount.replace(/\D/g, ""));
    if (!raw || raw <= 0) { setActionMsg("Ingresa un monto válido (mayor a 0)."); return; }
    const amount = raw * 1_000_000;
    if (amount > data.myStatus.budget) { setActionMsg(`No tienes suficiente presupuesto. Tu presupuesto es ${fmt(data.myStatus.budget)}.`); return; }
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

  useEffect(() => {
    if (!data?.currentTurn?.id) return;
    setTurnElapsed(0);
  }, [data?.currentTurn?.id]);

  useEffect(() => {
    if (!data?.isMyTurn) return;
    const interval = setInterval(() => {
      setTurnElapsed((prev) => prev + 1);
    }, 1000);
    return () => clearInterval(interval);
  }, [data?.isMyTurn, data?.currentTurn?.id]);

  useEffect(() => {
    if (!data?.recentTransfers?.length || !feedRef.current) return;
    feedRef.current.scrollTo({ top: 0, behavior: "smooth" });
  }, [data?.recentTransfers?.[0]?.id]);

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

  // Market finished or admin reviewing summary before closing
  if (showSummary) {
    return (
      <MarketFinished
        data={data}
        code={code}
        adminToken={adminToken}
        onBack={data.status !== "finished" ? () => setShowSummary(false) : undefined}
      />
    );
  }

  // Filter players — use groups that match the Spanish position abbreviations from the database
  const POS_FILTERS: { label: string; positions: string[] }[] = [
    { label: "TODOS", positions: [] },
    { label: "POR",   positions: ["POR", "GK"] },
    { label: "DFC",   positions: ["DFC", "CB"] },
    { label: "LI",    positions: ["LI", "LB"] },
    { label: "LD",    positions: ["LD", "RB"] },
    { label: "MCD",   positions: ["MCD", "CDM"] },
    { label: "MC",    positions: ["MC", "CM"] },
    { label: "MCO",   positions: ["MCO", "CAM"] },
    { label: "EI",    positions: ["EI", "LW", "MI", "LM"] },
    { label: "ED",    positions: ["ED", "RW", "MD", "RM"] },
    { label: "DC",    positions: ["DC", "ST"] },
    { label: "SD",    positions: ["SD", "CF", "SS"] },
  ];
  const uniqueTeams = ["ALL", ...Array.from(new Set(data.availablePlayers.map((p) => p.teamName))).sort()];
  const activeFilterPositions = POS_FILTERS.find((f) => f.label === posFilter)?.positions ?? [];
  const filtered = data.availablePlayers.filter((p) => {
    const matchPos  = posFilter === "TODOS" || activeFilterPositions.includes(p.position.toUpperCase());
    const matchTeam = teamFilter === "ALL" || p.teamName === teamFilter;
    const matchSearch = !searchQ || p.playerName.toLowerCase().includes(searchQ.toLowerCase()) ||
      p.teamName.toLowerCase().includes(searchQ.toLowerCase()) ||
      p.ownerName.toLowerCase().includes(searchQ.toLowerCase());
    return matchPos && matchTeam && matchSearch;
  });

  const isAdmin = !!adminToken;
  const canAct = data.isMyTurn && data.myStatus.purchasesUsed < data.myStatus.maxPurchases && !data.myStatus.hasPendingOffer;
  const needsAttention = data.isMyTurn || data.incomingOffers.length > 0;
  const myMember = data.allMembers.find((m) => m.id === data.myStatus.memberId) ?? null;

  return (
    <div className="relative h-full overflow-hidden bg-[#0D0F14]">
      <div className="h-full min-h-0 px-4 md:px-6 pb-6 pt-4">
        <div className="h-full min-h-0 flex flex-col xl:flex-row gap-4">
          <aside
            className={`bg-[#131722] border border-white/6 rounded-3xl min-h-0 overflow-hidden transition-all duration-200 ease-out ${
              sidebarCollapsed ? "xl:w-[72px]" : "xl:w-[340px]"
            }`}
          >
            <div className="h-full flex flex-col">
              <div className="px-3 py-3 border-b border-white/6 flex items-center justify-between">
                <button
                  onClick={() => setSidebarCollapsed((v) => !v)}
                  className="w-9 h-9 rounded-xl border border-white/10 hover:bg-[#1A1F2E] transition-colors flex items-center justify-center cursor-pointer relative"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#F3F4F6" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="3" y1="6" x2="21" y2="6" /><line x1="3" y1="12" x2="21" y2="12" /><line x1="3" y1="18" x2="21" y2="18" />
                  </svg>
                  {needsAttention && <span className="absolute -top-1 -right-1 w-2.5 h-2.5 rounded-full bg-[#EF4444]" />}
                </button>
                {!sidebarCollapsed && (
                  <div className="flex items-center gap-2.5">
                    <img src={FABRIZIO_IMG} alt="Fabrizio Romano" className="w-8 h-8 rounded-full object-cover" />
                    <div>
                      <div className="flex items-center gap-1">
                        <p className="text-[#F3F4F6] text-sm font-semibold">Fabrizio Romano</p>
                        <span className="w-4 h-4 rounded-full bg-[#1D9BF0] text-white text-[9px] flex items-center justify-center font-bold">✓</span>
                      </div>
                      <p className="text-[#9CA3AF] text-xs">@FabrizioRomano</p>
                    </div>
                  </div>
                )}
              </div>

              {sidebarCollapsed ? (
                <div className="flex-1 flex flex-col items-center py-4 gap-3">
                  <img src={FABRIZIO_IMG} alt="FR" className="w-9 h-9 rounded-full object-cover" />
                  <div className="w-9 h-9 rounded-xl bg-[#1A1F2E] border border-white/8 flex items-center justify-center text-[#9CA3AF] text-xs">24</div>
                  <div className="w-9 h-9 rounded-xl bg-[#1A1F2E] border border-white/8 flex items-center justify-center text-[#9CA3AF] text-xs">{data.recentTransfers.length}</div>
                </div>
              ) : (
                <div ref={feedRef} className="flex-1 min-h-0 overflow-y-auto px-3 py-3 space-y-3">
                  {data.recentTransfers.map((t: any, idx: number) => {
                    const copy = insiderCopy(t);
                    return (
                      <motion.div
                        key={t.id}
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{ duration: 0.22, delay: idx < 3 ? idx * 0.03 : 0 }}
                        className={`rounded-2xl border bg-[#0D0F14] p-4 ${
                          t.transferType === "icon_auction" ? "border-[#F59E0B]/25" :
                          t.transferType === "pending_offer" ? "border-[#F59E0B]/20" :
                          t.transferType === "clause" ? "border-[#EF4444]/15" :
                          t.transferType === "rejected" ? "border-white/6" :
                          t.transferType === "skip" ? "border-white/4" :
                          "border-[#22C55E]/15"
                        }`}
                      >
                        <div className="flex items-start gap-3">
                          <img
                            src={FABRIZIO_IMG}
                            alt="Fabrizio Romano"
                            className="w-11 h-11 rounded-full object-cover shrink-0"
                          />
                          <div className="min-w-0 flex-1">
                            <div className="flex items-center gap-1.5 text-xs">
                              <span className="text-[#F3F4F6] font-semibold">Fabrizio Romano</span>
                              <span className="text-[#9CA3AF]">@FabrizioRomano</span>
                              <span className="w-4 h-4 rounded-full bg-[#1D9BF0] text-white text-[9px] flex items-center justify-center font-bold">✓</span>
                            </div>
                            <p className="mt-2 text-xs tracking-[0.15em] uppercase font-bold text-[#8B5CF6]">{copy.type}</p>
                            <p className="text-[#F3F4F6] text-base font-bold leading-snug mt-1">{copy.headline}</p>
                            <p className="text-[#9CA3AF] text-sm leading-snug mt-1.5">{copy.context}</p>
                            <div className="mt-3 flex items-center justify-between">
                              <span className="text-[#6B7280] text-xs">{timeAgo(t.createdAt)}</span>
                              <div className="flex items-center gap-2.5 text-[#6B7280] text-xs">
                                <span>♡ {12 + idx}</span>
                                <span>↻ {4 + (idx % 6)}</span>
                              </div>
                            </div>
                          </div>
                        </div>
                      </motion.div>
                    );
                  })}
                </div>
              )}
            </div>
          </aside>

          <section
            className={`flex-1 min-h-0 rounded-3xl border bg-[#131722] overflow-hidden ${
              data.isMyTurn ? "border-[#8B5CF6]/35 shadow-[0_0_0_1px_rgba(139,92,246,0.25),0_0_50px_rgba(139,92,246,0.12)]" : "border-white/6"
            }`}
          >
            <div className="h-full flex flex-col min-h-0">
              <div className="px-4 md:px-5 py-4 border-b border-white/6">
                <div className="flex items-center justify-between gap-3 flex-wrap">
                  <div className="flex items-center gap-3">
                    <div className="px-3 py-2 rounded-xl bg-[#0D0F14] border border-white/8 text-center">
                      <p className="text-[9px] text-[#9CA3AF] uppercase tracking-widest">Ronda</p>
                      <p className="text-[#F3F4F6] text-base font-semibold">{data.session?.currentRound}/{data.session?.totalRounds}</p>
                    </div>
                    {data.session?.allRoundDone ? (
                      <div className="flex items-center gap-2">
                        <div className="w-2 h-2 rounded-full bg-[#F59E0B] animate-pulse" />
                        <p className="text-[#F59E0B] text-sm font-semibold">Ronda finalizada</p>
                      </div>
                    ) : (
                      <div>
                        <p className="text-[#F3F4F6] text-sm font-semibold">
                          {data.currentTurn ? `Turno de ${data.currentTurn.memberName}` : "Esperando siguiente turno"}
                        </p>
                        <p className="text-[#9CA3AF] text-xs">Mercado en vivo. Decide con rapidez y estrategia.</p>
                      </div>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    {data.session?.allRoundDone && isAdmin && (
                      <>
                        <IconAuctionInitiateButton
                          code={code}
                          adminToken={adminToken!}
                          currentRound={data.session!.currentRound}
                          auctionDone={roundAuctionDone}
                          onStarted={() => { setShowIconAuction(true); }}
                        />
                        {data.session!.currentRound < data.session!.totalRounds ? (
                          <button onClick={doNextRound} disabled={actionLoading}
                            className="px-5 py-2.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white font-semibold text-sm transition-colors cursor-pointer disabled:opacity-40 flex items-center gap-2">
                            {actionLoading ? (
                              <><div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />Iniciando…</>
                            ) : (
                              <><svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="13 17 18 12 13 7"/><polyline points="6 17 11 12 6 7"/></svg>Ronda {data.session!.currentRound + 1}</>
                            )}
                          </button>
                        ) : (
                          <button onClick={() => setShowSummary(true)}
                            className="px-5 py-2.5 rounded-xl bg-[#22C55E] hover:bg-[#16A34A] text-white font-semibold text-sm transition-colors cursor-pointer flex items-center gap-2">
                            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                            Cerrar Mercado
                          </button>
                        )}
                      </>
                    )}
                    {data.session?.allRoundDone && !isAdmin && (
                      <div className="px-3 py-1.5 rounded-lg border border-[#F59E0B]/20 bg-[#F59E0B]/10 text-[#F59E0B] text-[10px] font-semibold">
                        ESPERANDO ADMIN
                      </div>
                    )}
                    {!data.session?.allRoundDone && (
                      <div className="px-2.5 py-1.5 rounded-lg border border-[#22C55E]/20 bg-[#22C55E]/10 text-[#22C55E] text-[10px] font-semibold">
                        EN VIVO
                      </div>
                    )}
                    {data.incomingOffers.length > 0 && (
                      <button
                        onClick={() => setModal("offers")}
                        className="relative px-3 py-2 rounded-lg border border-[#F59E0B]/30 bg-[#F59E0B]/10 text-[#F59E0B] text-xs font-medium cursor-pointer"
                      >
                        {data.incomingOffers.length} oferta{data.incomingOffers.length > 1 ? "s" : ""}
                      </button>
                    )}
                  </div>
                </div>
                <div className="flex items-center gap-2 mt-3 overflow-x-auto pb-1">
                  {data.turns.map((t) => (
                    <TurnChip key={t.id} turn={t} isMe={t.memberId === data.myStatus.memberId} />
                  ))}
                </div>
              </div>

              <div className="px-4 md:px-5 py-3 border-b border-white/6 space-y-2">
                <div className="flex items-center gap-2 flex-wrap">
                  <div className="relative w-full sm:w-72">
                    <input
                      value={searchQ}
                      onChange={(e) => setSearchQ(e.target.value)}
                      placeholder="Buscar jugador, equipo o dueño..."
                      className="w-full bg-[#0D0F14] border border-white/10 rounded-xl px-4 py-2.5 text-sm text-[#F3F4F6] placeholder:text-[#9CA3AF]/50 focus:outline-none focus:border-[#8B5CF6]/50"
                    />
                  </div>
                  <div className="flex items-center gap-1.5 overflow-x-auto">
                    {POS_FILTERS.map((f) => (
                      <button
                        key={f.label}
                        onClick={() => setPosFilter(f.label)}
                        className={`px-3 py-1.5 rounded-lg text-xs font-semibold shrink-0 border cursor-pointer transition-colors ${
                          posFilter === f.label ? "bg-[#8B5CF6] border-[#8B5CF6] text-white" : "bg-[#0D0F14] border-white/10 text-[#9CA3AF] hover:bg-[#1A1F2E]"
                        }`}
                      >
                        {f.label}
                      </button>
                    ))}
                  </div>
                </div>
                <div className="flex items-center gap-1.5 overflow-x-auto">
                  {uniqueTeams.map((team) => (
                    <button
                      key={team}
                      onClick={() => setTeamFilter(team)}
                      className={`px-3 py-1.5 rounded-lg text-xs font-semibold shrink-0 border cursor-pointer transition-colors ${
                        teamFilter === team
                          ? "bg-[#8B5CF6]/18 text-[#C4B5FD] border-[#8B5CF6]/35"
                          : "bg-[#0D0F14] text-[#9CA3AF] border-white/10 hover:bg-[#1A1F2E]"
                      }`}
                    >
                      {team === "ALL" ? "Todos" : team}
                    </button>
                  ))}
                </div>
              </div>

              <div className="flex-1 min-h-0 overflow-y-auto px-4 md:px-5 py-4">
                {filtered.length === 0 ? (
                  <div className="h-40 flex items-center justify-center text-[#9CA3AF]/45 text-sm">No hay jugadores disponibles.</div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 2xl:grid-cols-3 gap-3">
                    {filtered.map((p) => (
                      <PlayerMarketCard
                        key={p.playerId}
                        player={p}
                        canAct={canAct}
                        onClause={() => { setSelectedPlayer(p); setModal("clause"); setActionMsg(""); }}
                        onOffer={() => { setSelectedPlayer(p); setModal("offer"); setActionMsg(""); setOfferAmount(""); }}
                      />
                    ))}
                  </div>
                )}
              </div>
            </div>
          </section>

          <aside className="xl:w-[320px] rounded-3xl border border-white/6 bg-[#131722] p-4 overflow-y-auto">
            {data.isMyTurn ? (
              <motion.div
                initial={{ opacity: 0, scale: 0.95 }}
                animate={{ opacity: 1, scale: 1 }}
                className="rounded-2xl border border-[#8B5CF6]/40 p-4"
                style={{
                  background: "linear-gradient(135deg, rgba(139,92,246,0.18) 0%, rgba(139,92,246,0.06) 100%)",
                  boxShadow: "0 0 24px rgba(139,92,246,0.12)",
                }}
              >
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2.5">
                    <div className="w-8 h-8 rounded-lg bg-[#8B5CF6] flex items-center justify-center shadow-md shadow-[#8B5CF6]/25">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                        <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
                      </svg>
                    </div>
                    <p className="text-white text-sm font-bold tracking-wide">ES TU TURNO</p>
                  </div>
                  <div className="flex items-center gap-1.5 bg-[#8B5CF6]/20 border border-[#8B5CF6]/35 rounded-lg px-2.5 py-1">
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#C4B5FD" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>
                    </svg>
                    <span className="text-[#C4B5FD] text-sm font-bold tabular-nums">
                      {Math.floor(turnElapsed / 60)}:{String(turnElapsed % 60).padStart(2, "0")}
                    </span>
                  </div>
                </div>
                <div className="flex items-center justify-between">
                  <p className="text-[10px] uppercase tracking-[0.18em] text-[#C4B5FD]">Mi Presupuesto</p>
                  <span className="w-2 h-2 rounded-full bg-[#8B5CF6] animate-pulse" />
                </div>
                <p className="text-[#F3F4F6] text-3xl font-bold mt-1">
                  <RollingNumber value={data.myStatus.budget} format={fmt} />
                </p>
              </motion.div>
            ) : (
              <div className="rounded-2xl border border-[#8B5CF6]/25 bg-[#8B5CF6]/10 p-4">
                <p className="text-[10px] uppercase tracking-[0.18em] text-[#C4B5FD]">Mi Presupuesto</p>
                <p className="text-[#F3F4F6] text-3xl font-bold mt-1">
                  <RollingNumber value={data.myStatus.budget} format={fmt} />
                </p>
              </div>
            )}

            <div className="mt-4 rounded-2xl border border-white/8 bg-[#0D0F14] p-4 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-[#9CA3AF] text-sm">Fichajes usados</span>
                <span className="text-[#F3F4F6] text-base font-semibold">{data.myStatus.purchasesUsed}/3</span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-[#9CA3AF] text-sm">Protección cláusula</span>
                <span className={`text-sm font-semibold ${data.myStatus.teamClauseProtected ? "text-[#22C55E]" : "text-[#EF4444]"}`}>
                  {data.myStatus.teamClauseProtected ? "Activa" : "Inactiva"}
                </span>
              </div>
              <div className="flex items-center justify-between">
                <span className="text-[#9CA3AF] text-sm">Ofertas pendientes</span>
                <span className="text-[#F3F4F6] text-base font-semibold">{data.incomingOffers.length}</span>
              </div>
              <button
                onClick={doSkip}
                disabled={!data.isMyTurn || actionLoading || data.myStatus.hasPendingOffer}
                className="w-full py-2.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white text-sm font-semibold transition-colors cursor-pointer disabled:opacity-35 disabled:cursor-not-allowed"
              >
                Pasar Turno
              </button>
            </div>

            <div className="mt-4 rounded-2xl border border-white/8 bg-[#0D0F14] p-4">
              <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-3">Participantes</p>
              <div className="space-y-2.5">
                {data.allMembers.map((m) => {
                  const isMe = m.id === data.myStatus.memberId;
                  return (
                    <div key={m.id} className="flex items-center justify-between gap-2">
                      <div className="min-w-0">
                        <p className={`text-xs font-semibold truncate ${isMe ? "text-[#8B5CF6]" : "text-[#F3F4F6]"}`}>
                          {m.displayName}{isMe ? " (tú)" : ""}
                        </p>
                        <p className="text-[#6B7280] text-[10px] truncate">{m.teamName ?? "Sin equipo"}</p>
                      </div>
                      <span className="text-[#9CA3AF] text-[11px]">{m.purchasesUsed}/3</span>
                    </div>
                  );
                })}
              </div>
            </div>

            {myMember && (
              <div className="mt-4 rounded-2xl border border-white/8 bg-[#0D0F14] p-4">
                <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-2">Mi estado</p>
                <p className="text-[#F3F4F6] text-sm font-semibold">{myMember.displayName}</p>
                <p className="text-[#9CA3AF] text-xs mt-1">{data.myStatus.myTeamName ?? "Sin equipo asignado"}</p>
              </div>
            )}
          </aside>
        </div>
      </div>

      <div className="fixed top-6 right-6 z-[60] flex flex-col gap-3 pointer-events-none">
        <AnimatePresence mode="popLayout">
          {toasts.map((t) => (
            <motion.div
              key={t.id}
              layout
              initial={{ opacity: 0, x: 80, scale: 0.9 }}
              animate={{ opacity: 1, x: 0, scale: 1 }}
              exit={{ opacity: 0, x: 80, scale: 0.9 }}
              transition={{ duration: 0.3, ease: "easeOut" }}
              className={`flex items-center gap-4 px-5 py-4 rounded-2xl border-2 shadow-2xl min-w-[320px] max-w-sm pointer-events-auto ${
                t.type === "turn"    ? "bg-[#8B5CF6] border-[#A78BFA] text-white shadow-[#8B5CF6]/40" :
                t.type === "success" ? "bg-[#131722] border-[#22C55E]/60 text-[#F3F4F6] shadow-[#22C55E]/15" :
                t.type === "warning" ? "bg-[#131722] border-[#F59E0B]/60 text-[#F3F4F6] shadow-[#F59E0B]/15" :
                                       "bg-[#131722] border-[#8B5CF6]/40 text-[#F3F4F6] shadow-[#8B5CF6]/10"
              }`}>
              <div className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${
                t.type === "turn"    ? "bg-white/20" :
                t.type === "success" ? "bg-[#22C55E]/15" :
                t.type === "warning" ? "bg-[#F59E0B]/15" :
                                       "bg-[#8B5CF6]/15"
              }`}>
                {t.type === "turn" && (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/>
                  </svg>
                )}
                {t.type === "success" && (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12"/>
                  </svg>
                )}
                {t.type === "warning" && (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#F59E0B" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>
                  </svg>
                )}
                {t.type === "info" && (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <circle cx="12" cy="12" r="10"/><line x1="12" y1="16" x2="12" y2="12"/><line x1="12" y1="8" x2="12.01" y2="8"/>
                  </svg>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-base font-bold leading-tight">{t.message}</p>
                {t.sub && <p className={`text-sm mt-1 ${t.type === "turn" ? "text-white/80" : "text-[#9CA3AF]"}`}>{t.sub}</p>}
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
        {modal === "offer" && selectedPlayer && (() => {
          const offerCol = ovrColor(selectedPlayer.ovr);
          const parsedAmount = parseInt(offerAmount.replace(/\D/g, "")) || 0;
          const amountInCents = parsedAmount * 1_000_000;
          const exceedsBudget = amountInCents > data.myStatus.budget;
          const remaining = data.myStatus.budget - amountInCents;
          return (
            <Modal onClose={() => setModal(null)}>
              <div className="flex flex-col gap-5">
                <div className="flex items-center gap-4">
                  <div className="w-20 h-20 rounded-2xl overflow-hidden shrink-0 bg-[#0D0F14] flex items-center justify-center"
                    style={{ border: `2px solid ${offerCol.bg}44` }}>
                    {selectedPlayer.headshotUrl ? (
                      <img src={selectedPlayer.headshotUrl} alt={selectedPlayer.playerName}
                        className="w-full h-full object-contain object-bottom" />
                    ) : (
                      <span className="font-black text-2xl" style={{ color: offerCol.bg }}>
                        {selectedPlayer.ovr}
                      </span>
                    )}
                  </div>
                  <div>
                    <p className="text-[#9CA3AF] text-xs uppercase tracking-widest mb-1">Hacer oferta</p>
                    <h2 className="text-[#F3F4F6] text-2xl font-bold leading-tight">{selectedPlayer.playerName}</h2>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="px-2 py-0.5 rounded-lg text-xs font-black" style={{ background: offerCol.bg, color: offerCol.text }}>{selectedPlayer.ovr}</span>
                      <span className="text-sm text-[#9CA3AF]">{selectedPlayer.position} · {selectedPlayer.teamName}</span>
                    </div>
                  </div>
                </div>
                <div className="grid grid-cols-3 gap-3">
                  <StatBox label="Precio ref." value={fmt(selectedPlayer.price)} />
                  <StatBox label="Cláusula" value={fmt(selectedPlayer.clause)} highlight />
                  <StatBox label="Tu presupuesto" value={fmt(data.myStatus.budget)} />
                </div>
                <div>
                  <label className="text-[#9CA3AF] text-sm font-medium block mb-2">Monto de la oferta (en millones €)</label>
                  <div className="flex items-center gap-3 bg-[#0D0F14] border border-white/10 rounded-xl px-4 py-3 focus-within:border-[#8B5CF6]/60 transition-colors">
                    <span className="text-[#9CA3AF] text-lg font-bold">€</span>
                    <input
                      type="number"
                      min="1"
                      value={offerAmount}
                      onChange={(e) => {
                        const val = e.target.value.replace(/[^0-9]/g, "");
                        setOfferAmount(val);
                        setActionMsg("");
                      }}
                      placeholder="Ej: 45"
                      className="flex-1 bg-transparent text-[#F3F4F6] text-xl font-bold focus:outline-none placeholder:text-[#9CA3AF]/30 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                    />
                    <span className="text-[#9CA3AF] text-lg font-bold">M</span>
                  </div>
                  {parsedAmount > 0 && (
                    <div className="flex items-center justify-between mt-2 px-1">
                      <span className="text-xs text-[#9CA3AF]">Total: <span className="text-[#F3F4F6] font-semibold">{fmt(amountInCents)}</span></span>
                      <span className={`text-xs font-semibold ${exceedsBudget ? "text-[#EF4444]" : "text-[#22C55E]"}`}>
                        Restante: {exceedsBudget ? "Insuficiente" : fmt(remaining)}
                      </span>
                    </div>
                  )}
                </div>
                {exceedsBudget && (
                  <div className="bg-[#EF4444]/10 border border-[#EF4444]/20 rounded-xl px-4 py-3 flex items-center gap-2">
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
                    </svg>
                    <span className="text-[#EF4444] text-sm font-medium">El monto excede tu presupuesto de {fmt(data.myStatus.budget)}.</span>
                  </div>
                )}
                {actionMsg && <p className="text-[#EF4444] text-sm font-medium">{actionMsg}</p>}
                <div className="flex gap-3">
                  <button onClick={() => setModal(null)}
                    className="flex-1 py-3.5 rounded-xl border border-white/10 text-[#9CA3AF] hover:text-[#F3F4F6] text-sm font-medium transition-colors cursor-pointer">
                    Cancelar
                  </button>
                  <button onClick={doOffer} disabled={actionLoading || exceedsBudget || parsedAmount <= 0}
                    className="flex-1 py-3.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white text-sm font-semibold transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed">
                    {actionLoading ? "Enviando…" : `Ofertar ${parsedAmount > 0 ? fmt(amountInCents) : ""}`}
                  </button>
                </div>
              </div>
            </Modal>
          );
        })()}

        {/* Incoming offers */}
        {modal === "offers" && (
          <Modal onClose={() => setModal(null)}>
            <div className="flex flex-col gap-5">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-xl bg-[#F59E0B]/10 border border-[#F59E0B]/25 flex items-center justify-center shrink-0">
                  <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#F59E0B" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="16" y1="13" x2="8" y2="13"/><line x1="16" y1="17" x2="8" y2="17"/>
                  </svg>
                </div>
                <div>
                  <h2 className="text-[#F3F4F6] font-bold text-xl">Ofertas recibidas</h2>
                  <p className="text-[#9CA3AF] text-sm mt-0.5">Puedes aceptar o rechazar en cualquier momento</p>
                </div>
              </div>
              {data.incomingOffers.length === 0
                ? (
                  <div className="bg-[#0D0F14] rounded-2xl p-8 text-center">
                    <p className="text-[#9CA3AF] text-base">No tienes ofertas pendientes.</p>
                  </div>
                )
                : data.incomingOffers.map((o) => {
                  const offerOvrCol = o.playerOvr ? ovrColor(o.playerOvr) : { bg: "#9CA3AF", text: "#fff" };
                  return (
                    <div key={o.id} className="bg-[#0D0F14] rounded-2xl p-5 border border-white/6">
                      <div className="flex items-center gap-4">
                        <div className="w-18 h-18 rounded-2xl overflow-hidden shrink-0 bg-[#131722] border border-white/8 flex items-center justify-center">
                          {o.playerHeadshot ? (
                            <img src={o.playerHeadshot} alt={o.playerName}
                              className="w-full h-full object-contain object-bottom" />
                          ) : o.playerOvr ? (
                            <span className="font-black text-2xl" style={{ color: offerOvrCol.bg }}>{o.playerOvr}</span>
                          ) : null}
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            {o.playerOvr && (
                              <span className="px-2 py-0.5 rounded-lg text-xs font-black" style={{ background: offerOvrCol.bg, color: offerOvrCol.text }}>
                                {o.playerOvr}
                              </span>
                            )}
                            <span className="px-2 py-0.5 rounded-lg text-xs font-bold bg-white/8 text-[#F3F4F6]">{o.playerPosition}</span>
                          </div>
                          <p className="text-[#F3F4F6] text-lg font-bold leading-tight">{o.playerName}</p>
                          <p className="text-[#9CA3AF] text-sm mt-0.5">
                            Oferta de <span className="text-[#F3F4F6] font-semibold">{o.buyerName}</span>
                          </p>
                        </div>
                        <div className="text-right shrink-0">
                          <p className="text-[10px] text-[#9CA3AF] uppercase tracking-wider mb-1">Monto</p>
                          <p className="text-[#22C55E] text-2xl font-black">{fmt(o.amount)}</p>
                        </div>
                      </div>
                      <div className="flex gap-3 mt-4">
                        <button onClick={() => respondOffer(o.id, "reject")}
                          disabled={!!respondingOfferId}
                          className="flex-1 py-3 rounded-xl border border-[#EF4444]/30 text-[#EF4444] text-sm font-semibold hover:bg-[#EF4444]/10 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2">
                          {respondingOfferId === o.id ? (
                            <div className="w-4 h-4 border-2 border-[#EF4444]/30 border-t-[#EF4444] rounded-full animate-spin" />
                          ) : (
                            <>
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                                <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                              </svg>
                              Rechazar
                            </>
                          )}
                        </button>
                        <button onClick={() => respondOffer(o.id, "accept")}
                          disabled={!!respondingOfferId}
                          className="flex-1 py-3 rounded-xl bg-[#22C55E] hover:bg-[#16A34A] text-white text-sm font-bold transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2">
                          {respondingOfferId === o.id ? (
                            <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                          ) : (
                            <>
                              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                                <polyline points="20 6 9 17 4 12"/>
                              </svg>
                              Aceptar
                            </>
                          )}
                        </button>
                      </div>
                    </div>
                  );
                })
              }
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
    <div className={`rounded-2xl border transition-colors p-4 bg-[#0D0F14] ${
      player.clauseProtected ? "border-[#3B82F6]/30" : "border-white/8 hover:border-white/18 hover:bg-[#131722]"
    }`}>
      <div className="flex items-center gap-4">
        <div className="w-18 h-18 rounded-2xl bg-[#131722] border border-white/8 overflow-hidden shrink-0 flex items-center justify-center">
          {player.headshotUrl && !imgError ? (
            <img src={player.headshotUrl} alt={player.playerName} onError={() => setImgError(true)} className="w-full h-full object-contain object-bottom" />
          ) : (
            <span className="text-2xl font-black" style={{ color: col.bg }}>{player.playerName.charAt(0)}</span>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="px-2 py-1 rounded-lg text-xs font-black" style={{ background: col.bg, color: col.text }}>{player.ovr}</span>
            <span className="px-2 py-1 rounded-lg text-xs font-bold bg-white/8 text-[#F3F4F6]">{player.position}</span>
            {player.clauseProtected && (
              <span className="ml-auto flex items-center gap-1 text-xs text-[#3B82F6] font-medium">
                <ShieldIcon size={12} filled />
                Protegido
              </span>
            )}
          </div>
          <p className="mt-2 text-base font-bold text-[#F3F4F6] truncate">{player.playerName}</p>
          <p className="text-sm text-[#9CA3AF] truncate mt-0.5">{player.teamName} · {player.ownerName}</p>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-2.5 mt-4">
        <div className="rounded-xl bg-[#131722] border border-white/6 px-3 py-2.5">
          <p className="text-[#6B7280] text-xs uppercase font-medium">Precio</p>
          <p className="text-[#F3F4F6] text-base font-bold mt-0.5">{fmt(player.price)}</p>
        </div>
        <div className="rounded-xl bg-[#131722] border border-white/6 px-3 py-2.5">
          <p className="text-[#6B7280] text-xs uppercase font-medium">Cláusula</p>
          <p className="text-[#EF4444] text-base font-bold mt-0.5">{fmt(player.clause)}</p>
        </div>
      </div>
      <div className="flex gap-2.5 mt-4">
        <button onClick={onOffer} disabled={!canAct} className="flex-1 h-10 rounded-xl border border-[#8B5CF6]/35 text-[#8B5CF6] text-sm font-semibold hover:bg-[#8B5CF6]/12 transition-colors cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed">
          Ofrecer
        </button>
        <button onClick={onClause} disabled={!canAct || player.clauseProtected} className="flex-1 h-10 rounded-xl border border-[#EF4444]/35 text-[#EF4444] text-sm font-semibold hover:bg-[#EF4444]/12 transition-colors cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed">
          Cláusula
        </button>
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

function MarketFinished({ data, code, adminToken, onBack }: {
  data: MarketState;
  code: string;
  adminToken: string | null;
  onBack?: () => void;
}) {
  const [closing, setClosing] = useState(false);
  const [actionError, setActionError] = useState("");

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
      return;
    }
    saveTournamentStatus(code, "lobby");
    window.location.href = `/lobby/${code}`;
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
          {onBack && (
            <button onClick={onBack}
              className="w-full py-3 rounded-2xl border border-white/10 hover:bg-[#1A1F2E] text-[#9CA3AF] font-medium text-sm transition-colors cursor-pointer">
              Volver al mercado
            </button>
          )}
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


