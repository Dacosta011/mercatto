"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import { getBrowserClient } from "@/lib/supabase-browser";
import RollingNumber from "./RollingNumber";

// ── Types ────────────────────────────────────────────────────────────────────

interface IconInfo {
  id: string; name: string; ovr: number;
  position: string; nation: string;
  minBid: number; headshotUrl: string | null;
}

interface BidEntry {
  memberId: string; memberName: string;
  amount: number; passed: boolean; createdAt: string;
}

interface MemberInfo {
  id: string; displayName: string; budget: number; purchasesUsed: number;
}

interface AuctionState {
  id: string;
  phase: "vote_activation" | "vote_icon" | "bidding" | "finished" | "skipped";
  roundNum: number;
  presentedIcons: IconInfo[];
  activationVotes: { memberId: string; vote: boolean }[];
  activationVoteCount: number;
  selectedIcon: IconInfo | null;
  selectionVotes: { memberId: string; iconId: string }[];
  selectionVoteCount: number;
  highestBid: number;
  highestBidderId: string | null;
  highestBidderName: string | null;
  currentBidderId: string | null;
  currentBidderName: string | null;
  bidderOrder: string[];
  consecutivePasses: number;
  bids: BidEntry[];
  winnerId: string | null;
  winnerName: string | null;
  finalAmount: number | null;
}

interface IconAuctionData {
  auction: AuctionState | null;
  totalMembers: number;
  members: MemberInfo[];
  myVoteActivation: boolean | null;
  myVoteIcon: string | null;
  myIconWon: boolean;
  isAdmin: boolean;
  rerollVoteCount: number;
  myRerollVote: boolean;
}

interface Props {
  code: string;
  token: string;
  adminToken: string | null;
  myMemberId: string;
  sessionId: string | null;
  currentRound: number | null;
  onFinished: () => void; // called when auction is done/skipped so parent can proceed
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function fmt(v: number): string {
  if (!v) return "€0";
  if (v >= 1_000_000_000) return `€${(v / 1_000_000_000).toFixed(1)}B`;
  if (v >= 1_000_000) return `€${(v / 1_000_000).toFixed(0)}M`;
  if (v >= 1_000) return `€${(v / 1_000).toFixed(0)}K`;
  return `€${v}`;
}

// ── Icon Card visual ──────────────────────────────────────────────────────────

function getTierColor(ovr: number) {
  return ovr >= 95 ? "#F59E0B" : ovr >= 92 ? "#C084FC" : ovr >= 89 ? "#60A5FA" : "#34D399";
}

function IconCard({ icon, selected, onClick, votes, myVote, compact }: {
  icon: IconInfo;
  selected?: boolean;
  onClick?: () => void;
  votes?: number;
  myVote?: boolean;
  compact?: boolean;
}) {
  const tierColor = getTierColor(icon.ovr);

  return (
    <motion.div
      whileHover={onClick ? { y: -4, scale: 1.02 } : {}}
      whileTap={onClick ? { scale: 0.97 } : {}}
      onClick={onClick}
      className={`relative flex flex-col overflow-hidden rounded-2xl transition-all duration-200 ${onClick ? "cursor-pointer" : ""}`}
      style={{
        background: selected
          ? `linear-gradient(160deg, ${tierColor}20 0%, #131722 60%)`
          : `linear-gradient(160deg, ${tierColor}0a 0%, #131722 70%)`,
        border: selected ? `2px solid ${tierColor}90` : `1px solid rgba(255,255,255,0.07)`,
        boxShadow: selected ? `0 0 32px ${tierColor}40, 0 8px 32px #00000060` : `0 2px 16px #00000040`,
      }}>

      {/* Top accent bar */}
      <div className="h-1 w-full shrink-0" style={{ background: `linear-gradient(90deg, ${tierColor}, ${tierColor}40)` }} />

      <div className={`flex flex-col items-center ${compact ? "gap-2 p-4" : "gap-3.5 p-5"} flex-1`}>
        {/* ICON label + OVR row */}
        <div className="flex items-center justify-between w-full">
          <span className={`${compact ? "text-[9px]" : "text-[11px]"} font-black uppercase tracking-[0.18em]`} style={{ color: tierColor }}>
            ★ Ícono
          </span>
          <span className={`${compact ? "text-xl" : "text-2xl"} font-black leading-none`} style={{ color: tierColor }}>
            {icon.ovr}
          </span>
        </div>

        {/* Headshot */}
        <div className={`${compact ? "w-20 h-20" : "w-28 h-28"} rounded-2xl overflow-hidden shrink-0 flex items-center justify-center`}
          style={{ background: `${tierColor}10`, border: `1.5px solid ${tierColor}30` }}>
          {icon.headshotUrl ? (
            <img src={icon.headshotUrl} alt={icon.name}
              className="w-full h-full object-contain object-bottom" />
          ) : (
            <span className={`${compact ? "text-3xl" : "text-4xl"} font-black`} style={{ color: tierColor }}>
              {icon.name.charAt(0)}
            </span>
          )}
        </div>

        {/* Name */}
        <p className={`text-[#F3F4F6] ${compact ? "text-sm" : "text-base"} font-bold leading-tight truncate text-center w-full`}>{icon.name}</p>

        {/* Position badge */}
        <div className="flex items-center gap-2">
          <span className={`px-2.5 py-0.5 rounded-md ${compact ? "text-[10px]" : "text-xs"} font-black`}
            style={{ background: `${tierColor}20`, color: tierColor, border: `1px solid ${tierColor}35` }}>
            {icon.position}
          </span>
          <span className={`text-[#9CA3AF] ${compact ? "text-[10px]" : "text-xs"}`}>{icon.nation}</span>
        </div>

        {/* Min bid chip */}
        <div className={`px-4 ${compact ? "py-1.5" : "py-2"} rounded-xl ${compact ? "text-[11px]" : "text-sm"} font-bold w-full text-center`}
          style={{ background: `${tierColor}15`, color: tierColor, border: `1px solid ${tierColor}30` }}>
          Mín. {fmt(icon.minBid)}
        </div>
      </div>

      {/* My vote checkmark */}
      {myVote && (
        <div className="absolute top-3 right-3 w-6 h-6 rounded-full flex items-center justify-center"
          style={{ background: "#22C55E", boxShadow: "0 2px 8px #22C55E60" }}>
          <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="20 6 9 17 4 12"/>
          </svg>
        </div>
      )}

      {/* Vote count */}
      {votes !== undefined && votes > 0 && !myVote && (
        <div className="absolute top-3 right-3 w-6 h-6 rounded-full bg-[#8B5CF6] flex items-center justify-center text-white text-[10px] font-black"
          style={{ boxShadow: "0 2px 8px #8B5CF660" }}>
          {votes}
        </div>
      )}
    </motion.div>
  );
}

// ── Bid History ───────────────────────────────────────────────────────────────

function BidTimeline({ bids, members }: { bids: BidEntry[]; members: MemberInfo[] }) {
  const memberById: Record<string, MemberInfo> = {};
  for (const m of members) memberById[m.id] = m;

  return (
    <div className="flex flex-col gap-2">
      {bids.map((b, i) => (
        <motion.div key={i}
          initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }}
          transition={{ delay: i * 0.03 }}
          className={`flex items-center gap-3 px-3 py-2 rounded-xl text-sm ${
            b.passed
              ? "bg-[#1A1F2E]/60 text-[#9CA3AF]"
              : "bg-[#8B5CF6]/8 border border-[#8B5CF6]/20"
          }`}>
          <div className={`w-2 h-2 rounded-full shrink-0 ${b.passed ? "bg-[#4B5563]" : "bg-[#8B5CF6]"}`} />
          <span className="font-semibold text-[#F3F4F6] text-xs">{b.memberName}</span>
          {b.passed
            ? <span className="text-[#9CA3AF] text-[10px]">pasó</span>
            : <span className="text-[#8B5CF6] font-bold text-xs ml-auto">{fmt(b.amount)}</span>
          }
        </motion.div>
      ))}
    </div>
  );
}

