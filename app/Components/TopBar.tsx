"use client";

import Link from "next/link";
import { useSyncExternalStore } from "react";
import {
  getLastTournamentCode,
  getDisplayName,
  getTeamCrest,
  getTournamentStatus,
  getMarketOpen,
  getNavBadge,
  type NavBadge as NavBadgeType,
} from "@/lib/tokenStorage";

// ── Snapshot ────────────────────────────────────────────────────────────────────

interface TopBarState {
  has: boolean;
  displayName: string | null;
  teamCrest: string | null;
  status: string | null;
  marketActive: boolean;
  leagueActive: boolean;
  totalBadges: number;
}

let _prev: TopBarState | null = null;

function getTopBarSnapshot(): TopBarState {
  const code = getLastTournamentCode();
  const displayName = code ? getDisplayName(code) : null;
  const teamCrest = code ? getTeamCrest(code) : null;
  const status = code ? getTournamentStatus(code) : null;
  const marketOpen = code ? getMarketOpen(code) : false;

  const marketActive = status === "market" || marketOpen;
  const leagueActive = status === "league" || status === "complete";

  const mb = code ? getNavBadge(code, "market") : null;
  const tb = code ? getNavBadge(code, "torneo") : null;
  const fb = code ? getNavBadge(code, "feed") : null;
  const totalBadges = (mb?.count ?? 0) + (tb?.count ?? 0) + (fb?.count ?? 0);

  const next: TopBarState = {
    has: !!code,
    displayName,
    teamCrest,
    status,
    marketActive,
    leagueActive,
    totalBadges,
  };

  if (
    _prev &&
    _prev.has === next.has &&
    _prev.displayName === next.displayName &&
    _prev.teamCrest === next.teamCrest &&
    _prev.status === next.status &&
    _prev.marketActive === next.marketActive &&
    _prev.leagueActive === next.leagueActive &&
    _prev.totalBadges === next.totalBadges
  )
    return _prev;

  _prev = next;
  return next;
}

const SERVER_TOPBAR: TopBarState = {
  has: false,
  displayName: null,
  teamCrest: null,
  status: null,
  marketActive: false,
  leagueActive: false,
  totalBadges: 0,
};

// ── Status config ───────────────────────────────────────────────────────────────

function statusConfig(s: string | null): { label: string; color: string }[] {
  const pills: { label: string; color: string }[] = [];

  switch (s) {
    case "lobby":
      pills.push({ label: "Lobby", color: "#22C55E" });
      break;
    case "draft":
      pills.push({ label: "Draft", color: "#F59E0B" });
      break;
    case "market":
      pills.push({ label: "Mercado", color: "#8B5CF6" });
      break;
    case "league":
      pills.push({ label: "Liga", color: "#3B82F6" });
      break;
    case "complete":
      pills.push({ label: "Finalizado", color: "#9CA3AF" });
      break;
  }

  return pills;
}

// ── Main component ──────────────────────────────────────────────────────────────

export default function TopBar() {
  const bar = useSyncExternalStore(
    (cb) => {
      window.addEventListener("mercatto:store-change", cb);
      window.addEventListener("storage", cb);
      return () => {
        window.removeEventListener("mercatto:store-change", cb);
        window.removeEventListener("storage", cb);
      };
    },
    getTopBarSnapshot,
    () => SERVER_TOPBAR,
  );

  const basePills = statusConfig(bar.status);

  // In hybrid mode (league + market open), show both pills
  const isHybrid = bar.marketActive && bar.leagueActive;
  const pills = isHybrid
    ? [
        { label: "Mercado", color: "#8B5CF6" },
        { label: "Liga", color: "#3B82F6" },
      ]
    : basePills;

  return (
    <header className="sticky top-0 z-20 border-b border-white/6 bg-[#0D0F14]/95 backdrop-blur-xl lg:hidden">
      <div className="flex items-center justify-between h-14 px-4">
        {/* Left: Logo + status pills */}
        <div className="flex items-center gap-2 min-w-0">
          <Link href="/" className="flex items-center gap-2 shrink-0">
            <div className="w-7 h-7 rounded-lg bg-[#8B5CF6] flex items-center justify-center shadow-lg shadow-[#8B5CF6]/20">
              <svg width="12" height="12" viewBox="0 0 14 14" fill="none">
                <path
                  d="M7 1L9.5 5.5H13L9.5 8.5L11 13L7 10.5L3 13L4.5 8.5L1 5.5H4.5L7 1Z"
                  fill="white"
                />
              </svg>
            </div>
            <span className="text-[#F3F4F6] font-semibold tracking-widest text-[11px]">
              MERCATTO
            </span>
          </Link>

          {bar.has &&
            pills.map((pill) => (
              <span
                key={pill.label}
                className="text-[9px] font-bold px-2 py-0.5 rounded-full uppercase tracking-wider shrink-0 transition-all duration-300"
                style={{
                  color: pill.color,
                  background: `${pill.color}15`,
                  border: `1px solid ${pill.color}25`,
                }}
              >
                {pill.label}
              </span>
            ))}
        </div>

        {/* Right: Bell + Avatar */}
        <div className="flex items-center gap-2.5">
          {bar.has && bar.totalBadges > 0 && (
            <div className="relative w-8 h-8 flex items-center justify-center rounded-lg bg-[#131722] border border-white/6">
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#9CA3AF"
                strokeWidth="1.75"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9" />
                <path d="M13.73 21a2 2 0 0 1-3.46 0" />
              </svg>
              <span className="absolute -top-1 -right-1 min-w-4 h-4 rounded-full bg-[#EF4444] flex items-center justify-center text-[9px] font-black text-white px-1 ring-2 ring-[#0D0F14]">
                {bar.totalBadges > 99 ? "99+" : bar.totalBadges}
              </span>
            </div>
          )}

          {bar.has && (
            <div className="flex items-center">
              {bar.teamCrest ? (
                <img
                  src={bar.teamCrest}
                  alt=""
                  className="w-7 h-7 object-contain"
                />
              ) : bar.displayName ? (
                <div className="w-7 h-7 rounded-full bg-linear-to-br from-[#8B5CF6] to-[#6D28D9] flex items-center justify-center">
                  <span className="text-white text-[10px] font-bold">
                    {bar.displayName.charAt(0).toUpperCase()}
                  </span>
                </div>
              ) : null}
            </div>
          )}
        </div>
      </div>
    </header>
  );
}
