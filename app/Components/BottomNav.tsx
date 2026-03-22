"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useSyncExternalStore } from "react";
import {
  getLastTournamentCode,
  hasTeamAssignment,
  getTournamentStatus,
  getMarketOpen,
  getNavBadge,
  type NavBadge as NavBadgeType,
} from "@/lib/tokenStorage";

// ── Snapshot ────────────────────────────────────────────────────────────────────

interface NavState {
  lobbyHref: string;
  has: boolean;
  hasTeam: boolean;
  status: string | null;
  marketActive: boolean;
  leagueActive: boolean;
  marketBadge: NavBadgeType | null;
  torneoBadge: NavBadgeType | null;
  feedBadge: NavBadgeType | null;
}

let _prev: NavState | null = null;

function getNavSnapshot(): NavState {
  const code = getLastTournamentCode();
  const hasTeam = code ? hasTeamAssignment(code) : false;
  const status = code ? getTournamentStatus(code) : null;
  const marketOpen = code ? getMarketOpen(code) : false;

  const marketActive = status === "market" || marketOpen;
  const leagueActive = status === "league" || status === "complete";

  const marketBadge = code ? getNavBadge(code, "market") : null;
  const torneoBadge = code ? getNavBadge(code, "torneo") : null;
  const feedBadge = code ? getNavBadge(code, "feed") : null;

  const next: NavState = {
    lobbyHref: code ? `/lobby/${code}` : "/lobby",
    has: !!code,
    hasTeam,
    status,
    marketActive,
    leagueActive,
    marketBadge,
    torneoBadge,
    feedBadge,
  };

  if (
    _prev &&
    _prev.lobbyHref === next.lobbyHref &&
    _prev.has === next.has &&
    _prev.hasTeam === next.hasTeam &&
    _prev.status === next.status &&
    _prev.marketActive === next.marketActive &&
    _prev.leagueActive === next.leagueActive &&
    _prev.marketBadge === next.marketBadge &&
    _prev.torneoBadge === next.torneoBadge &&
    _prev.feedBadge === next.feedBadge
  )
    return _prev;

  _prev = next;
  return next;
}

const SERVER_NAV: NavState = {
  lobbyHref: "/lobby",
  has: false,
  hasTeam: false,
  status: null,
  marketActive: false,
  leagueActive: false,
  marketBadge: null,
  torneoBadge: null,
  feedBadge: null,
};

// ── Badge component ─────────────────────────────────────────────────────────────

function TabBadge({ badge }: { badge: NavBadgeType | null }) {
  if (!badge) return null;

  const colors = {
    critical: "bg-[#EF4444]",
    important: "bg-[#F59E0B]",
    info: "bg-[#3B82F6]",
  };
  const bg = colors[badge.priority];
  const pulse = badge.priority === "critical" ? "badge-critical" : "";

  if (badge.count <= 1) {
    return (
      <span
        className={`absolute -top-0.5 -right-0.5 w-2.5 h-2.5 rounded-full ${bg} ${pulse} ring-2 ring-[#0D0F14]`}
      />
    );
  }

  return (
    <span
      className={`absolute -top-1.5 -right-2.5 min-w-4 h-4 rounded-full flex items-center justify-center text-[9px] font-black text-white px-1 ${bg} ${pulse} ring-2 ring-[#0D0F14]`}
    >
      {badge.count > 99 ? "99+" : badge.count}
    </span>
  );
}

// ── Icons ───────────────────────────────────────────────────────────────────────

function IconLobby({ active }: { active: boolean }) {
  const c = active ? "#8B5CF6" : "#6B7280";
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
      <circle cx="9" cy="7" r="4" />
      <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  );
}

function IconEquipo({ active }: { active: boolean }) {
  const c = active ? "#8B5CF6" : "#6B7280";
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
    </svg>
  );
}

