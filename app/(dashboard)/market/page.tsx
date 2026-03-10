"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  getLastTournamentCode,
  getMemberToken,
  getAdminToken,
  getMemberId,
  saveMemberId,
  saveTournamentStatus,
} from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";
import type { RealtimeChannel } from "@supabase/supabase-js";
import RollingNumber from "../../Components/RollingNumber";
import {
  playSound,
  isSoundEnabled,
  setSoundEnabled,
} from "@/lib/sounds";
import {
  registerPushSubscription,
  unregisterPushSubscription,
} from "@/lib/pushClient";

// ── Types ─────────────────────────────────────────────────────────────────────

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
  teamCrestUrl: string | null;
  ownerId: string;
  ownerName: string;
  clauseProtected: boolean;
  inNegotiation: boolean;
}

interface OfferEntry {
  id: string;
  buyerId: string;
  buyerName: string;
  sellerId: string;
  sellerName: string;
  playerId: string;
  playerName: string;
  playerOvr: number | null;
  playerPosition: string;
  playerHeadshot: string | null;
  playerPrice: number;
  playerClause: number;
  amount: number;
  expiresAt: string | null;
  counterAmount: number | null;
  parentOfferId: string | null;
  createdAt: string;
}

interface MyStatus {
  memberId: string;
  budget: number;
  budgetReserved: number;
  purchasesUsed: number;
  maxPurchases: number;
  iconSlotUsed: boolean;
  myTeamId: string | null;
  myTeamName: string | null;
  myTeamCrestUrl: string | null;
  pendingIncoming: number;
  pendingOutgoing: number;
}

interface TimerInfo {
  closesAt: string | null;
  timeRemainingMs: number | null;
  isClosingSoon: boolean;
  isUrgent: boolean;
}

interface MarketState {
  status: "pending" | "active" | "finished";
  session: {
    id: string;
    status: string;
    opensAt: string;
    closesAt: string;
    durationHours: number;
    startedAt: string;
    finishedAt: string | null;
  } | null;
  timer: TimerInfo;
  myStatus: MyStatus;
  availablePlayers: PlayerCard[];
  myIncomingOffers: OfferEntry[];
  myOutgoingOffers: OfferEntry[];
  recentTransfers: any[];
  clauseProtectionEnabled: boolean;
  unreadNotifications: number;
  allMembers: {
    id: string;
    displayName: string;
    teamName: string | null;
    teamCrestUrl: string | null;
    purchasesUsed: number;
  }[];
}

// ── Formatters ────────────────────────────────────────────────────────────────