// ── Main Component ────────────────────────────────────────────────────────────

export default function IconAuction({ code, token, adminToken, myMemberId, sessionId, currentRound, onFinished }: Props) {
  const [data, setData] = useState<IconAuctionData | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState(false);
  const [bidAmount, setBidAmount] = useState("");
  const [confirmVote, setConfirmVote] = useState<IconInfo | null>(null);
  const [initiating, setInitiating] = useState(false);
  const [rerollLoading, setRerollLoading] = useState(false);
  const channelRef       = useRef<any>(null);
  const fetchingRef      = useRef(false);
  const pendingFetchRef  = useRef(false);
  const autoRetiredRef   = useRef(false); // prevents firing auto-retire twice

  const authHeader = { Authorization: `Bearer ${adminToken || token}` };

  const fetchData = useCallback(async (silent = false) => {
    if (!code || (!token && !adminToken)) return;
    if (fetchingRef.current) {
      pendingFetchRef.current = true;
      return;
    }
    fetchingRef.current = true;
    if (!silent) setLoading(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/market/icon-auction`, {
        headers: { Authorization: `Bearer ${adminToken || token}` },
      });
      if (res.ok) setData(await res.json());
    } finally {
      fetchingRef.current = false;
      if (!silent) setLoading(false);
      if (pendingFetchRef.current) {
        pendingFetchRef.current = false;
        fetchData(true);
      }
    }
  }, [code, token, adminToken]);

  // Initial fetch + Realtime
  useEffect(() => {
    if (!sessionId) return;
    fetchData(false);

    const supabase = getBrowserClient();
    if (channelRef.current) supabase.removeChannel(channelRef.current);

    channelRef.current = supabase
      .channel(`icon-auction:${sessionId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "icon_auctions" }, () => fetchData(true))
      .on("postgres_changes", { event: "*", schema: "public", table: "icon_activation_votes" }, () => fetchData(true))
      .on("postgres_changes", { event: "*", schema: "public", table: "icon_selection_votes" }, () => fetchData(true))
      .on("postgres_changes", { event: "*", schema: "public", table: "icon_bids" }, () => fetchData(true))
      .subscribe();

    return () => {
      if (channelRef.current) { supabase.removeChannel(channelRef.current); channelRef.current = null; }
    };
  }, [sessionId, fetchData]);

  // ── Auto-retire when budget is insufficient ─────────────────────────────
  const _auction = data?.auction;
  const _me = data?.members.find((m) => m.id === myMemberId);
  const _amIActive = _auction?.phase === "bidding" && (_auction?.bidderOrder?.includes(myMemberId ?? "") ?? false);
  const _isMyTurn = _auction?.currentBidderId === myMemberId;
  const _minNextBid = (_auction?.highestBid ?? 0) > 0
    ? (_auction?.highestBid ?? 0) + 5_000_000
    : (_auction?.selectedIcon?.minBid ?? 120_000_000);
  const _cantAfford = _isMyTurn && _amIActive && (_me?.budget ?? 0) < _minNextBid;

  useEffect(() => {
    if (!_cantAfford || !token || autoRetiredRef.current) return;
    autoRetiredRef.current = true;
    fetch(`/api/tournaments/${code}/market/icon-auction/pass`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
    }).then(() => {
      autoRetiredRef.current = false;
      fetchData(true);
    }).catch(() => { autoRetiredRef.current = false; });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [_cantAfford]);

  // Reset guard whenever it's no longer my turn (new turn cycle)
  useEffect(() => {
    if (!_isMyTurn) autoRetiredRef.current = false;
  }, [_isMyTurn]);

  // Don't render if no auction
  if (loading && !data) return null;
  if (!data?.auction) return null;

  const { auction, totalMembers, members, myVoteActivation, myVoteIcon, myIconWon, isAdmin, rerollVoteCount, myRerollVote } = data;
  const me = members.find((m) => m.id === myMemberId);

  // ── Phase: Skipped ────────────────────────────────────────────────────────
  if (auction.phase === "skipped") {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#0D0F14]/95 backdrop-blur-md">
        <motion.div initial={{ opacity: 0, scale: 0.92 }} animate={{ opacity: 1, scale: 1 }}
          className="bg-[#131722] rounded-3xl border border-white/8 p-12 max-w-md w-full mx-4 text-center flex flex-col items-center gap-6">
          <div className="w-20 h-20 rounded-3xl bg-[#9CA3AF]/10 border border-[#9CA3AF]/20 flex items-center justify-center">
            <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="10"/><line x1="15" y1="9" x2="9" y2="15"/><line x1="9" y1="9" x2="15" y2="15"/>
            </svg>
          </div>
          <div>
            <p className="text-[#F3F4F6] text-xl font-bold mb-2">Sin subasta esta ronda</p>
            <p className="text-[#9CA3AF] text-sm">La mayoría votó por no activar la subasta de ícono.</p>
          </div>
          {(isAdmin || !isAdmin) && (
            <button onClick={onFinished}
              className="px-8 py-3 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white font-semibold text-sm transition-colors cursor-pointer">
              Continuar
            </button>
          )}
        </motion.div>
      </div>
    );
  }

  // ── Phase: Finished ───────────────────────────────────────────────────────
  if (auction.phase === "finished") {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#0D0F14]/95 backdrop-blur-md">
        <motion.div initial={{ opacity: 0, scale: 0.92 }} animate={{ opacity: 1, scale: 1 }}
          className="bg-[#131722] rounded-3xl border border-white/8 p-10 max-w-lg w-full mx-4 text-center flex flex-col items-center gap-6">
          {auction.winnerId ? (
            <>
              <motion.div initial={{ scale: 0 }} animate={{ scale: 1 }} transition={{ type: "spring", delay: 0.2 }}
                className="w-24 h-24 rounded-3xl flex items-center justify-center text-5xl"
                style={{ background: "linear-gradient(135deg, #F59E0B20, #F59E0B10)", border: "1px solid #F59E0B40" }}>
                🏆
              </motion.div>
              <div>
                <p className="text-[#F59E0B] text-xs uppercase tracking-widest font-bold mb-2">¡Ícono adjudicado!</p>
                <p className="text-[#F3F4F6] text-2xl font-black">{auction.winnerName}</p>
                <p className="text-[#9CA3AF] text-sm mt-1">se lleva a <span className="text-[#F3F4F6] font-semibold">{auction.selectedIcon?.name}</span></p>
              </div>
              <div className="bg-[#0D0F14] rounded-2xl px-8 py-4 text-center">
                <p className="text-[#9CA3AF] text-xs mb-1">Puja final</p>
                <p className="text-[#8B5CF6] text-3xl font-black">{fmt(auction.finalAmount ?? 0)}</p>
              </div>
              {auction.selectedIcon && (
                <IconCard icon={auction.selectedIcon} />
              )}
            </>
          ) : (
            <>
              <div className="w-20 h-20 rounded-3xl bg-[#9CA3AF]/10 border border-[#9CA3AF]/20 flex items-center justify-center text-4xl">
                🏷️
              </div>
              <div>
                <p className="text-[#F3F4F6] text-xl font-bold mb-2">Sin ganador</p>
                <p className="text-[#9CA3AF] text-sm">Nadie pujó por el ícono. Continúa la siguiente ronda.</p>
              </div>
            </>
          )}
          <button onClick={onFinished}
            className="px-10 py-3.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white font-semibold text-sm transition-colors cursor-pointer">
            Continuar
          </button>
        </motion.div>
      </div>
    );
  }

  // ── Phase: Vote Activation ────────────────────────────────────────────────
  if (auction.phase === "vote_activation") {
    const alreadyVoted = myVoteActivation !== null;
    const yesCount = auction.activationVotes.filter((v) => v.vote).length;
    const noCount = auction.activationVotes.filter((v) => !v.vote).length;

    const doVote = async (vote: boolean) => {
      if (alreadyVoted || actionLoading) return;
      setActionLoading(true);
      try {
        await fetch(`/api/tournaments/${code}/market/icon-auction/vote-activation`, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
          body: JSON.stringify({ vote }),
        });
        await fetchData(true);
      } finally { setActionLoading(false); }
    };

    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#0D0F14]/95 backdrop-blur-md">
        <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }}
          className="bg-[#131722] rounded-3xl border border-white/8 p-10 max-w-md w-full mx-4 flex flex-col items-center gap-8">

          {/* Header */}
          <div className="text-center">
            <div className="w-14 h-14 rounded-2xl bg-[#F59E0B]/10 border border-[#F59E0B]/20 flex items-center justify-center text-2xl mx-auto mb-4">
              ⭐
            </div>
            <p className="text-[#F59E0B] text-xs uppercase tracking-widest font-bold mb-2">
              Ronda {auction.roundNum}
            </p>
            <h2 className="text-[#F3F4F6] text-2xl font-black">¿Subasta de Ícono?</h2>
            <p className="text-[#9CA3AF] text-sm mt-2">
              ¿Quieres activar una subasta de ícono legendario?
            </p>
          </div>

          {/* Progress */}
          <div className="w-full bg-[#0D0F14] rounded-2xl p-4 flex items-center justify-between">
            <span className="text-[#9CA3AF] text-sm">Votos</span>
            <span className="text-[#F3F4F6] font-bold">{auction.activationVoteCount}/{totalMembers}</span>
          </div>

          {/* Vote buttons or waiting state */}
          {!alreadyVoted ? (
            <div className="w-full flex gap-4">
              <motion.button whileTap={{ scale: 0.95 }} onClick={() => doVote(true)}
                disabled={actionLoading}
                className="flex-1 py-5 rounded-2xl border-2 border-[#22C55E]/30 bg-[#22C55E]/8 text-[#22C55E] font-bold text-lg flex flex-col items-center gap-1 transition-all cursor-pointer hover:border-[#22C55E]/60 hover:bg-[#22C55E]/15 disabled:opacity-40">
                <span className="text-3xl">✅</span>
                <span className="text-sm">Sí, activar</span>
              </motion.button>
              <motion.button whileTap={{ scale: 0.95 }} onClick={() => doVote(false)}
                disabled={actionLoading}
                className="flex-1 py-5 rounded-2xl border-2 border-[#EF4444]/30 bg-[#EF4444]/8 text-[#EF4444] font-bold text-lg flex flex-col items-center gap-1 transition-all cursor-pointer hover:border-[#EF4444]/60 hover:bg-[#EF4444]/15 disabled:opacity-40">
                <span className="text-3xl">❌</span>
                <span className="text-sm">No, saltar</span>
              </motion.button>
            </div>
          ) : (
            <div className="w-full flex flex-col items-center gap-4">
              <div className={`px-6 py-3 rounded-xl border font-semibold text-sm ${
                myVoteActivation
                  ? "bg-[#22C55E]/10 border-[#22C55E]/30 text-[#22C55E]"
                  : "bg-[#EF4444]/10 border-[#EF4444]/30 text-[#EF4444]"
              }`}>
                Votaste: {myVoteActivation ? "✅ Sí" : "❌ No"}
              </div>
              <p className="text-[#9CA3AF] text-sm animate-pulse">Esperando a los demás…</p>
            </div>
          )}

          {/* Live vote split */}
          {auction.activationVoteCount > 0 && (
            <div className="w-full flex gap-3">
              <div className="flex-1 bg-[#22C55E]/8 rounded-xl p-3 text-center">
                <p className="text-[#22C55E] text-xl font-black">{yesCount}</p>
                <p className="text-[#9CA3AF] text-[10px]">Sí</p>
              </div>
              <div className="flex-1 bg-[#EF4444]/8 rounded-xl p-3 text-center">
                <p className="text-[#EF4444] text-xl font-black">{noCount}</p>
                <p className="text-[#9CA3AF] text-[10px]">No</p>
              </div>
            </div>
          )}
        </motion.div>
      </div>
    );
  }

  // ── Phase: Vote Icon ──────────────────────────────────────────────────────
  if (auction.phase === "vote_icon") {
    const alreadyVoted = myVoteIcon !== null;

    const voteCounts: Record<string, number> = {};
    for (const v of auction.selectionVotes) {
      voteCounts[v.iconId] = (voteCounts[v.iconId] ?? 0) + 1;
    }

    const doVoteIcon = async (icon: IconInfo) => {
      if (alreadyVoted || actionLoading) return;
      setActionLoading(true);
      try {
        await fetch(`/api/tournaments/${code}/market/icon-auction/vote-icon`, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
          body: JSON.stringify({ iconId: icon.id }),
        });
        setConfirmVote(null);
        await fetchData(true);
      } finally { setActionLoading(false); }
    };

    const doReroll = async () => {
      if (actionLoading || rerollLoading) return;
      setRerollLoading(true);
      try {
        const res = await fetch(`/api/tournaments/${code}/market/icon-auction/reroll`, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        });
        if (res.ok) await fetchData(true);
      } finally { setRerollLoading(false); }
    };

    const confirmTierColor = confirmVote ? getTierColor(confirmVote.ovr) : "#34D399";

    return (
      <div className="fixed inset-0 z-50 flex flex-col bg-[#0D0F14] overflow-y-auto">
        {/* Top bar */}
        <div className="shrink-0 flex items-center justify-between px-8 py-5 border-b border-white/5">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-xl bg-[#F59E0B]/10 border border-[#F59E0B]/20 flex items-center justify-center">
              <span className="text-sm">⭐</span>
            </div>
            <div>
              <p className="text-[#F59E0B] text-[10px] uppercase tracking-widest font-bold">
                Ronda {auction.roundNum} — Subasta de Ícono
              </p>
              <h2 className="text-[#F3F4F6] text-base font-black leading-tight">Elige tu Ícono</h2>
            </div>
          </div>

          <div className="flex items-center gap-4">
            {/* Reroll button */}
            {!alreadyVoted && (
              <button onClick={doReroll} disabled={rerollLoading || myRerollVote}
                className={`flex items-center gap-2 px-4 py-2 rounded-xl text-xs font-semibold transition-all ${
                  myRerollVote
                    ? "opacity-60 cursor-default"
                    : "cursor-pointer hover:bg-[#F59E0B]/15 disabled:opacity-40"
                }`}
                style={{ background: myRerollVote ? "#F59E0B18" : "#F59E0B10", color: "#F59E0B", border: `1px solid ${myRerollVote ? "#F59E0B50" : "#F59E0B30"}` }}>
                {rerollLoading ? (
                  <svg className="animate-spin w-3.5 h-3.5" viewBox="0 0 24 24" fill="none"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/></svg>
                ) : myRerollVote ? (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                ) : (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21.5 2v6h-6"/><path d="M2.5 22v-6h6"/><path d="M2 11.5a10 10 0 0 1 18.8-4.3"/><path d="M22 12.5a10 10 0 0 1-18.8 4.3"/></svg>
                )}
                {myRerollVote ? "Votado" : "Reroll"} <span className="px-1.5 py-0.5 rounded bg-[#F59E0B]/20 text-[10px]">{rerollVoteCount}/{Math.ceil(totalMembers / 2)}</span>
              </button>
            )}

            {/* Vote progress */}
            <div className="flex items-center gap-3">
              <div className="text-right">
                <p className="text-[#F3F4F6] text-sm font-bold">
                  {auction.selectionVoteCount}
                  <span className="text-[#4B5563]">/{totalMembers}</span>
                </p>
                <p className="text-[#6B7280] text-[10px] uppercase tracking-wider">votos</p>
              </div>
              <div className="flex gap-1">
                {Array.from({ length: totalMembers }).map((_, i) => (
                  <div key={i} className="w-1.5 h-5 rounded-full transition-all duration-300"
                    style={{ background: i < auction.selectionVoteCount ? "#8B5CF6" : "rgba(255,255,255,0.08)" }} />
                ))}
              </div>
            </div>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 flex flex-col items-center justify-center px-8 py-10">
          <AnimatePresence mode="wait">
            {confirmVote ? (
              /* ── Expanded card confirmation ──────────────────────────── */
              <motion.div
                key="confirm"
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.9 }}
                transition={{ type: "spring", damping: 25, stiffness: 300 }}
                className="flex flex-col items-center gap-6 w-full max-w-sm"
              >
                {/* Large hero card */}
                <motion.div
                  className="w-full rounded-3xl overflow-hidden relative"
                  style={{
                    background: `linear-gradient(160deg, ${confirmTierColor}18 0%, #131722 55%)`,
                    border: `2px solid ${confirmTierColor}60`,
                    boxShadow: `0 0 60px ${confirmTierColor}25, 0 16px 48px #00000060`,
                  }}>
                  <div className="h-1.5 w-full" style={{ background: `linear-gradient(90deg, ${confirmTierColor}, ${confirmTierColor}40)` }} />
                  <div className="flex flex-col items-center gap-4 p-8">
                    {/* OVR + Label */}
                    <div className="flex items-center justify-between w-full">
                      <span className="text-xs font-black uppercase tracking-[0.2em]" style={{ color: confirmTierColor }}>
                        ★ Ícono
                      </span>
                      <span className="text-4xl font-black" style={{ color: confirmTierColor }}>
                        {confirmVote.ovr}
                      </span>
                    </div>

                    {/* Large headshot */}
                    <div className="w-40 h-40 rounded-3xl overflow-hidden flex items-center justify-center"
                      style={{ background: `${confirmTierColor}10`, border: `2px solid ${confirmTierColor}30` }}>
                      {confirmVote.headshotUrl ? (
                        <img src={confirmVote.headshotUrl} alt={confirmVote.name}
                          className="w-full h-full object-contain object-bottom" />
                      ) : (
                        <span className="text-6xl font-black" style={{ color: confirmTierColor }}>
                          {confirmVote.name.charAt(0)}
                        </span>
                      )}
                    </div>

                    {/* Name */}
                    <p className="text-[#F3F4F6] text-2xl font-black text-center">{confirmVote.name}</p>

                    {/* Position + Nation */}
                    <div className="flex items-center gap-3">
                      <span className="px-3 py-1 rounded-lg text-sm font-black"
                        style={{ background: `${confirmTierColor}20`, color: confirmTierColor, border: `1px solid ${confirmTierColor}35` }}>
                        {confirmVote.position}
                      </span>
                      <span className="text-[#9CA3AF] text-sm">{confirmVote.nation}</span>
                    </div>

                    {/* Min bid */}
                    <div className="px-6 py-2.5 rounded-xl text-sm font-bold w-full text-center"
                      style={{ background: `${confirmTierColor}12`, color: confirmTierColor, border: `1px solid ${confirmTierColor}25` }}>
                      Mín. {fmt(confirmVote.minBid)}
                    </div>
                  </div>
                </motion.div>

                {/* Confirmation text */}
                <div className="text-center">
                  <p className="text-[#F3F4F6] font-bold text-base">¿Confirmar voto por este ícono?</p>
                  <p className="text-[#6B7280] text-xs mt-1">Solo puedes votar una vez, elige bien</p>
                </div>

                {/* Action buttons */}
                <div className="flex gap-3 w-full">
                  <motion.button whileTap={{ scale: 0.95 }}
                    onClick={() => setConfirmVote(null)}
                    className="flex-1 py-3.5 rounded-xl border border-white/10 text-[#9CA3AF] text-sm font-semibold cursor-pointer hover:bg-[#1A1F2E] transition-colors">
                    Volver
                  </motion.button>
                  <motion.button whileTap={{ scale: 0.95 }}
                    onClick={() => doVoteIcon(confirmVote)} disabled={actionLoading}
                    className="flex-1 py-3.5 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white text-sm font-bold cursor-pointer transition-colors disabled:opacity-40 flex items-center justify-center gap-2"
                    style={{ boxShadow: "0 4px 20px #8B5CF640" }}>
                    {actionLoading ? (
                      <><svg className="animate-spin w-4 h-4" viewBox="0 0 24 24" fill="none"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/></svg>Votando...</>
                    ) : (
                      <>
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
                        Confirmar voto
                      </>
                    )}
                  </motion.button>
                </div>
              </motion.div>
            ) : (
              /* ── Grid of icons ──────────────────────────────────────── */
              <motion.div
                key="grid"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="flex flex-col items-center w-full"
              >
                <p className="text-[#6B7280] text-sm mb-8">
                  {alreadyVoted ? "Voto registrado — esperando a los demás..." : "Selecciona el ícono que quieres subastar"}
                </p>

                <div className="grid grid-cols-3 gap-5 w-full max-w-4xl">
                  {auction.presentedIcons.map((icon, i) => (
                    <motion.div
                      key={icon.id}
                      initial={{ opacity: 0, y: 16 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ delay: i * 0.05 }}
                    >
                      <IconCard
                        icon={icon}
                        selected={myVoteIcon === icon.id}
                        onClick={!alreadyVoted ? () => setConfirmVote(icon) : undefined}
                        votes={voteCounts[icon.id]}
                        myVote={myVoteIcon === icon.id}
                      />
                    </motion.div>
                  ))}
                </div>

                {alreadyVoted && (
                  <motion.div initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }}
                    className="mt-8 flex items-center gap-2 px-5 py-3 rounded-xl bg-[#8B5CF6]/8 border border-[#8B5CF6]/20">
                    <div className="w-1.5 h-1.5 rounded-full bg-[#8B5CF6] animate-pulse" />
                    <span className="text-[#9CA3AF] text-sm">Esperando a los demás participantes...</span>
                  </motion.div>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
    );
  }

  // ── Phase: Bidding ────────────────────────────────────────────────────────
  if (auction.phase === "bidding") {
    const isMyTurn = auction.currentBidderId === myMemberId;
    const amIActive = auction.bidderOrder.includes(myMemberId ?? "");
    const myBudget = me?.budget ?? 0;
    const canBid = isMyTurn && !actionLoading && (me?.purchasesUsed ?? 0) < 3 && !myIconWon;
    const minBid = auction.selectedIcon?.minBid ?? 120_000_000;
    const minNextBid = auction.highestBid > 0 ? auction.highestBid + 5_000_000 : minBid;
    const budgetOk = myBudget >= minNextBid;
    const parsedBidAmount = parseFloat(bidAmount.replace(/[^0-9.]/g, "")) * 1_000_000;
    const bidExceedsBudget = !isNaN(parsedBidAmount) && parsedBidAmount > myBudget;
    // Members not in bidder_order are eliminated
    const activeIds = new Set(auction.bidderOrder);

    const doBid = async () => {
      const parsed = parseFloat(bidAmount.replace(/[^0-9.]/g, "")) * 1_000_000;
      if (isNaN(parsed) || parsed <= 0) return;
      setActionLoading(true);
      try {
        await fetch(`/api/tournaments/${code}/market/icon-auction/bid`, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
          body: JSON.stringify({ amount: parsed }),
        });
        setBidAmount("");
        await fetchData(true);
      } finally { setActionLoading(false); }
    };

    const doPass = async () => {
      if (actionLoading) return;
      setActionLoading(true);
      try {
        const res = await fetch(`/api/tournaments/${code}/market/icon-auction/pass`, {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!res.ok) {
          // If pass fails (e.g., "not your turn"), still refresh to get latest state
          await fetchData(true);
          return;
        }
        await fetchData(true);
      } finally { setActionLoading(false); }
    };

    const quickBid = (addM: number) => {
      const base = Math.max(minNextBid / 1_000_000, parseFloat(bidAmount) || minNextBid / 1_000_000);
      setBidAmount(String(base + addM));
    };

    return (
      <div className="fixed inset-0 z-50 flex flex-col bg-[#0D0F14]/97 backdrop-blur-md overflow-hidden">
        {/* Header bar */}
        <div className="shrink-0 px-8 py-4 border-b border-white/6 flex items-center justify-between">
          <div>
            <p className="text-[#F59E0B] text-[10px] uppercase tracking-widest font-bold">Ronda {auction.roundNum} — Subasta de Ícono</p>
            <h2 className="text-[#F3F4F6] font-bold text-lg leading-tight">{auction.selectedIcon?.name}</h2>
          </div>
          <div className="flex items-center gap-3">
            {isMyTurn && (
              <motion.div animate={{ opacity: [1, 0.4, 1] }} transition={{ duration: 1.5, repeat: Infinity }}
                className="px-3 py-1.5 rounded-xl bg-[#8B5CF6]/20 border border-[#8B5CF6]/40 text-[#8B5CF6] text-xs font-bold">
                TU TURNO
              </motion.div>
            )}
            {!isMyTurn && auction.currentBidderName && (
              <div className="px-3 py-1.5 rounded-xl bg-[#1A1F2E] border border-white/6 text-[#9CA3AF] text-xs">
                Turno de <span className="text-[#F3F4F6] font-semibold">{auction.currentBidderName}</span>
              </div>
            )}
          </div>
        </div>

        <div className="flex-1 overflow-y-auto p-8">
          <div className="max-w-5xl mx-auto flex gap-6 h-full">
            {/* Left: Icon hero */}
            <div className="w-72 shrink-0 flex flex-col gap-4">
              {auction.selectedIcon && <IconCard icon={auction.selectedIcon} compact />}

              {/* Highest bid */}
              <div className="bg-[#131722] rounded-2xl border border-[#8B5CF6]/20 p-5 text-center">
                <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-2">Puja más alta</p>
                {auction.highestBid > 0 ? (
                  <>
                    <p className="text-[#8B5CF6] text-3xl font-black">
                      <RollingNumber value={auction.highestBid} format={fmt} />
                    </p>
                    <p className="text-[#9CA3AF] text-xs mt-1">{auction.highestBidderName}</p>
                  </>
                ) : (
                  <p className="text-[#4B5563] text-xl font-black">Sin pujas</p>
                )}
              </div>
            </div>

            {/* Right: Auction panel */}
            <div className="flex-1 flex flex-col gap-4">
              {/* My status */}
              <div className="grid grid-cols-2 gap-3">
                <div className="bg-[#131722] rounded-2xl border border-white/6 p-4">
                  <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Mi presupuesto</p>
                  <p className="text-[#22C55E] text-xl font-bold">
                    <RollingNumber value={me?.budget ?? 0} format={fmt} />
                  </p>
                </div>
                <div className="bg-[#131722] rounded-2xl border border-white/6 p-4">
                  <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Compras</p>
                  <div className="flex items-center gap-1.5 mt-1">
                    {[0,1,2].map((i) => (
                      <div key={i} className={`w-3 h-3 rounded-full border ${
                        i < (me?.purchasesUsed ?? 0)
                          ? "bg-[#8B5CF6] border-[#8B5CF6]"
                          : "bg-transparent border-white/20"
                      }`} />
                    ))}
                    <span className="text-[#9CA3AF] text-xs ml-1">{me?.purchasesUsed ?? 0}/3</span>
                  </div>
                </div>
              </div>

              {/* Action panel */}
              {!amIActive ? (
                // Member was eliminated (can't afford or chose to retire)
                <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 flex items-center gap-3">
                  <div className="w-8 h-8 rounded-xl bg-[#EF4444]/10 border border-[#EF4444]/20 flex items-center justify-center shrink-0">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                  </div>
                  <div>
                    <p className="text-[#EF4444] text-sm font-semibold">Retirado de la subasta</p>
                    <p className="text-[#6B7280] text-xs mt-0.5">No puedes participar más en este remate</p>
                  </div>
                </div>
              ) : isMyTurn && myIconWon ? (
                <div className="bg-[#131722] rounded-2xl border border-[#F59E0B]/20 p-5">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-lg">⭐</span>
                    <p className="text-[#F59E0B] font-semibold text-sm">Ya tienes un ícono</p>
                  </div>
                  <p className="text-[#9CA3AF] text-xs mb-4">Solo puedes ganar un ícono por mercado.</p>
                  <button onClick={doPass} disabled={actionLoading}
                    className="w-full py-3 rounded-xl bg-[#EF4444]/10 hover:bg-[#EF4444]/20 border border-[#EF4444]/30 text-[#EF4444] text-sm font-semibold cursor-pointer transition-colors disabled:opacity-40">
                    {actionLoading ? "Retirando…" : "Retirarme"}
                  </button>
                </div>
              ) : isMyTurn && !budgetOk ? (
                // On my turn but can't afford — must retire
                <div className="bg-[#131722] rounded-2xl border border-[#EF4444]/20 p-5">
                  <p className="text-[#EF4444] font-semibold text-sm mb-1">Presupuesto insuficiente</p>
                  <p className="text-[#9CA3AF] text-xs mb-4">No tienes fondos para superar la puja mínima de <span className="text-[#F3F4F6]">{fmt(minNextBid)}</span>.</p>
                  <button onClick={doPass} disabled={actionLoading}
                    className="w-full py-3 rounded-xl bg-[#EF4444]/10 hover:bg-[#EF4444]/20 border border-[#EF4444]/30 text-[#EF4444] text-sm font-semibold cursor-pointer transition-colors disabled:opacity-40">
                    {actionLoading ? "Retirando…" : "Retirarme del remate"}
                  </button>
                </div>
              ) : isMyTurn && (me?.purchasesUsed ?? 0) >= 3 ? (
                <div className="bg-[#131722] rounded-2xl border border-[#EF4444]/20 p-5">
                  <p className="text-[#EF4444] font-semibold text-sm mb-1">Límite de compras alcanzado</p>
                  <p className="text-[#9CA3AF] text-xs mb-4">Ya tienes 3 jugadores comprados este mercado.</p>
                  <button onClick={doPass} disabled={actionLoading}
                    className="w-full py-3 rounded-xl bg-[#EF4444]/10 hover:bg-[#EF4444]/20 border border-[#EF4444]/30 text-[#EF4444] text-sm font-semibold cursor-pointer transition-colors disabled:opacity-40">
                    {actionLoading ? "Retirando…" : "Retirarme del remate"}
                  </button>
                </div>
              ) : isMyTurn ? (
                <div className="bg-[#131722] rounded-2xl border border-[#8B5CF6]/30 p-5 flex flex-col gap-4">
                  <div>
                    <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-1">Puja mínima para superar</p>
                    <p className="text-[#8B5CF6] text-sm font-bold">{fmt(minNextBid)}</p>
                  </div>

                  {/* Quick bid buttons */}
                  <div className="flex gap-2">
                    {[10, 20, 50].map((add) => {
                      const resultM = Math.max(minNextBid / 1_000_000, parseFloat(bidAmount) || minNextBid / 1_000_000) + add;
                      const tooExpensive = resultM * 1_000_000 > myBudget;
                      return (
                        <button key={add} onClick={() => quickBid(add)} disabled={tooExpensive}
                          className="flex-1 py-2 rounded-lg border border-[#8B5CF6]/30 text-[#8B5CF6] text-xs font-bold cursor-pointer hover:bg-[#8B5CF6]/10 transition-colors disabled:opacity-30 disabled:cursor-not-allowed">
                          +{add}M
                        </button>
                      );
                    })}
                  </div>

                  {/* Bid amount input */}
                  <div className="flex items-center bg-[#0D0F14] rounded-xl border border-white/10 px-3 gap-2">
                    <span className="text-[#9CA3AF] text-sm">€</span>
                    <input
                      type="number"
                      value={bidAmount}
                      onKeyDown={(e) => { if (e.key === "-" || e.key === "e") e.preventDefault(); }}
                      onChange={(e) => {
                        const raw = e.target.value;
                        if (raw === "") { setBidAmount(""); return; }
                        const n = parseFloat(raw);
                        if (isNaN(n) || n < 0) return;
                        setBidAmount(raw);
                      }}
                      placeholder={`${minNextBid / 1_000_000}`}
                      className="flex-1 bg-transparent text-[#F3F4F6] text-sm py-3 outline-none"
                    />
                    <span className="text-[#9CA3AF] text-xs">M</span>
                  </div>

                  {bidExceedsBudget && (
                    <p className="text-[#EF4444] text-xs font-medium -mt-1">Supera tu presupuesto de {fmt(myBudget)}</p>
                  )}
                  {!isNaN(parsedBidAmount) && parsedBidAmount > 0 && parsedBidAmount < minNextBid && !bidExceedsBudget && (
                    <p className="text-[#F59E0B] text-xs font-medium -mt-1">La puja mínima es {fmt(minNextBid)}</p>
                  )}

                  <div className="flex gap-3">
                    <button onClick={doPass} disabled={actionLoading}
                      className="flex-1 py-3 rounded-xl bg-[#EF4444]/10 hover:bg-[#EF4444]/20 border border-[#EF4444]/30 text-[#EF4444] text-sm font-semibold cursor-pointer transition-colors disabled:opacity-40">
                      {actionLoading ? "Retirando…" : "Retirarme"}
                    </button>
                    <button onClick={doBid} disabled={!canBid || !bidAmount || actionLoading || !budgetOk || bidExceedsBudget || parsedBidAmount < minNextBid}
                      className="flex-1 py-3 rounded-xl bg-[#8B5CF6] hover:bg-[#7C3AED] text-white text-sm font-semibold cursor-pointer transition-colors disabled:opacity-40 disabled:cursor-not-allowed">
                      {actionLoading ? "Pujando…" : "Pujar"}
                    </button>
                  </div>
                </div>
              ) : (
                <div className="bg-[#131722] rounded-2xl border border-white/6 p-5 flex items-center justify-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-[#8B5CF6] animate-pulse" />
                  <p className="text-[#9CA3AF] text-sm">
                    Esperando a <span className="text-[#F3F4F6] font-semibold">{auction.currentBidderName}</span>…
                  </p>
                </div>
              )}

              {/* Bid participant status */}
              <div className="bg-[#131722] rounded-2xl border border-white/6 p-4">
                <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-3">Participantes</p>
                <div className="flex flex-wrap gap-2">
                  {members.map((m) => {
                    const isActive = activeIds.has(m.id);
                    const isCurrent = m.id === auction.currentBidderId;
                    return (
                      <div key={m.id}
                        className={`flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-medium transition-all ${
                          isCurrent
                            ? "bg-[#8B5CF6] text-white"
                            : isActive
                            ? "bg-[#1A1F2E] text-[#9CA3AF] border border-white/6"
                            : "bg-transparent text-[#4B5563] line-through border border-white/4"
                        }`}>
                        {!isActive && (
                          <svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                        )}
                        {m.displayName}
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Bid history */}
              <div className="bg-[#131722] rounded-2xl border border-white/6 p-4 flex-1 overflow-y-auto">
                <p className="text-[#9CA3AF] text-[10px] uppercase tracking-widest mb-3">Historial</p>
                {auction.bids.length === 0 ? (
                  <p className="text-[#4B5563] text-sm text-center py-4">Aún no hay pujas</p>
                ) : (
                  <BidTimeline bids={[...auction.bids].reverse()} members={members} />
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return null;
}

// ── Admin Initiate Button (rendered in market page) ───────────────────────────

export function IconAuctionInitiateButton({ code, adminToken, currentRound, auctionDone, onStarted }: {
  code: string;
  adminToken: string;
  currentRound: number;
  auctionDone?: boolean;
  onStarted: () => void;
}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const doInitiate = async () => {
    if (auctionDone) return;
    setLoading(true); setError("");
    try {
      const res = await fetch(`/api/tournaments/${code}/market/icon-auction/initiate`, {
        method: "POST",
        headers: { Authorization: `Bearer ${adminToken}` },
      });
      if (!res.ok) {
        const d = await res.json();
        setError(d.error ?? "Error");
      } else {
        onStarted();
      }
    } finally { setLoading(false); }
  };

  return (
    <div className="flex flex-col items-center gap-2">
      <button onClick={doInitiate} disabled={loading || auctionDone}
        className="w-full flex items-center justify-center gap-2 px-6 py-3 rounded-xl font-semibold text-sm transition-colors cursor-pointer disabled:opacity-40 disabled:cursor-not-allowed"
        style={{ background: "#F59E0B20", color: "#F59E0B", border: "1px solid #F59E0B40" }}>
        {loading
          ? <><svg className="animate-spin w-4 h-4" viewBox="0 0 24 24" fill="none"><circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"/><path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8z"/></svg>Iniciando…</>
          : auctionDone
          ? <><span className="text-lg">✓</span>Subasta ya realizada</>
          : <><span className="text-lg">⭐</span>Iniciar Subasta de Ícono</>
        }
      </button>
      {error && <p className="text-[#EF4444] text-xs">{error}</p>}
    </div>
  );
}