function IconMercado({ active }: { active: boolean }) {
  const c = active ? "#8B5CF6" : "#6B7280";
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" />
      <polyline points="16 7 22 7 22 13" />
    </svg>
  );
}

function IconTorneo({ active }: { active: boolean }) {
  const c = active ? "#8B5CF6" : "#6B7280";
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6" />
      <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18" />
      <path d="M4 22h16" />
      <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20 7 22" />
      <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20 17 22" />
      <path d="M18 2H6v7a6 6 0 0 0 12 0V2Z" />
    </svg>
  );
}

function IconFeed({ active }: { active: boolean }) {
  const c = active ? "#8B5CF6" : "#6B7280";
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    </svg>
  );
}

function IconMas({ active }: { active: boolean }) {
  const c = active ? "#8B5CF6" : "#6B7280";
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="1" /><circle cx="19" cy="12" r="1" /><circle cx="5" cy="12" r="1" />
    </svg>
  );
}

// ── Tab interface ───────────────────────────────────────────────────────────────

interface Tab {
  id: string;
  href: string;
  label: string;
  icon: React.ComponentType<{ active: boolean }>;
  badge?: NavBadgeType | null;
  matchPaths: string[];
}

// ── Sub-tabs component ──────────────────────────────────────────────────────────

function SubTabs({
  items,
  pathname,
}: {
  items: { href: string; label: string; icon: React.ReactNode }[];
  pathname: string;
}) {
  return (
    <div className="flex items-center gap-1.5 px-4 pt-2.5 pb-1.5">
      {items.map(({ href, label, icon }) => {
        const active = pathname === href || pathname.startsWith(href + "/");
        return (
          <Link
            key={href}
            href={href}
            className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-full text-[11px] font-semibold transition-all duration-200 ${
              active
                ? "bg-[#8B5CF6]/15 text-[#8B5CF6] border border-[#8B5CF6]/25"
                : "bg-[#131722] text-[#9CA3AF] border border-white/6 active:bg-[#1A1F2E]"
            }`}
          >
            {icon}
            {label}
          </Link>
        );
      })}
    </div>
  );
}

const mercadoSubItems = [
  {
    href: "/market",
    label: "Mercado",
    icon: (
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" /><polyline points="16 7 22 7 22 13" />
      </svg>
    ),
  },
  {
    href: "/subastas",
    label: "Subastas",
    icon: (
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
      </svg>
    ),
  },
];

const torneoSubItems = [
  {
    href: "/calendar",
    label: "Jornada",
    icon: (
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="4" width="18" height="18" rx="2" ry="2" /><line x1="16" y1="2" x2="16" y2="6" /><line x1="8" y1="2" x2="8" y2="6" /><line x1="3" y1="10" x2="21" y2="10" />
      </svg>
    ),
  },
  {
    href: "/table",
    label: "Tabla",
    icon: (
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <path d="M18 20V10" /><path d="M12 20V4" /><path d="M6 20v-6" />
      </svg>
    ),
  },
];

// ── Más drawer ──────────────────────────────────────────────────────────────────

function MoreDrawer({
  open,
  onClose,
  marketActive,
  leagueActive,
  lobbyHref,
}: {
  open: boolean;
  onClose: () => void;
  marketActive: boolean;
  leagueActive: boolean;
  lobbyHref: string;
}) {
  const pathname = usePathname();

  const items: {
    href: string;
    label: string;
    locked: boolean;
    icon: React.ReactNode;
  }[] = [
    {
      href: lobbyHref,
      label: "Lobby",
      locked: false,
      icon: (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
          <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M23 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" />
        </svg>
      ),
    },
    {
      href: "/magic-link",
      label: "Mi Enlace",
      locked: false,
      icon: (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
          <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
          <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
        </svg>
      ),
    },
    {
      href: "/rejoin",
      label: "Reingresar",
      locked: false,
      icon: (
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
          <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" />
          <polyline points="10 17 15 12 10 7" />
          <line x1="15" y1="12" x2="3" y2="12" />
        </svg>
      ),
    },
  ];

  if (!open) return null;

  return (
    <>
      <div className="fixed inset-0 z-40 bg-black/50 backdrop-blur-sm" onClick={onClose} />
      <div className="fixed bottom-[calc(env(safe-area-inset-bottom)+4rem)] left-0 right-0 z-50 mx-3 mb-2 rounded-2xl bg-[#131722] border border-white/8 shadow-2xl overflow-hidden animate-in slide-in-from-bottom-4 duration-200">
        <div className="px-4 pt-4 pb-2">
          <p className="text-[#9CA3AF] text-[10px] font-semibold uppercase tracking-widest mb-3">
            Más opciones
          </p>
          <div className="flex flex-col gap-0.5">
            {items.map(({ href, label, locked, icon }) => {
              const active =
                pathname === href || pathname.startsWith(href + "/");

              if (locked) {
                return (
                  <div
                    key={href}
                    className="flex items-center gap-3 px-3 py-3 rounded-xl text-[#9CA3AF]/30 cursor-not-allowed"
                  >
                    <span className="text-[#9CA3AF]/20">{icon}</span>
                    <span className="text-sm font-medium">{label}</span>
                    <svg className="ml-auto" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <rect x="3" y="11" width="18" height="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />
                    </svg>
                  </div>
                );
              }

              return (
                <Link
                  key={href}
                  href={href}
                  onClick={onClose}
                  className={`flex items-center gap-3 px-3 py-3 rounded-xl text-sm font-medium transition-colors duration-150 ${
                    active
                      ? "bg-[#8B5CF6]/10 text-[#8B5CF6]"
                      : "text-[#F3F4F6] active:bg-[#1A1F2E]"
                  }`}
                >
                  <span className={active ? "text-[#8B5CF6]" : "text-[#9CA3AF]"}>
                    {icon}
                  </span>
                  {label}
                </Link>
              );
            })}
          </div>
        </div>
        <div className="h-px bg-white/4 mx-4" />
        <button
          onClick={onClose}
          className="w-full px-4 py-3.5 text-[#9CA3AF] text-sm font-medium text-center active:bg-[#1A1F2E] transition-colors cursor-pointer"
        >
          Cerrar
        </button>
      </div>
    </>
  );
}

// ── Main component ──────────────────────────────────────────────────────────────

export default function BottomNav() {
  const pathname = usePathname();
  const [moreOpen, setMoreOpen] = useState(false);

  const nav = useSyncExternalStore(
    (cb) => {
      window.addEventListener("mercatto:store-change", cb);
      window.addEventListener("storage", cb);
      return () => {
        window.removeEventListener("mercatto:store-change", cb);
        window.removeEventListener("storage", cb);
      };
    },
    getNavSnapshot,
    () => SERVER_NAV,
  );

  // ── Build dynamic tab list ────────────────────────────────────────────
  const tabs: Tab[] = [];

  if (nav.hasTeam) {
    tabs.push({
      id: "equipo",
      href: "/squad",
      label: "Equipo",
      icon: IconEquipo,
      matchPaths: ["/squad"],
    });
  } else if (nav.has) {
    tabs.push({
      id: "lobby",
      href: nav.lobbyHref,
      label: "Lobby",
      icon: IconLobby,
      matchPaths: ["/lobby"],
    });
  }

  if (nav.marketActive) {
    tabs.push({
      id: "mercado",
      href: "/market",
      label: "Mercado",
      icon: IconMercado,
      badge: nav.marketBadge,
      matchPaths: ["/market", "/subastas"],
    });
  }

  if (nav.leagueActive) {
    tabs.push({
      id: "torneo",
      href: "/calendar",
      label: "Torneo",
      icon: IconTorneo,
      badge: nav.torneoBadge,
      matchPaths: ["/calendar", "/table"],
    });
  }

  if (nav.hasTeam) {
    tabs.push({
      id: "feed",
      href: "/feed",
      label: "Feed",
      icon: IconFeed,
      badge: nav.feedBadge,
      matchPaths: ["/feed"],
    });
  }

  const moreMatchPaths = ["/magic-link", "/rejoin"];
  if (!nav.hasTeam) moreMatchPaths.push("/lobby");
  const moreActive = moreMatchPaths.some(
    (p) => pathname === p || pathname.startsWith(p + "/"),
  );

  const totalBadges =
    (nav.marketBadge?.count ?? 0) +
    (nav.torneoBadge?.count ?? 0) +
    (nav.feedBadge?.count ?? 0);

  const mercadoSectionActive =
    nav.marketActive &&
    (pathname === "/market" ||
      pathname.startsWith("/market/") ||
      pathname === "/subastas" ||
      pathname.startsWith("/subastas/"));

  const torneoSectionActive =
    nav.leagueActive &&
    (pathname === "/calendar" ||
      pathname.startsWith("/calendar/") ||
      pathname === "/table" ||
      pathname.startsWith("/table/"));

  return (
    <>
      <MoreDrawer
        open={moreOpen}
        onClose={() => setMoreOpen(false)}
        marketActive={nav.marketActive}
        leagueActive={nav.leagueActive}
        lobbyHref={nav.lobbyHref}
      />

      <nav
        className="fixed bottom-0 left-0 right-0 z-30 border-t border-white/6 bg-[#0D0F14]/95 backdrop-blur-xl lg:hidden"
        style={{ paddingBottom: "env(safe-area-inset-bottom)" }}
      >
        {/* Sub-tabs for active section */}
        {mercadoSectionActive && (
          <SubTabs items={mercadoSubItems} pathname={pathname} />
        )}
        {torneoSectionActive && (
          <SubTabs items={torneoSubItems} pathname={pathname} />
        )}

        {/* Main tabs */}
        <div className="flex items-center h-16 px-1">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            const active = tab.matchPaths.some(
              (p) => pathname === p || pathname.startsWith(p + "/"),
            );
            const hasCritical = tab.badge?.priority === "critical";

            return (
              <Link
                key={tab.id}
                href={tab.href}
                className={`relative flex flex-col items-center justify-center gap-0.5 flex-1 py-1 transition-colors duration-200 ${
                  active
                    ? "text-[#8B5CF6]"
                    : "text-[#6B7280] active:text-[#9CA3AF]"
                } ${hasCritical ? "tab-glow-critical" : ""}`}
              >
                <div className="relative">
                  <Icon active={active} />
                  <TabBadge badge={tab.badge ?? null} />
                  {active && (
                    <div className="absolute -top-1 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-[#8B5CF6]" />
                  )}
                </div>
                <span
                  className={`text-[10px] font-medium ${active ? "text-[#8B5CF6]" : ""}`}
                >
                  {tab.label}
                </span>
              </Link>
            );
          })}

          {/* Más tab */}
          <button
            onClick={() => setMoreOpen(true)}
            className={`relative flex flex-col items-center justify-center gap-0.5 flex-1 py-1 transition-colors duration-200 cursor-pointer ${
              moreOpen || moreActive
                ? "text-[#8B5CF6]"
                : "text-[#6B7280] active:text-[#9CA3AF]"
            }`}
          >
            <div className="relative">
              <IconMas active={moreOpen || moreActive} />
              {moreActive && (
                <div className="absolute -top-1 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-[#8B5CF6]" />
              )}
              {totalBadges > 0 && !moreActive && (
                <span className="absolute -top-0.5 -right-0.5 w-2.5 h-2.5 rounded-full bg-[#8B5CF6] ring-2 ring-[#0D0F14]" />
              )}
            </div>
            <span
              className={`text-[10px] font-medium ${moreOpen || moreActive ? "text-[#8B5CF6]" : ""}`}
            >
              Más
            </span>
          </button>
        </div>
      </nav>
    </>
  );
}