function fmt(v: number) {
  if (!v || isNaN(v)) return "—";
  if (v >= 1_000_000) return `€${(v / 1_000_000).toFixed(0)}M`;
  if (v >= 1_000) return `€${(v / 1_000).toFixed(0)}K`;
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
  if (minutes < 60) return `Hace ${minutes} min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `Hace ${hours}h`;
  const days = Math.floor(hours / 24);
  return `Hace ${days}d`;
}

function formatCountdown(ms: number | null) {
  if (ms === null || ms <= 0) return "Cerrado";
  const totalMin = Math.floor(ms / 60000);
  const hours = Math.floor(totalMin / 60);
  const minutes = totalMin % 60;
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

function formatTimeLeft(expiresAt: string | null) {
  if (!expiresAt) return null;
  const ms = new Date(expiresAt).getTime() - Date.now();
  if (ms <= 0) return "Expirada";
  const hours = Math.floor(ms / 3600000);
  const minutes = Math.floor((ms % 3600000) / 60000);
  if (hours > 0) return `Expira en ${hours}h ${minutes}m`;
  return `Expira en ${minutes}m`;
}

const INSIDER_IMG = "/cavsulas.png";

function pickRandom<T>(arr: T[], id: string): T {
  let hash = 0;
  for (let i = 0; i < id.length; i++)
    hash = ((hash << 5) - hash + id.charCodeAt(i)) | 0;
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
    return pickRandom(
      [
        {
          type: "🚨 BREAKING",
          headline: `${b} activa la cláusula de ${p} por ${a}. Here we go! ✅`,
          context: `${st} queda protegido por cláusula. Movimiento confirmado. 🔴🔵`,
        },
        {
          type: "🚨 EXCLUSIVA",
          headline: `BOMBAZO. ${p} se va con ${b} por ${a}. Cláusula pagada. 💣`,
          context: `${st} no pudo retenerlo. Protección de cláusula activada. ✅`,
        },
        {
          type: "🚨 CONFIRMED",
          headline: `${p} a ${b} por ${a}, cláusula activada. Done deal. 🤝`,
          context: `${st} recibe el dinero. Here we go confirmed! ✅`,
        },
      ],
      id
    );
  }

  if (transfer.transferType === "pending_offer") {
    return pickRandom(
      [
        {
          type: "🔄 OFERTA ENVIADA",
          headline: `${b} presenta oferta formal de ${a} por ${p}. ⏳`,
          context: `${s} tiene la decisión. Negociaciones en curso... 🔜`,
        },
        {
          type: "📋 NUEVA OFERTA",
          headline: `Oferta de ${a} de ${b} por ${p} está sobre la mesa. 📝`,
          context: `Pendiente de respuesta de ${s}. Mercatto en vivo. ⏳`,
        },
        {
          type: "💰 OFERTA FORMAL",
          headline: `${b} quiere a ${p} y ofrece ${a}. Esperando respuesta. 🔔`,
          context: `${s} debe decidir. Todos los ojos en este movimiento. 👀`,
        },
      ],
      id
    );
  }

  if (transfer.transferType === "rejected") {
    return pickRandom(
      [
        {
          type: "❌ OFERTA RECHAZADA",
          headline: `${s} dice NO a ${b} por ${p}. Oferta rechazada. ❌`,
          context: `La propuesta de ${a} no fue suficiente. El jugador se queda. 🔒`,
        },
        {
          type: "🚫 RECHAZADA",
          headline: `Nada que hacer. ${s} rechaza la oferta de ${b} por ${p}. ❌`,
          context: `${a} no convenció. Sin acuerdo. ⛔`,
        },
      ],
      id
    );
  }

  if (transfer.transferType === "icon_auction") {
    return pickRandom(
      [
        {
          type: "🌟 LEYENDA DE VUELTA",
          headline: `¡${p} SALE DEL RETIRO! 🔥 ${b} lo convence de volver. ${a}. Here we go! ✅`,
          context: `Una leyenda regresa. ${b} hace historia. 🏆👑`,
        },
        {
          type: "👑 REGRESO LEGENDARIO",
          headline: `LOCURA TOTAL. ${p} deja la jubilación para jugar con ${b}. ${a} 💰🤯`,
          context: `El retiro puede esperar. Leyenda viva. ⚽🔥`,
        },
      ],
      id
    );
  }

  return pickRandom(
    [
      {
        type: "✅ HERE WE GO",
        headline: `${b} y ${s} cierran a ${p} por ${a}. Here we go! ✅🤝`,
        context: `Negociación completada. Deal done. ✅`,
      },
      {
        type: "🤝 DEAL DONE",
        headline: `${p} a ${b} por ${a}. Acuerdo total con ${s}. Done deal! 🔥`,
        context: `Fichaje confirmado. Welcome! 🎉`,
      },
      {
        type: "✅ FICHAJE OFICIAL",
        headline: `OFICIAL: ${p} fichado por ${b}. ${a} al equipo de ${s}. 💰`,
        context: `Todo cerrado. Documentos firmados. Welcome! 🎉`,
      },
    ],
    id
  );
}

// ── Main Page ─────────────────────────────────────────────────────────────────

export default function MarketPage() {
  const [code, setCode] = useState<string | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [adminToken, setAdminToken] = useState<string | null>(null);
  const [data, setData] = useState<MarketState | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [modal, setModal] = useState<
    "clause" | "offer" | "offers" | "notifications" | null
  >(null);
  const [selectedPlayer, setSelectedPlayer] = useState<PlayerCard | null>(null);
  const [offerAmount, setOfferAmount] = useState("");
  const [actionLoading, setActionLoading] = useState(false);
  const [actionMsg, setActionMsg] = useState("");
  const [posFilter, setPosFilter] = useState("TODOS");
  const [teamFilter, setTeamFilter] = useState("ALL");
  const [searchQ, setSearchQ] = useState("");
  const [showSummary, setShowSummary] = useState(false);
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [counterMode, setCounterMode] = useState<string | null>(null);
  const [counterAmount, setCounterAmount] = useState("");
  const [notifications, setNotifications] = useState<any[]>([]);
  const [liveTimer, setLiveTimer] = useState<number | null>(null);
  const [soundsOn, setSoundsOn] = useState(true);
  const [pushStatus, setPushStatus] = useState<"idle" | "granted" | "denied" | "loading">("idle");

  useEffect(() => {
    setSoundsOn(isSoundEnabled());
    if (typeof Notification !== "undefined") {
      setPushStatus(Notification.permission === "granted" ? "granted" : Notification.permission === "denied" ? "denied" : "idle");
    }
  }, []);

  const channelRef = useRef<RealtimeChannel | null>(null);
  const sessionIdRef = useRef<string | null>(null);
  const prevDataRef = useRef<MarketState | null>(null);
  const fetchingRef = useRef(false);
  const pendingFetchRef = useRef(false);
  const adminTokenRef = useRef<string | null>(null);
  const feedRef = useRef<HTMLDivElement | null>(null);

  interface Toast {
    id: number;
    type: "info" | "success" | "warning" | "action";
    message: string;
    sub?: string;
  }
  const [toasts, setToasts] = useState<Toast[]>([]);
  const toastIdRef = useRef(0);

  const pushToast = useCallback(
    (type: Toast["type"], message: string, sub?: string) => {
      const id = ++toastIdRef.current;
      setToasts((prev) => [...prev.slice(-4), { id, type, message, sub }]);
      setTimeout(
        () => setToasts((prev) => prev.filter((t) => t.id !== id)),
        5000
      );
    },
    []
  );

  useEffect(() => {
    const c = getLastTournamentCode();
    const t = c ? getMemberToken(c) : null;
    const a = c ? getAdminToken(c) : null;
    setCode(c);
    setToken(t);
    setAdminToken(a);
    adminTokenRef.current = a;
  }, []);

  const fetchData = useCallback(
    async (silent = false) => {
      if (!code || !token) return;
      if (fetchingRef.current) {
        pendingFetchRef.current = true;
        return;
      }
      fetchingRef.current = true;
      if (!silent) setLoading(true);

      try {
        const res = await fetch(`/api/tournaments/${code}/market`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) {
          setError("Error al cargar el mercado.");
          return;
        }
        const d: MarketState = await res.json();

        const prev = prevDataRef.current;
        if (prev && d.status === "active") {
          const prevNewestId = prev.recentTransfers[0]?.id;
          const newNewestId = d.recentTransfers[0]?.id;
          if (newNewestId && newNewestId !== prevNewestId) {
            const newest = d.recentTransfers[0];
            if (newest.transferType === "clause") {
              pushToast(
                "warning",
                "Cláusula activada",
                `${newest.playerName} por ${fmt(newest.amount)}`
              );
              playSound("warning");
            } else if (
              newest.transferType !== "rejected" &&
              newest.transferType !== "skip"
            ) {
              pushToast(
                "info",
                `Transferencia: ${newest.playerName}`,
                `${newest.buyerName} ← ${newest.sellerTeamName}`
              );
              playSound("success");
            }
          }

          if (
            d.myStatus.pendingIncoming > 0 &&
            d.myStatus.pendingIncoming > (prev.myStatus.pendingIncoming ?? 0)
          ) {
            pushToast(
              "action",
              "Nueva oferta recibida",
              "Revisa tu panel de ofertas"
            );
            playSound("ping");
          }
        }

        prevDataRef.current = d;
        setData(d);
        setError("");

        if (d.timer.timeRemainingMs !== null) {
          setLiveTimer(d.timer.timeRemainingMs);
        }

        if (code) saveTournamentStatus(code, "market");
        if (code && d.myStatus?.memberId) {
          saveMemberId(code, d.myStatus.memberId);
        }

        if (d.session?.id) sessionIdRef.current = d.session.id;

        if (d.status === "finished") {
          setShowSummary(true);
        }
      } catch {
        setError("Error de conexión.");
      } finally {
        fetchingRef.current = false;
        setLoading(false);
        if (pendingFetchRef.current) {
          pendingFetchRef.current = false;
          fetchData(true);
        }
      }
    },
    [code, token, pushToast]
  );

  // Live countdown timer
  useEffect(() => {
    if (liveTimer === null || liveTimer <= 0) return;
    const interval = setInterval(() => {
      setLiveTimer((prev) => (prev !== null ? Math.max(0, prev - 1000) : null));
    }, 1000);
    return () => clearInterval(interval);
  }, [liveTimer]);

  // Realtime subscription
  useEffect(() => {
    if (!code || !token) return;

    const supabase = getBrowserClient();
    const setupChannel = (sessionId: string) => {
      if (channelRef.current) supabase.removeChannel(channelRef.current);

      const onDbChange = () => fetchData(true);

      channelRef.current = supabase
        .channel(`market:${sessionId}`)
        .on(
          "postgres_changes",
          {
            event: "INSERT",
            schema: "public",
            table: "market_transfers",
            filter: `session_id=eq.${sessionId}`,
          },
          onDbChange
        )
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "market_offers",
            filter: `session_id=eq.${sessionId}`,
          },
          onDbChange
        )
        .on(
          "postgres_changes",
          {
            event: "UPDATE",
            schema: "public",
            table: "market_sessions",
            filter: `id=eq.${sessionId}`,
          },
          onDbChange
        )
        .on(
          "postgres_changes",
          {
            event: "*",
            schema: "public",
            table: "icon_auctions",
            filter: `session_id=eq.${sessionId}`,
          },
          onDbChange
        )
        .subscribe();
    };

    fetchData(false).then(() => {
      if (sessionIdRef.current) setupChannel(sessionIdRef.current);
    });

    return () => {
      if (channelRef.current) {
        supabase.removeChannel(channelRef.current);
        channelRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [code, token]);

  // Fetch notifications
  const fetchNotifications = useCallback(async () => {
    if (!code || !token) return;
    try {
      const res = await fetch(
        `/api/tournaments/${code}/notifications?limit=20`,
        {
          headers: { Authorization: `Bearer ${token}` },
        }
      );
      if (res.ok) {
        const d = await res.json();
        setNotifications(d.notifications ?? []);
      }
    } catch {
      /* non-blocking */
    }
  }, [code, token]);

  const markNotificationsRead = async () => {
    if (!code || !token) return;
    await fetch(`/api/tournaments/${code}/notifications`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ all: true }),
    });
    fetchData(true);
    fetchNotifications();
  };

  // ── Actions ───────────────────────────────────────────────────────────────

  const doClause = async () => {
    if (!selectedPlayer || !code || !token) return;
    setActionLoading(true);
    setActionMsg("");
    const res = await fetch(`/api/tournaments/${code}/market/clause`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ playerId: selectedPlayer.playerId }),
    });
    const d = await res.json();
    if (!res.ok) {
      setActionMsg(d.error ?? "Error al ejecutar la acción.");
      setActionLoading(false);
      return;
    }
    setModal(null);
    setSelectedPlayer(null);
    setActionLoading(false);
    fetchData(true);
  };

  const doOffer = async () => {
    if (!selectedPlayer || !code || !token || !data) return;
    const raw = parseInt(offerAmount.replace(/\D/g, ""));
    if (!raw || raw <= 0) {
      setActionMsg("Ingresa un monto válido (mayor a 0).");
      return;
    }
    const amount = raw * 1_000_000;
    const avail = data.myStatus.budget - data.myStatus.budgetReserved;
    if (amount > avail) {
      setActionMsg(
        `No tienes suficiente presupuesto. Disponible: ${fmt(avail)}.`
      );
      return;
    }
    setActionLoading(true);
    const res = await fetch(`/api/tournaments/${code}/market/offer`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ playerId: selectedPlayer.playerId, amount }),
    });
    const d = await res.json();
    if (!res.ok) {
      setActionMsg(d.error);
      setActionLoading(false);
      return;
    }
    setModal(null);
    setOfferAmount("");
    fetchData(true);
    setActionLoading(false);
  };

  const [respondingOfferId, setRespondingOfferId] = useState<string | null>(
    null
  );

  const respondOffer = async (
    offerId: string,
    action: "accept" | "reject" | "counter",
    cAmount?: number
  ) => {
    if (!code || !token || respondingOfferId) return;
    setRespondingOfferId(offerId);
    try {
      await fetch(`/api/tournaments/${code}/market/offer/${offerId}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          action,
          ...(action === "counter" && cAmount
            ? { counterAmount: cAmount }
            : {}),
        }),
      });
      setModal(null);
      setCounterMode(null);
      setCounterAmount("");
      fetchData(true);
    } finally {
      setRespondingOfferId(null);
    }
  };

  const doCloseMarket = async () => {
    if (!code || !adminToken) return;
    setActionLoading(true);
    const res = await fetch(`/api/tournaments/${code}/market/close`, {
      method: "POST",
      headers: { Authorization: `Bearer ${adminToken}` },
    });
    if (res.ok) {
      await fetchData();
      setShowSummary(true);
    }
    setActionLoading(false);
  };

  useEffect(() => {
    if (!data?.recentTransfers?.length || !feedRef.current) return;
    feedRef.current.scrollTo({ top: 0, behavior: "smooth" });
  }, [data?.recentTransfers?.[0]?.id]);

  // ── Guard states ──────────────────────────────────────────────────────────
  if (!code || !token) {
    return (
      <div className="min-h-screen flex items-center justify-center p-8">
        <EmptyCard
          icon="🔒"
          title="Sin sesión"
          sub="Únete a un torneo para acceder al mercado."
        />
      </div>
    );
  }

  if (loading)
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="w-10 h-10 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          <p className="text-[#9CA3AF] text-sm">Cargando mercado…</p>
        </div>
      </div>
    );

  if (error)
    return (
      <div className="min-h-screen flex items-center justify-center p-8">
        <EmptyCard icon="⚠️" title="Error" sub={error} />
      </div>
    );

  if (!data || data.status === "pending") {
    return (
      <MarketPending
        code={code}
        adminToken={adminToken}
        onStarted={() => fetchData()}
      />
    );
  }

  if (data.status === "finished" || showSummary) {
    return (
      <MarketFinished
        data={data}
        code={code}
        adminToken={adminToken}
      />
    );
  }

  // ── Filters ─────────────────────────────────────────────────────────────────
  const POS_FILTERS: { label: string; positions: string[] }[] = [
    { label: "TODOS", positions: [] },
    { label: "POR", positions: ["POR", "GK"] },
    { label: "DFC", positions: ["DFC", "CB"] },
    { label: "LI", positions: ["LI", "LB"] },
    { label: "LD", positions: ["LD", "RB"] },
    { label: "MCD", positions: ["MCD", "CDM"] },
    { label: "MC", positions: ["MC", "CM"] },
    { label: "MCO", positions: ["MCO", "CAM"] },
    { label: "EI", positions: ["EI", "LW", "MI", "LM"] },
    { label: "ED", positions: ["ED", "RW", "MD", "RM"] },
    { label: "DC", positions: ["DC", "ST"] },
    { label: "SD", positions: ["SD", "CF", "SS"] },
  ];
  const uniqueTeams = [
    "ALL",
    ...Array.from(
      new Set(data.availablePlayers.map((p) => p.teamName))
    ).sort(),
  ];
  const activeFilterPositions =
    POS_FILTERS.find((f) => f.label === posFilter)?.positions ?? [];
  const filtered = data.availablePlayers.filter((p) => {
    const matchPos =
      posFilter === "TODOS" ||
      activeFilterPositions.includes(p.position.toUpperCase());
    const matchTeam = teamFilter === "ALL" || p.teamName === teamFilter;
    const matchSearch =
      !searchQ ||
      p.playerName.toLowerCase().includes(searchQ.toLowerCase()) ||
      p.teamName.toLowerCase().includes(searchQ.toLowerCase()) ||
      p.ownerName.toLowerCase().includes(searchQ.toLowerCase());
    return matchPos && matchTeam && matchSearch;
  });

  const isAdmin = !!adminToken;
  const canAct = data.myStatus.purchasesUsed < data.myStatus.maxPurchases;
  const hasActions =
    data.myStatus.pendingIncoming > 0 || data.myStatus.pendingOutgoing > 0;

  // Timer color
  const timerColor =
    data.timer.isUrgent
      ? "text-[#EF4444]"
      : data.timer.isClosingSoon
        ? "text-[#F59E0B]"
        : "text-[#22C55E]";

  const timerBorder =
    data.timer.isUrgent
      ? "border-[#EF4444]/30"
      : data.timer.isClosingSoon
        ? "border-[#F59E0B]/30"
        : "border-[#22C55E]/30";

  return (
    <div className="relative h-full overflow-hidden bg-[#0D0F14]">
      <div className="h-full min-h-0 px-4 md:px-6 pb-6 pt-4">
        <div className="h-full min-h-0 flex flex-col xl:flex-row gap-4">
          {/* ── LEFT: Mercatto Insider Feed ─────────────────────────────── */}
          <aside
            className={`bg-[#131722] border border-white/6 rounded-3xl min-h-0 overflow-hidden transition-all duration-200 ease-out ${
              sidebarCollapsed ? "xl:w-18" : "xl:w-85"
            }`}
          >
            <div className="h-full flex flex-col">
              <div className="px-3 py-3 border-b border-white/6 flex items-center justify-between">
                <button
                  onClick={() => setSidebarCollapsed((v) => !v)}
                  className="w-9 h-9 rounded-xl border border-white/10 hover:bg-[#1A1F2E] transition-colors flex items-center justify-center cursor-pointer"
                >
                  <svg
                    width="14"
                    height="14"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#F3F4F6"
                    strokeWidth="2.2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <line x1="3" y1="6" x2="21" y2="6" />
                    <line x1="3" y1="12" x2="21" y2="12" />
                    <line x1="3" y1="18" x2="21" y2="18" />
                  </svg>
                </button>
                {!sidebarCollapsed && (
                  <div className="flex items-center gap-2.5">
                    <img
                      src={INSIDER_IMG}
                      alt="Capsulizio Pelado"
                      className="w-8 h-8 rounded-full object-cover"
                    />
                    <div>
                      <div className="flex items-center gap-1">
                        <p className="text-[#F3F4F6] text-sm font-semibold">
                          Capsulizio Pelado
                        </p>
                        <span className="w-4 h-4 rounded-full bg-[#1D9BF0] text-white text-[9px] flex items-center justify-center font-bold">
                          ✓
                        </span>
                      </div>
                      <p className="text-[#9CA3AF] text-xs">
                        @CapsulaPelado
                      </p>
                    </div>
                  </div>
                )}
              </div>

              {sidebarCollapsed ? (
                <div className="flex-1 flex flex-col items-center py-4 gap-3">
                  <img
                    src={INSIDER_IMG}
                    alt="CP"
                    className="w-9 h-9 rounded-full object-cover"
                  />
                  <div className="w-9 h-9 rounded-xl bg-[#1A1F2E] border border-white/8 flex items-center justify-center text-[#9CA3AF] text-xs">
                    {data.recentTransfers.length}
                  </div>
                </div>
              ) : (
                <div
                  ref={feedRef}
                  className="flex-1 min-h-0 overflow-y-auto px-3 py-3 space-y-3"
                >
                  {data.recentTransfers.map((t: any, idx: number) => {
                    const copy = insiderCopy(t);
                    return (
                      <motion.div
                        key={t.id}
                        initial={{ opacity: 0, y: 8 }}
                        animate={{ opacity: 1, y: 0 }}
                        transition={{
                          duration: 0.22,
                          delay: idx < 3 ? idx * 0.03 : 0,
                        }}
                        className={`rounded-2xl border bg-[#0D0F14] p-4 ${
                          t.transferType === "icon_auction"
                            ? "border-[#F59E0B]/25"
                            : t.transferType === "pending_offer"
                              ? "border-[#F59E0B]/20"
                              : t.transferType === "clause"
                                ? "border-[#EF4444]/15"
                                : t.transferType === "rejected"
                                  ? "border-white/6"
                                  : "border-[#22C55E]/15"
                        }`}
                      >
                        <div className="flex items-start gap-3">
                          <img
                            src={INSIDER_IMG}
                            alt="Capsulizio Pelado"
                            className="w-11 h-11 rounded-full object-cover shrink-0"
                          />
                          <div className="min-w-0 flex-1">
                            <div className="flex items-center gap-1.5 text-xs">
                              <span className="text-[#F3F4F6] font-semibold">
                                Capsulizio Pelado
                              </span>
                              <span className="w-4 h-4 rounded-full bg-[#1D9BF0] text-white text-[9px] flex items-center justify-center font-bold">
                                ✓
                              </span>
                            </div>
                            <p className="mt-2 text-xs tracking-[0.15em] uppercase font-bold text-[#8B5CF6]">
                              {copy.type}
                            </p>
                            <p className="text-[#F3F4F6] text-base font-bold leading-snug mt-1">
                              {copy.headline}
                            </p>
                            <p className="text-[#9CA3AF] text-sm leading-snug mt-1.5">
                              {copy.context}
                            </p>
                            <div className="mt-3 flex items-center justify-between">
                              <span className="text-[#6B7280] text-xs">
                                {timeAgo(t.createdAt)}
                              </span>
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

          {/* ── CENTER: Market Grid ──────────────────────────────────────── */}
          <section className="flex-1 min-h-0 rounded-3xl border bg-[#131722] overflow-hidden border-white/6">
            <div className="h-full flex flex-col min-h-0">
              {/* Header with timer */}
              <div className="px-4 md:px-5 py-4 border-b border-white/6">
                <div className="flex items-center justify-between gap-3 flex-wrap">
                  <div className="flex items-center gap-3">
                    <div
                      className={`px-4 py-2.5 rounded-xl bg-[#0D0F14] border ${timerBorder} text-center`}
                    >
                      <p className="text-[9px] text-[#9CA3AF] uppercase tracking-widest">
                        Cierra en
                      </p>
                      <p
                        className={`text-lg font-bold tabular-nums ${timerColor}`}
                      >
                        {formatCountdown(liveTimer)}
                      </p>
                    </div>
                    <div>
                      <p className="text-[#F3F4F6] text-sm font-semibold">
                        Mercado Abierto
                      </p>
                      <p className="text-[#9CA3AF] text-xs">
                        Oferta o paga cláusulas libremente
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {isAdmin && (
                      <button
                        onClick={doCloseMarket}
                        disabled={actionLoading}
                        className="px-4 py-2 rounded-xl bg-[#EF4444] hover:bg-[#DC2626] text-white text-sm font-semibold transition-colors cursor-pointer disabled:opacity-50 flex items-center gap-2"
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
                          <polyline points="20 6 9 17 4 12" />
                        </svg>
                        Cerrar Mercado
                      </button>
                    )}
                    {/* Notification bell */}
                    <button
                      onClick={() => {
                        setModal("notifications");
                        fetchNotifications();
                      }}
                      className="relative w-10 h-10 rounded-xl border border-white/10 hover:bg-[#1A1F2E] flex items-center justify-center cursor-pointer transition-colors"
                    >
                      <svg
                        width="18"
                        height="18"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="#F3F4F6"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
                        <path d="M13.73 21a2 2 0 0 1-3.46 0" />
                      </svg>
                      {(data.unreadNotifications ?? 0) > 0 && (
                        <span className="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-[#EF4444] text-white text-[10px] font-bold flex items-center justify-center">
                          {data.unreadNotifications > 9
                            ? "9+"
                            : data.unreadNotifications}
                        </span>
                      )}
                    </button>
                    {/* Sound toggle */}
                    <button
                      onClick={() => {
                        const next = !soundsOn;
                        setSoundsOn(next);
                        setSoundEnabled(next);
                        if (next) playSound("tap");
                      }}
                      title={soundsOn ? "Sonidos: ON" : "Sonidos: OFF"}
                      className="relative w-10 h-10 rounded-xl border border-white/10 hover:bg-[#1A1F2E] flex items-center justify-center cursor-pointer transition-colors"
                    >
                      {soundsOn ? (
                        <svg
                          width="18"
                          height="18"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="#F3F4F6"
                          strokeWidth="2"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                        >
                          <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                          <path d="M19.07 4.93a10 10 0 0 1 0 14.14M15.54 8.46a5 5 0 0 1 0 7.07" />
                        </svg>
                      ) : (
                        <svg
                          width="18"
                          height="18"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="#6B7280"
                          strokeWidth="2"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                        >
                          <polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
                          <line x1="23" y1="9" x2="17" y2="15" />
                          <line x1="17" y1="9" x2="23" y2="15" />
                        </svg>
                      )}
                    </button>
                    <div className="px-2.5 py-1.5 rounded-lg border border-[#22C55E]/20 bg-[#22C55E]/10 text-[#22C55E] text-[10px] font-semibold">
                      EN VIVO
                    </div>
                  </div>
                </div>
              </div>

              {/* Filters */}
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
                          posFilter === f.label
                            ? "bg-[#8B5CF6] border-[#8B5CF6] text-white"
                            : "bg-[#0D0F14] border-white/10 text-[#9CA3AF] hover:bg-[#1A1F2E]"
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

              {/* Player grid */}
              <div className="flex-1 min-h-0 overflow-y-auto px-4 md:px-5 py-4">
                {filtered.length === 0 ? (
                  <div className="h-40 flex items-center justify-center text-[#9CA3AF]/45 text-sm">
                    No hay jugadores disponibles.
                  </div>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 2xl:grid-cols-3 gap-3">
                    {filtered.map((p) => (
                      <PlayerMarketCard
                        key={p.playerId}
                        player={p}
                        canAct={canAct}
                        clauseProtectionEnabled={data.clauseProtectionEnabled}
                        onClause={() => {
                          setSelectedPlayer(p);
                          setModal("clause");
                          setActionMsg("");
                        }}
                        onOffer={() => {
                          setSelectedPlayer(p);
                          setModal("offer");
                          setActionMsg("");
                          setOfferAmount("");
                        }}
                      />
                    ))}
                  </div>
                )}
              </div>
            </div>
          </section>

          {/* ── RIGHT: Personal Panel ──────────────────────────────────── */}
          <aside className="xl:w-[320px] rounded-3xl border border-white/6 bg-[#131722] p-4 overflow-y-auto">
            {/* Budget */}
            <div className="rounded-2xl border border-[#8B5CF6]/25 bg-[#8B5CF6]/10 p-4">
              <p className="text-[10px] uppercase tracking-[0.18em] text-[#C4B5FD]">
                Presupuesto Disponible
              </p>
              <p className="text-[#F3F4F6] text-3xl font-bold mt-1">
                <RollingNumber value={data.myStatus.budget - data.myStatus.budgetReserved} format={fmt} />
              </p>
              {data.myStatus.budgetReserved > 0 && (
                <div className="flex items-center justify-between mt-2 pt-2 border-t border-white/8">
                  <span className="text-[#9CA3AF] text-[10px]">Total: {fmt(data.myStatus.budget)}</span>
                  <span className="text-[#F59E0B] text-[10px]">Reservado en subastas: {fmt(data.myStatus.budgetReserved)}</span>
                </div>
              )}
            </div>

            {/* Status cards */}
            <div className="mt-4 rounded-2xl border border-white/8 bg-[#0D0F14] p-4 space-y-3">
              <div className="flex items-center justify-between">
                <span className="text-[#9CA3AF] text-sm">Fichajes usados</span>
                <span className="text-[#F3F4F6] text-base font-semibold">
                  {data.myStatus.purchasesUsed}/{data.myStatus.maxPurchases}
                </span>
              </div>
              <div className="w-full bg-[#1A1F2E] rounded-full h-1.5">
                <div
                  className="bg-[#8B5CF6] h-1.5 rounded-full transition-all"
                  style={{
                    width: `${(data.myStatus.purchasesUsed / data.myStatus.maxPurchases) * 100}%`,
                  }}
                />
              </div>
              <div className="flex items-center justify-between">
                <span className="text-[#9CA3AF] text-sm">
                  Subasta Ícono
                </span>
                <span
                  className={`text-sm font-semibold ${data.myStatus.iconSlotUsed ? "text-[#9CA3AF]" : "text-[#22C55E]"}`}
                >
                  {data.myStatus.iconSlotUsed ? "Usado" : "Disponible"}
                </span>
              </div>
            </div>

            {/* Pending actions */}
            {hasActions && (
              <div className="mt-4 rounded-2xl border border-[#F59E0B]/20 bg-[#F59E0B]/5 p-4">
                <p className="text-[#F59E0B] text-xs font-bold uppercase tracking-widest mb-3">
                  Acciones pendientes
                </p>
                {data.myStatus.pendingIncoming > 0 && (
                  <button
                    onClick={() => setModal("offers")}
                    className="w-full flex items-center justify-between py-2.5 px-3 rounded-xl bg-[#0D0F14] border border-white/8 hover:border-[#F59E0B]/30 transition-colors cursor-pointer mb-2"
                  >
                    <span className="text-[#F3F4F6] text-sm font-medium">
                      {data.myStatus.pendingIncoming} oferta
                      {data.myStatus.pendingIncoming > 1 ? "s" : ""} recibida
                      {data.myStatus.pendingIncoming > 1 ? "s" : ""}
                    </span>
                    <svg
                      width="14"
                      height="14"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="#F59E0B"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <polyline points="9 18 15 12 9 6" />
                    </svg>
                  </button>
                )}
                {data.myStatus.pendingOutgoing > 0 && (
                  <div className="flex items-center gap-2 py-2 px-3 rounded-xl bg-[#0D0F14] border border-white/8">
                    <div className="w-2 h-2 rounded-full bg-[#8B5CF6] animate-pulse" />
                    <span className="text-[#9CA3AF] text-sm">
                      {data.myStatus.pendingOutgoing} oferta
                      {data.myStatus.pendingOutgoing > 1 ? "s" : ""} enviada
                      {data.myStatus.pendingOutgoing > 1 ? "s" : ""}
                    </span>
                  </div>
                )}
              </div>
            )}

            {/* CTA buttons */}
            <div className="mt-4 space-y-2">
              <a
                href={`/subastas`}
                className="w-full flex items-center justify-center gap-2 py-3 rounded-xl border border-[#8B5CF6]/30 text-[#8B5CF6] text-sm font-semibold hover:bg-[#8B5CF6]/8 transition-colors cursor-pointer"
              >
                <svg
                  width="16"
                  height="16"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
                </svg>
                Ver Subastas
              </a>
              {pushStatus !== "granted" && pushStatus !== "denied" && (
                <button
                  onClick={async () => {
                    if (!code || !token) return;
                    setPushStatus("loading");
                    try {
                      const ok = await registerPushSubscription(code, token);
                      setPushStatus(ok ? "granted" : "denied");
                    } catch {
                      setPushStatus("denied");
                    }
                  }}
                  disabled={pushStatus === "loading"}
                  className="w-full flex items-center justify-center gap-2 py-3 rounded-xl border border-[#22C55E]/30 text-[#22C55E] text-sm font-semibold hover:bg-[#22C55E]/8 transition-colors cursor-pointer disabled:opacity-40"
                >
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/>
                    <path d="M13.73 21a2 2 0 0 1-3.46 0"/>
                  </svg>
                  {pushStatus === "loading" ? "Activando…" : "Activar notificaciones"}
                </button>
              )}
              {pushStatus === "granted" && (
                <div className="w-full flex items-center justify-center gap-2 py-3 rounded-xl border border-[#22C55E]/20 bg-[#22C55E]/5 text-[#22C55E] text-sm font-semibold">
                  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                  Notificaciones activas
                </div>
              )}
              {pushStatus === "denied" && (
                <div className="w-full flex items-center justify-center gap-2 py-2.5 rounded-xl border border-[#EF4444]/20 bg-[#EF4444]/5 text-[#EF4444]/80 text-xs">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <circle cx="12" cy="12" r="10"/><line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
                  </svg>
                  Notificaciones bloqueadas
                </div>
              )}
            </div>

            {/* Participants */}
            <div className="mt-4 rounded-2xl border border-white/8 bg-[#0D0F14] p-4">
              <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-3">
                Participantes
              </p>
              <div className="space-y-2.5">
                {data.allMembers.map((m) => {
                  const isMe = m.id === data.myStatus.memberId;
                  return (
                    <div
                      key={m.id}
                      className="flex items-center justify-between gap-2"
                    >
                      <div className="min-w-0">
                        <p
                          className={`text-xs font-semibold truncate ${isMe ? "text-[#8B5CF6]" : "text-[#F3F4F6]"}`}
                        >
                          {m.displayName}
                          {isMe ? " (tú)" : ""}
                        </p>
                        <p className="text-[#6B7280] text-[10px] truncate">
                          {m.teamName ?? "Sin equipo"}
                        </p>
                      </div>
                      <span className="text-[#9CA3AF] text-[11px]">
                        {m.purchasesUsed}/{data.myStatus.maxPurchases}
                      </span>
                    </div>
                  );
                })}
              </div>
            </div>
          </aside>
        </div>
      </div>

      {/* ── Toasts ── */}
      <div className="fixed top-6 right-6 z-60 flex flex-col gap-3 pointer-events-none">
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
                t.type === "action"
                  ? "bg-[#8B5CF6] border-[#A78BFA] text-white shadow-[#8B5CF6]/40"
                  : t.type === "success"
                    ? "bg-[#131722] border-[#22C55E]/60 text-[#F3F4F6] shadow-[#22C55E]/15"
                    : t.type === "warning"
                      ? "bg-[#131722] border-[#F59E0B]/60 text-[#F3F4F6] shadow-[#F59E0B]/15"
                      : "bg-[#131722] border-[#8B5CF6]/40 text-[#F3F4F6] shadow-[#8B5CF6]/10"
              }`}
            >
              <div
                className={`w-10 h-10 rounded-xl flex items-center justify-center shrink-0 ${
                  t.type === "action"
                    ? "bg-white/20"
                    : t.type === "success"
                      ? "bg-[#22C55E]/15"
                      : t.type === "warning"
                        ? "bg-[#F59E0B]/15"
                        : "bg-[#8B5CF6]/15"
                }`}
              >
                {t.type === "action" && (
                  <svg
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="white"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
                  </svg>
                )}
                {t.type === "success" && (
                  <svg
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#22C55E"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                )}
                {t.type === "warning" && (
                  <svg
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#F59E0B"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
                    <line x1="12" y1="9" x2="12" y2="13" />
                    <line x1="12" y1="17" x2="12.01" y2="17" />
                  </svg>
                )}
                {t.type === "info" && (
                  <svg
                    width="20"
                    height="20"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#8B5CF6"
                    strokeWidth="2.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <circle cx="12" cy="12" r="10" />
                    <line x1="12" y1="16" x2="12" y2="12" />
                    <line x1="12" y1="8" x2="12.01" y2="8" />
                  </svg>
                )}
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-base font-bold leading-tight">{t.message}</p>
                {t.sub && (
                  <p
                    className={`text-sm mt-1 ${t.type === "action" ? "text-white/80" : "text-[#9CA3AF]"}`}
                  >
                    {t.sub}
                  </p>
                )}
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
                <div
                  className="w-16 h-16 rounded-2xl overflow-hidden shrink-0 bg-[#0D0F14] flex items-center justify-center"
                  style={{
                    border: `1.5px solid ${ovrColor(selectedPlayer.ovr).bg}44`,
                  }}
                >
                  {selectedPlayer.headshotUrl ? (
                    <img
                      src={selectedPlayer.headshotUrl}
                      alt={selectedPlayer.playerName}
                      className="w-full h-full object-contain object-bottom"
                    />
                  ) : (
                    <span
                      className="font-black text-lg"
                      style={{ color: ovrColor(selectedPlayer.ovr).bg }}
                    >
                      {selectedPlayer.ovr}
                    </span>
                  )}
                </div>
                <div>
                  <p className="text-[#9CA3AF] text-xs uppercase tracking-widest mb-1">
                    Pagar cláusula
                  </p>
                  <h2 className="text-[#F3F4F6] text-xl font-bold leading-tight">
                    {selectedPlayer.playerName}
                  </h2>
                  <p className="text-[#9CA3AF] text-sm">
                    {selectedPlayer.teamName} · {selectedPlayer.ownerName}
                  </p>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <StatBox label="OVR" value={selectedPlayer.ovr.toString()} />
                <StatBox
                  label="Cláusula"
                  value={fmt(selectedPlayer.clause)}
                  highlight
                />
                <StatBox
                  label="Disponible"
                  value={fmt(data.myStatus.budget - data.myStatus.budgetReserved)}
                />
                <StatBox
                  label="Restante"
                  value={fmt(data.myStatus.budget - data.myStatus.budgetReserved - selectedPlayer.clause)}
                />
              </div>
              {data.clauseProtectionEnabled && selectedPlayer.clauseProtected && (
                <div className="flex items-center gap-2 bg-[#EF4444]/10 border border-[#EF4444]/20 rounded-xl px-3 py-2.5">
                  <ShieldIcon />
                  <span className="text-[#EF4444] text-xs font-medium">
                    Este equipo ya está protegido. No puedes pagar la cláusula.
                  </span>
                </div>
              )}
              {(data.myStatus.budget - data.myStatus.budgetReserved) < selectedPlayer.clause && (
                <div className="bg-[#EF4444]/10 border border-[#EF4444]/20 rounded-xl px-3 py-2.5">
                  <span className="text-[#EF4444] text-xs font-medium">
                    Presupuesto disponible insuficiente.
                  </span>
                </div>
              )}
              {actionMsg && (
                <p className="text-[#EF4444] text-xs">{actionMsg}</p>
              )}
              <div className="flex gap-3">
                <button
                  onClick={() => setModal(null)}
                  className="flex-1 py-3 rounded-xl border border-white/10 text-[#9CA3AF] hover:text-[#F3F4F6] text-sm font-medium transition-colors cursor-pointer"
                >
                  Cancelar
                </button>
                <button
                  onClick={doClause}
                  disabled={
                    actionLoading ||
                    (data.clauseProtectionEnabled && selectedPlayer.clauseProtected) ||
                    (data.myStatus.budget - data.myStatus.budgetReserved) < selectedPlayer.clause
                  }
                  className="flex-1 py-3 rounded-xl bg-[#EF4444] hover:bg-[#DC2626] text-white text-sm font-semibold transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
                >
                  {actionLoading
                    ? "Procesando…"
                    : `Pagar ${fmt(selectedPlayer.clause)}`}
                </button>
              </div>
            </div>
          </Modal>
        )}

        {/* Offer modal */}
        {modal === "offer" &&
          selectedPlayer &&
          (() => {
            const offerCol = ovrColor(selectedPlayer.ovr);
            const parsedAmount =
              parseInt(offerAmount.replace(/\D/g, "")) || 0;
            const amountInCents = parsedAmount * 1_000_000;
            const availBudget = data.myStatus.budget - data.myStatus.budgetReserved;
            const exceedsBudget = amountInCents > availBudget;
            const remaining = availBudget - amountInCents;
            return (
              <Modal onClose={() => setModal(null)}>
                <div className="flex flex-col gap-5">
                  <div className="flex items-center gap-4">
                    <div
                      className="w-20 h-20 rounded-2xl overflow-hidden shrink-0 bg-[#0D0F14] flex items-center justify-center"
                      style={{ border: `2px solid ${offerCol.bg}44` }}
                    >
                      {selectedPlayer.headshotUrl ? (
                        <img
                          src={selectedPlayer.headshotUrl}
                          alt={selectedPlayer.playerName}
                          className="w-full h-full object-contain object-bottom"
                        />
                      ) : (
                        <span
                          className="font-black text-2xl"
                          style={{ color: offerCol.bg }}
                        >
                          {selectedPlayer.ovr}
                        </span>
                      )}
                    </div>
                    <div>
                      <p className="text-[#9CA3AF] text-xs uppercase tracking-widest mb-1">
                        Hacer oferta
                      </p>
                      <h2 className="text-[#F3F4F6] text-2xl font-bold leading-tight">
                        {selectedPlayer.playerName}
                      </h2>
                      <div className="flex items-center gap-2 mt-1">
                        <span
                          className="px-2 py-0.5 rounded-lg text-xs font-black"
                          style={{
                            background: offerCol.bg,
                            color: offerCol.text,
                          }}
                        >
                          {selectedPlayer.ovr}
                        </span>
                        <span className="text-sm text-[#9CA3AF]">
                          {selectedPlayer.position} · {selectedPlayer.teamName}
                        </span>
                      </div>
                      {selectedPlayer.inNegotiation && (
                        <p className="text-[#F59E0B] text-xs mt-1 font-medium">
                          En negociación
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="grid grid-cols-3 gap-3">
                    <StatBox
                      label="Precio ref."
                      value={fmt(selectedPlayer.price)}
                    />
                    <StatBox
                      label="Cláusula"
                      value={fmt(selectedPlayer.clause)}
                      highlight
                    />
                    <StatBox
                      label="Disponible"
                      value={fmt(data.myStatus.budget - data.myStatus.budgetReserved)}
                    />
                  </div>
                  <div>
                    <label className="text-[#9CA3AF] text-sm font-medium block mb-2">
                      Monto de la oferta (en millones €)
                    </label>
                    <div className="flex items-center gap-3 bg-[#0D0F14] border border-white/10 rounded-xl px-4 py-3 focus-within:border-[#8B5CF6]/60 transition-colors">
                      <span className="text-[#9CA3AF] text-lg font-bold">
                        €
                      </span>
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
                      <span className="text-[#9CA3AF] text-lg font-bold">
                        M
                      </span>
                    </div>
                    {parsedAmount > 0 && (
                      <div className="flex items-center justify-between mt-2 px-1">
                        <span className="text-xs text-[#9CA3AF]">
                          Total:{" "}
                          <span className="text-[#F3F4F6] font-semibold">
                            {fmt(amountInCents)}
                          </span>
                        </span>
                        <span
                          className={`text-xs font-semibold ${exceedsBudget ? "text-[#EF4444]" : "text-[#22C55E]"}`}
                        >
                          Restante:{" "}
                          {exceedsBudget ? "Insuficiente" : fmt(remaining)}
                        </span>
                      </div>
                    )}
                    <p className="text-[#6B7280] text-xs mt-2">
                      La oferta expira en 4 horas si no hay respuesta.
                    </p>
                  </div>
                  {exceedsBudget && (
                    <div className="bg-[#EF4444]/10 border border-[#EF4444]/20 rounded-xl px-4 py-3 flex items-center gap-2">
                      <svg
                        width="16"
                        height="16"
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
                      <span className="text-[#EF4444] text-sm font-medium">
                        El monto excede tu presupuesto disponible de{" "}
                        {fmt(data.myStatus.budget - data.myStatus.budgetReserved)}.
                      </span>
                    </div>
                  )}
                  {actionMsg && (
                    <p className="text-[#EF4444] text-sm font-medium">
                      {actionMsg}
                    </p>
                  )}
                  <div className="flex gap-3">
                    <button
                      onClick={() => setModal(null)}
                      className="flex-1 py-3.5 rounded-xl border border-white/10 text-[#9CA3AF] hover:text-[#F3F4F6] text-sm font-medium transition-colors cursor-pointer"
                    >
                      Cancelar
                    </button>
                    <button
                      onClick={doOffer}
                      disabled={
                        actionLoading || exceedsBudget || parsedAmount <= 0
                      }
                      className="flex-1 py-3.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white text-sm font-semibold transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      {actionLoading
                        ? "Enviando…"
                        : `Ofertar ${parsedAmount > 0 ? fmt(amountInCents) : ""}`}
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
                  <svg
                    width="22"
                    height="22"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#F59E0B"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
                    <polyline points="14 2 14 8 20 8" />
                    <line x1="16" y1="13" x2="8" y2="13" />
                    <line x1="16" y1="17" x2="8" y2="17" />
                  </svg>
                </div>
                <div>
                  <h2 className="text-[#F3F4F6] font-bold text-xl">
                    Ofertas recibidas
                  </h2>
                  <p className="text-[#9CA3AF] text-sm mt-0.5">
                    Acepta, rechaza o contra-oferta
                  </p>
                </div>
              </div>
              {data.myIncomingOffers.length === 0 ? (
                <div className="bg-[#0D0F14] rounded-2xl p-8 text-center">
                  <p className="text-[#9CA3AF] text-base">
                    No tienes ofertas pendientes.
                  </p>
                </div>
              ) : (
                data.myIncomingOffers.map((o) => {
                  const offerOvrCol = o.playerOvr
                    ? ovrColor(o.playerOvr)
                    : { bg: "#9CA3AF", text: "#fff" };
                  const timeLeft = formatTimeLeft(o.expiresAt);
                  const isCountering = counterMode === o.id;

                  return (
                    <div
                      key={o.id}
                      className="bg-[#0D0F14] rounded-2xl p-5 border border-white/6"
                    >
                      <div className="flex items-center gap-4">
                        <div className="w-18 h-18 rounded-2xl overflow-hidden shrink-0 bg-[#131722] border border-white/8 flex items-center justify-center">
                          {o.playerHeadshot ? (
                            <img
                              src={o.playerHeadshot}
                              alt={o.playerName}
                              className="w-full h-full object-contain object-bottom"
                            />
                          ) : o.playerOvr ? (
                            <span
                              className="font-black text-2xl"
                              style={{ color: offerOvrCol.bg }}
                            >
                              {o.playerOvr}
                            </span>
                          ) : null}
                        </div>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 mb-1">
                            {o.playerOvr && (
                              <span
                                className="px-2 py-0.5 rounded-lg text-xs font-black"
                                style={{
                                  background: offerOvrCol.bg,
                                  color: offerOvrCol.text,
                                }}
                              >
                                {o.playerOvr}
                              </span>
                            )}
                            <span className="px-2 py-0.5 rounded-lg text-xs font-bold bg-white/8 text-[#F3F4F6]">
                              {o.playerPosition}
                            </span>
                          </div>
                          <p className="text-[#F3F4F6] text-lg font-bold leading-tight">
                            {o.playerName}
                          </p>
                          <p className="text-[#9CA3AF] text-sm mt-0.5">
                            Oferta de{" "}
                            <span className="text-[#F3F4F6] font-semibold">
                              {o.buyerName}
                            </span>
                          </p>
                          {timeLeft && (
                            <p className="text-[#F59E0B] text-xs mt-1 font-medium">
                              {timeLeft}
                            </p>
                          )}
                        </div>
                        <div className="text-right shrink-0">
                          <p className="text-[10px] text-[#9CA3AF] uppercase tracking-wider mb-1">
                            Oferta
                          </p>
                          <p className="text-[#22C55E] text-2xl font-black">
                            {fmt(o.amount)}
                          </p>
                          <div className="mt-1.5 space-y-0.5">
                            <p className="text-[10px] text-[#9CA3AF]">
                              Valor:{" "}
                              <span className="text-[#F3F4F6] font-semibold">
                                {fmt(o.playerPrice)}
                              </span>
                            </p>
                            <p className="text-[10px] text-[#9CA3AF]">
                              Cláusula:{" "}
                              <span className="text-[#F3F4F6] font-semibold">
                                {fmt(o.playerClause)}
                              </span>
                            </p>
                          </div>
                        </div>
                      </div>

                      {isCountering ? (
                        <div className="mt-4 space-y-3">
                          <div className="flex items-center gap-3 bg-[#131722] border border-white/10 rounded-xl px-4 py-3">
                            <span className="text-[#9CA3AF] text-lg font-bold">
                              €
                            </span>
                            <input
                              type="number"
                              min="1"
                              value={counterAmount}
                              onChange={(e) =>
                                setCounterAmount(
                                  e.target.value.replace(/[^0-9]/g, "")
                                )
                              }
                              placeholder="Tu precio"
                              className="flex-1 bg-transparent text-[#F3F4F6] text-lg font-bold focus:outline-none placeholder:text-[#9CA3AF]/30 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                            />
                            <span className="text-[#9CA3AF] text-lg font-bold">
                              M
                            </span>
                          </div>
                          <div className="flex gap-2">
                            <button
                              onClick={() => {
                                setCounterMode(null);
                                setCounterAmount("");
                              }}
                              className="flex-1 py-2.5 rounded-xl border border-white/10 text-[#9CA3AF] text-sm font-medium cursor-pointer"
                            >
                              Cancelar
                            </button>
                            <button
                              onClick={() => {
                                const amt =
                                  parseInt(counterAmount) * 1_000_000;
                                if (amt > 0) {
                                  respondOffer(o.id, "counter", amt);
                                }
                              }}
                              disabled={
                                !!respondingOfferId ||
                                parseInt(counterAmount) <= 0
                              }
                              className="flex-1 py-2.5 rounded-xl bg-[#F59E0B] hover:bg-[#D97706] text-white text-sm font-semibold cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
                            >
                              Enviar contra-oferta
                            </button>
                          </div>
                        </div>
                      ) : (
                        <div className="flex gap-2.5 mt-4">
                          <button
                            onClick={() => respondOffer(o.id, "reject")}
                            disabled={!!respondingOfferId}
                            className="flex-1 py-3 rounded-xl border border-[#EF4444]/30 text-[#EF4444] text-sm font-semibold hover:bg-[#EF4444]/10 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                          >
                            {respondingOfferId === o.id ? (
                              <div className="w-4 h-4 border-2 border-[#EF4444]/30 border-t-[#EF4444] rounded-full animate-spin" />
                            ) : (
                              "Rechazar"
                            )}
                          </button>
                          <button
                            onClick={() => {
                              setCounterMode(o.id);
                              setCounterAmount("");
                            }}
                            disabled={!!respondingOfferId}
                            className="flex-1 py-3 rounded-xl border border-[#F59E0B]/30 text-[#F59E0B] text-sm font-semibold hover:bg-[#F59E0B]/10 transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed"
                          >
                            Contra-oferta
                          </button>
                          <button
                            onClick={() => respondOffer(o.id, "accept")}
                            disabled={!!respondingOfferId}
                            className="flex-1 py-3 rounded-xl bg-[#22C55E] hover:bg-[#16A34A] text-white text-sm font-bold transition-colors cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                          >
                            {respondingOfferId === o.id ? (
                              <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                            ) : (
                              "Aceptar"
                            )}
                          </button>
                        </div>
                      )}
                    </div>
                  );
                })
              )}
            </div>
          </Modal>
        )}

        {/* Notifications */}
        {modal === "notifications" && (
          <Modal onClose={() => setModal(null)}>
            <div className="flex flex-col gap-4">
              <div className="flex items-center justify-between">
                <h2 className="text-[#F3F4F6] font-bold text-xl">
                  Notificaciones
                </h2>
                {notifications.some((n: any) => !n.read) && (
                  <button
                    onClick={markNotificationsRead}
                    className="text-[#8B5CF6] text-xs font-semibold cursor-pointer hover:text-[#A78BFA]"
                  >
                    Marcar todo como leído
                  </button>
                )}
              </div>
              {notifications.length === 0 ? (
                <div className="bg-[#0D0F14] rounded-2xl p-8 text-center">
                  <p className="text-[#9CA3AF] text-sm">
                    No tienes notificaciones.
                  </p>
                </div>
              ) : (
                <div className="max-h-100 overflow-y-auto space-y-2">
                  {notifications.map((n: any) => (
                    <div
                      key={n.id}
                      className={`rounded-xl p-3 border ${
                        n.read
                          ? "bg-[#0D0F14] border-white/4"
                          : "bg-[#8B5CF6]/5 border-[#8B5CF6]/20"
                      }`}
                    >
                      <div className="flex items-start gap-2">
                        {!n.read && (
                          <span className="w-2 h-2 rounded-full bg-[#8B5CF6] shrink-0 mt-1.5" />
                        )}
                        <div className="min-w-0 flex-1">
                          <p className="text-[#F3F4F6] text-sm font-semibold">
                            {n.title}
                          </p>
                          {n.body && (
                            <p className="text-[#9CA3AF] text-xs mt-0.5">
                              {n.body}
                            </p>
                          )}
                          <p className="text-[#6B7280] text-[10px] mt-1">
                            {timeAgo(n.created_at)}
                          </p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </Modal>
        )}
      </AnimatePresence>
    </div>
  );
}

// ── Sub-components ─────────────────────────────────────────────────────────────

function PlayerMarketCard({
  player,
  canAct,
  clauseProtectionEnabled,
  onClause,
  onOffer,
}: {
  player: PlayerCard;
  canAct: boolean;
  clauseProtectionEnabled: boolean;
  onClause: () => void;
  onOffer: () => void;
}) {
  const col = ovrColor(player.ovr);
  const [imgError, setImgError] = useState(false);
  const isProtected = clauseProtectionEnabled && player.clauseProtected;

  return (
    <div
      className={`rounded-2xl border transition-colors p-4 bg-[#0D0F14] ${
        isProtected
          ? "border-[#3B82F6]/30"
          : player.inNegotiation
            ? "border-[#F59E0B]/25"
            : "border-white/8 hover:border-white/18 hover:bg-[#131722]"
      }`}
    >
      <div className="flex items-center gap-4">
        <div className="w-18 h-18 rounded-2xl bg-[#131722] border border-white/8 overflow-hidden shrink-0 flex items-center justify-center">
          {player.headshotUrl && !imgError ? (
            <img
              src={player.headshotUrl}
              alt={player.playerName}
              onError={() => setImgError(true)}
              className="w-full h-full object-contain object-bottom"
            />
          ) : (
            <span
              className="text-2xl font-black"
              style={{ color: col.bg }}
            >
              {player.playerName.charAt(0)}
            </span>
          )}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span
              className="px-2 py-1 rounded-lg text-xs font-black"
              style={{ background: col.bg, color: col.text }}
            >
              {player.ovr}
            </span>
            <span className="px-2 py-1 rounded-lg text-xs font-bold bg-white/8 text-[#F3F4F6]">
              {player.position}
            </span>
            {isProtected && (
              <span className="ml-auto flex items-center gap-1 text-xs text-[#3B82F6] font-medium">
                <ShieldIcon size={12} filled />
                Protegido
              </span>
            )}
            {player.inNegotiation && !isProtected && (
              <span className="ml-auto text-xs text-[#F59E0B] font-medium">
                En negociación
              </span>
            )}
          </div>
          <p className="mt-2 text-base font-bold text-[#F3F4F6] truncate">
            {player.playerName}
          </p>
          <p className="text-sm text-[#9CA3AF] truncate mt-0.5">
            {player.teamName} · {player.ownerName}
          </p>
        </div>
      </div>
      <div className="grid grid-cols-2 gap-2.5 mt-4">
        <div className="rounded-xl bg-[#131722] border border-white/6 px-3 py-2.5">
          <p className="text-[#6B7280] text-xs uppercase font-medium">
            Precio
          </p>
          <p className="text-[#F3F4F6] text-base font-bold mt-0.5">
            {fmt(player.price)}
          </p>
        </div>
        <div className="rounded-xl bg-[#131722] border border-white/6 px-3 py-2.5">
          <p className="text-[#6B7280] text-xs uppercase font-medium">
            Cláusula
          </p>
          <p className="text-[#EF4444] text-base font-bold mt-0.5">
            {fmt(player.clause)}
          </p>
        </div>
      </div>
      <div className="flex gap-2.5 mt-4">
        <button
          onClick={onOffer}
          disabled={!canAct}
          className="flex-1 h-10 rounded-xl border border-[#8B5CF6]/35 text-[#8B5CF6] text-sm font-semibold hover:bg-[#8B5CF6]/12 transition-colors cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed"
        >
          Ofrecer
        </button>
        <button
          onClick={onClause}
          disabled={!canAct || isProtected}
          className="flex-1 h-10 rounded-xl border border-[#EF4444]/35 text-[#EF4444] text-sm font-semibold hover:bg-[#EF4444]/12 transition-colors cursor-pointer disabled:opacity-30 disabled:cursor-not-allowed"
        >
          Cláusula
        </button>
      </div>
    </div>
  );
}

function Modal({
  children,
  onClose,
}: {
  children: React.ReactNode;
  onClose: () => void;
}) {
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
        className="bg-[#131722] rounded-3xl border border-white/10 p-7 w-full max-w-lg shadow-2xl max-h-[85vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {children}
      </motion.div>
    </motion.div>
  );
}

function MarketPending({
  code,
  adminToken,
  onStarted,
}: {
  code: string;
  adminToken: string | null;
  onStarted: () => void;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [hours, setHours] = useState("24");

  const start = async () => {
    if (!adminToken) return;
    setLoading(true);
    const res = await fetch(`/api/tournaments/${code}/market/start`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${adminToken}`,
      },
      body: JSON.stringify({ durationHours: parseInt(hours) || 24 }),
    });
    const d = await res.json();
    if (!res.ok) {
      setError(d.error);
      setLoading(false);
      return;
    }
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
            <line x1="12" y1="1" x2="12" y2="23" />
            <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
          </svg>
        </div>
        <div>
          <h1 className="text-[#F3F4F6] text-2xl font-bold mb-2">
            Mercado de Fichajes
          </h1>
          <p className="text-[#9CA3AF] text-sm leading-relaxed">
            {adminToken
              ? "Configura la duración y abre el mercado. Todos podrán negociar simultáneamente."
              : "El administrador debe abrir el mercado."}
          </p>
        </div>
        {adminToken && (
          <div className="w-full">
            <label className="text-[#9CA3AF] text-xs font-medium block mb-2 text-left">
              Duración del mercado (horas)
            </label>
            <div className="flex gap-2">
              {["6", "12", "24", "48"].map((h) => (
                <button
                  key={h}
                  onClick={() => setHours(h)}
                  className={`flex-1 py-2.5 rounded-xl text-sm font-semibold border cursor-pointer transition-colors ${
                    hours === h
                      ? "bg-[#8B5CF6] border-[#8B5CF6] text-white"
                      : "bg-[#0D0F14] border-white/10 text-[#9CA3AF] hover:bg-[#1A1F2E]"
                  }`}
                >
                  {h}h
                </button>
              ))}
            </div>
          </div>
        )}
        {error && <p className="text-[#EF4444] text-sm">{error}</p>}
        {adminToken ? (
          <button
            onClick={start}
            disabled={loading}
            className="w-full py-4 rounded-2xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white font-bold text-sm shadow-lg shadow-[#8B5CF6]/25 transition-all cursor-pointer disabled:opacity-50"
          >
            {loading ? "Iniciando…" : `Abrir Mercado (${hours}h)`}
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

function MarketFinished({
  data,
  code,
  adminToken,
}: {
  data: MarketState;
  code: string;
  adminToken: string | null;
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
    (t: any) =>
      t.transferType === "clause" ||
      t.transferType === "offer" ||
      t.transferType === "icon_auction"
  );
  const totalSpent = realTransfers.reduce(
    (s: number, t: any) => s + (t.amount ?? 0),
    0
  );
  const clauseCount = realTransfers.filter(
    (t: any) => t.transferType === "clause"
  ).length;
  const auctionCount = realTransfers.filter(
    (t: any) => t.transferType === "icon_auction"
  ).length;
  const offerCount = realTransfers.filter(
    (t: any) => t.transferType === "offer"
  ).length;

  const biggestDeal = realTransfers.length > 0
    ? realTransfers.reduce((a: any, b: any) =>
        (b.amount ?? 0) > (a.amount ?? 0) ? b : a
      )
    : null;

  const transfersByMember: Record<string, { bought: any[]; sold: any[] }> = {};
  for (const m of data.allMembers)
    transfersByMember[m.id] = { bought: [], sold: [] };
  for (const t of realTransfers) {
    if (t.buyerId && transfersByMember[t.buyerId])
      transfersByMember[t.buyerId].bought.push(t);
    if (t.sellerId && transfersByMember[t.sellerId])
      transfersByMember[t.sellerId].sold.push(t);
  }

  const mostActive = data.allMembers
    .map((m) => ({
      ...m,
      totalTx:
        (transfersByMember[m.id]?.bought.length ?? 0) +
        (transfersByMember[m.id]?.sold.length ?? 0),
      totalSpent: (transfersByMember[m.id]?.bought ?? []).reduce(
        (s: number, t: any) => s + (t.amount ?? 0),
        0
      ),
    }))
    .sort((a, b) => b.totalTx - a.totalTx);

  return (
    <motion.div
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      transition={{ duration: 0.5 }}
      className="p-8 max-w-5xl mx-auto"
    >
      {/* Header */}
      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5, delay: 0.1 }}
        className="text-center mb-10"
      >
        <div className="inline-flex items-center justify-center w-20 h-20 rounded-3xl bg-[#22C55E]/10 border border-[#22C55E]/20 mb-5">
          <svg
            width="36"
            height="36"
            viewBox="0 0 24 24"
            fill="none"
            stroke="#22C55E"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <polyline points="20 6 9 17 4 12" />
          </svg>
        </div>
        <h1 className="text-[#F3F4F6] text-3xl font-bold tracking-tight mb-2">
          Mercado Completado
        </h1>
        <p className="text-[#9CA3AF] text-sm">
          Resumen final del periodo de fichajes
        </p>
      </motion.div>

      {/* Global stats */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, delay: 0.2 }}
        className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8"
      >
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 text-center">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">
            Transferencias
          </p>
          <p className="text-[#F3F4F6] text-2xl font-bold">
            {realTransfers.length}
          </p>
        </div>
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 text-center">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">
            Total movido
          </p>
          <p className="text-[#22C55E] text-2xl font-bold">
            {fmt(totalSpent)}
          </p>
        </div>
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 text-center">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">
            Cláusulas
          </p>
          <p className="text-[#F59E0B] text-2xl font-bold">{clauseCount}</p>
        </div>
        <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 text-center">
          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">
            Subastas
          </p>
          <p className="text-[#8B5CF6] text-2xl font-bold">{auctionCount}</p>
        </div>
      </motion.div>

      {/* Biggest deal highlight */}
      {biggestDeal && (
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.4, delay: 0.3 }}
          className="bg-[#131722] rounded-2xl border border-[#8B5CF6]/20 p-6 mb-8 flex items-center gap-5 shadow-[0_0_40px_rgba(139,92,246,0.06)]"
        >
          <div className="w-14 h-14 rounded-2xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center shrink-0">
            <svg
              width="24"
              height="24"
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
          <div className="min-w-0 flex-1">
            <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">
              Fichaje más caro
            </p>
            <p className="text-[#F3F4F6] text-lg font-bold truncate">
              {biggestDeal.playerName}
            </p>
            <p className="text-[#9CA3AF] text-xs">
              {biggestDeal.buyerName} ← {biggestDeal.sellerTeamName ?? "Subasta"}
            </p>
          </div>
          <p className="text-[#22C55E] text-2xl font-bold shrink-0">
            {fmt(biggestDeal.amount)}
          </p>
        </motion.div>
      )}

      {/* Per-member breakdown */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4, delay: 0.4 }}
      >
        <h2 className="text-[#F3F4F6] text-lg font-semibold mb-4">
          Resumen por Mánager
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mb-8">
          {mostActive.map((m, idx) => {
            const tx = transfersByMember[m.id] ?? { bought: [], sold: [] };
            return (
              <motion.div
                key={m.id}
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ duration: 0.3, delay: 0.4 + idx * 0.05 }}
                className="bg-[#131722] rounded-2xl border border-white/6 p-5 flex flex-col gap-3"
              >
                <div className="flex items-center gap-3">
                  {m.teamCrestUrl ? (
                    <img
                      src={m.teamCrestUrl}
                      alt={m.teamName ?? ""}
                      className="w-8 h-8 object-contain shrink-0"
                    />
                  ) : (
                    <div className="w-8 h-8 rounded-full bg-[#8B5CF6]/15 flex items-center justify-center shrink-0">
                      <span className="text-[#8B5CF6] text-xs font-bold">
                        {m.displayName.charAt(0).toUpperCase()}
                      </span>
                    </div>
                  )}
                  <div className="min-w-0 flex-1">
                    <p className="text-[#F3F4F6] text-sm font-semibold truncate">
                      {m.displayName}
                    </p>
                    {m.teamName && (
                      <p className="text-[#9CA3AF] text-[10px] truncate">
                        {m.teamName}
                      </p>
                    )}
                  </div>
                  <div className="text-right shrink-0">
                    <p className="text-[#F3F4F6] text-sm font-bold">
                      {m.purchasesUsed}/{data.myStatus.maxPurchases}
                    </p>
                    {m.totalSpent > 0 && (
                      <p className="text-[#22C55E] text-[10px] font-semibold">
                        {fmt(m.totalSpent)}
                      </p>
                    )}
                  </div>
                </div>
                {tx.bought.length > 0 && (
                  <div className="flex flex-col gap-1">
                    <p className="text-[#6B7280] text-[9px] uppercase font-medium px-1">
                      Compras
                    </p>
                    {tx.bought.map((t: any, i: number) => (
                      <div
                        key={i}
                        className="flex items-center justify-between text-[10px] bg-[#22C55E]/5 rounded-lg px-2.5 py-1.5"
                      >
                        <span className="text-[#F3F4F6] font-medium truncate">
                          {t.playerName}
                        </span>
                        <span className="text-[#22C55E] font-bold shrink-0 ml-2">
                          {fmt(t.amount)}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
                {tx.sold.length > 0 && (
                  <div className="flex flex-col gap-1">
                    <p className="text-[#6B7280] text-[9px] uppercase font-medium px-1">
                      Ventas
                    </p>
                    {tx.sold.map((t: any, i: number) => (
                      <div
                        key={i}
                        className="flex items-center justify-between text-[10px] bg-[#EF4444]/5 rounded-lg px-2.5 py-1.5"
                      >
                        <span className="text-[#F3F4F6] font-medium truncate">
                          {t.playerName}
                        </span>
                        <span className="text-[#EF4444] font-bold shrink-0 ml-2">
                          {fmt(t.amount)}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
                {tx.bought.length === 0 && tx.sold.length === 0 && (
                  <p className="text-[#4B5563] text-[10px] text-center py-2">
                    Sin movimientos
                  </p>
                )}
              </motion.div>
            );
          })}
        </div>
      </motion.div>

      {/* All transfers timeline */}
      {realTransfers.length > 0 && (
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.5 }}
          className="mb-8"
        >
          <h2 className="text-[#F3F4F6] text-lg font-semibold mb-4">
            Todos los Movimientos
          </h2>
          <div className="bg-[#131722] rounded-2xl border border-white/6 divide-y divide-white/4">
            {realTransfers.map((t: any, i: number) => (
              <div
                key={i}
                className="flex items-center gap-4 px-5 py-3.5"
              >
                <div
                  className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 ${
                    t.transferType === "clause"
                      ? "bg-[#F59E0B]/10"
                      : t.transferType === "icon_auction"
                        ? "bg-[#8B5CF6]/10"
                        : "bg-[#22C55E]/10"
                  }`}
                >
                  {t.transferType === "clause" && (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#F59E0B" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
                    </svg>
                  )}
                  {t.transferType === "icon_auction" && (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
                    </svg>
                  )}
                  {t.transferType === "offer" && (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <p className="text-[#F3F4F6] text-sm font-semibold truncate">
                    {t.playerName}
                  </p>
                  <p className="text-[#9CA3AF] text-[10px]">
                    {t.buyerName} ← {t.sellerTeamName ?? "Subasta"} ·{" "}
                    {t.transferType === "clause"
                      ? "Cláusula"
                      : t.transferType === "icon_auction"
                        ? "Subasta"
                        : "Oferta"}
                  </p>
                </div>
                <p className="text-[#22C55E] text-sm font-bold shrink-0">
                  {fmt(t.amount)}
                </p>
              </div>
            ))}
          </div>
        </motion.div>
      )}

      {adminToken && (
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, delay: 0.6 }}
          className="flex flex-col items-center gap-3 max-w-md mx-auto"
        >
          {actionError && (
            <p className="text-[#EF4444] text-xs">{actionError}</p>
          )}
          <button
            onClick={doClose}
            disabled={closing}
            className="w-full py-3.5 rounded-2xl bg-[#22C55E] hover:bg-[#16A34A] text-white font-semibold text-sm transition-colors cursor-pointer disabled:opacity-40"
          >
            {closing ? "Cerrando…" : "Cerrar Mercado y volver al Lobby"}
          </button>
        </motion.div>
      )}
      {!adminToken && (
        <p className="text-center text-[#9CA3AF] text-sm mt-4">
          Esperando que el administrador cierre el mercado.
        </p>
      )}
    </motion.div>
  );
}

function StatBox({
  label,
  value,
  highlight,
}: {
  label: string;
  value: string;
  highlight?: boolean;
}) {
  return (
    <div className="bg-[#0D0F14] rounded-xl px-3 py-2.5">
      <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mb-1">
        {label}
      </p>
      <p
        className={`text-sm font-bold ${highlight ? "text-[#EF4444]" : "text-[#F3F4F6]"}`}
      >
        {value}
      </p>
    </div>
  );
}

function EmptyCard({
  icon,
  title,
  sub,
}: {
  icon: string;
  title: string;
  sub: string;
}) {
  return (
    <div className="bg-[#131722] rounded-2xl border border-white/6 p-10 max-w-sm w-full text-center">
      <p className="text-3xl mb-3">{icon}</p>
      <p className="text-[#F3F4F6] font-semibold">{title}</p>
      <p className="text-[#9CA3AF] text-sm mt-1">{sub}</p>
    </div>
  );
}

function ShieldIcon({
  size = 14,
  filled = false,
}: {
  size?: number;
  filled?: boolean;
}) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={filled ? "#3B82F6" : "none"}
      stroke={filled ? "#3B82F6" : "#9CA3AF"}
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
    </svg>
  );
}
