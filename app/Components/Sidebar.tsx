"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useSyncExternalStore } from "react";
import {
  getLastTournamentCode,
  hasTeamAssignment,
  getDisplayName,
  getRole,
  getTeamAssignment,
  getTeamCrest,
  getTournamentStatus,
  getMarketOpen,
  getNavBadge,
  isGuest,
  type NavBadge as NavBadgeType,
} from "@/lib/tokenStorage";

// ── Snapshot ────────────────────────────────────────────────────────────────────

interface SidebarState {
  lobbyHref: string;
  has: boolean;
  hasTeam: boolean;
  guest: boolean;
  displayName: string | null;
  role: string | null;
  teamName: string | null;
  teamCrest: string | null;
  status: string | null;
  marketActive: boolean;
  leagueActive: boolean;
  marketBadge: NavBadgeType | null;
  torneoBadge: NavBadgeType | null;
  feedBadge: NavBadgeType | null;
}

let _prev: SidebarState | null = null;

function getSessionSnapshot(): SidebarState {
  const code = getLastTournamentCode();
  const hasTeamVal = code ? hasTeamAssignment(code) : false;
  const guest = code ? isGuest(code) : false;
  const displayName = code ? getDisplayName(code) : null;
  const role = code ? getRole(code) : null;
  const teamName = code ? getTeamAssignment(code) : null;
  const teamCrest = code ? getTeamCrest(code) : null;
  const status = code ? getTournamentStatus(code) : null;
  const marketOpen = code ? getMarketOpen(code) : false;

  const marketActive = status === "market" || marketOpen;
  const leagueActive = status === "league" || status === "complete";

  const marketBadge = code ? getNavBadge(code, "market") : null;
  const torneoBadge = code ? getNavBadge(code, "torneo") : null;
  const feedBadge = code ? getNavBadge(code, "feed") : null;

  const next: SidebarState = {
    lobbyHref: code ? `/lobby/${code}` : "/lobby",
    has: !!code,
    hasTeam: hasTeamVal,
    guest,
    displayName,
    role,
    teamName,
    teamCrest,
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
    _prev.guest === next.guest &&
    _prev.displayName === next.displayName &&
    _prev.role === next.role &&
    _prev.teamName === next.teamName &&
    _prev.teamCrest === next.teamCrest &&
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

const SERVER_SESSION: SidebarState = {
  lobbyHref: "/lobby",
  has: false,
  hasTeam: false,
  guest: false,
  displayName: null,
  role: null,
  teamName: null,
  teamCrest: null,
  status: null,
  marketActive: false,
  leagueActive: false,
  marketBadge: null,
  torneoBadge: null,
  feedBadge: null,
};

// ── Nav item type ───────────────────────────────────────────────────────────────

interface NavItem {
  href: string;
  label: string;
  locked?: boolean;
  lockReason?: string;
  badge?: NavBadgeType | null;
  icon: (active: boolean) => React.ReactNode;
}

// ── Badge component ─────────────────────────────────────────────────────────────

function SidebarBadge({
  badge,
  collapsed,
}: {
  badge: NavBadgeType | null;
  collapsed: boolean;
}) {
  if (!badge) return null;

  const colors = {
    critical: "bg-[#EF4444]",
    important: "bg-[#F59E0B]",
    info: "bg-[#3B82F6]",
  };
  const bg = colors[badge.priority];
  const pulse = badge.priority === "critical" ? "badge-critical" : "";

  if (collapsed) {
    return (
      <span
        className={`absolute top-1 right-0.5 w-2 h-2 rounded-full ${bg} ${pulse}`}
      />
    );
  }

  if (badge.count <= 1) {
    return (
      <span className={`ml-auto w-2 h-2 rounded-full ${bg} ${pulse} shrink-0`} />
    );
  }

  return (
    <span
      className={`ml-auto min-w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-black text-white px-1 ${bg} ${pulse} shrink-0`}
    >
      {badge.count > 99 ? "99+" : badge.count}
    </span>
  );
}

// ── Icons ───────────────────────────────────────────────────────────────────────

const icons = {
  lobby: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M23 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  ),
  equipo: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" />
    </svg>
  ),
  mercado: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" /><polyline points="16 7 22 7 22 13" />
    </svg>
  ),
  subastas: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
    </svg>
  ),
  historial: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" />
    </svg>
  ),
  calendario: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="18" height="18" rx="2" ry="2" /><line x1="16" y1="2" x2="16" y2="6" /><line x1="8" y1="2" x2="8" y2="6" /><line x1="3" y1="10" x2="21" y2="10" />
    </svg>
  ),
  clasificacion: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M18 20V10" /><path d="M12 20V4" /><path d="M6 20v-6" />
    </svg>
  ),
  feed: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
    </svg>
  ),
  enlace: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" /><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  ),
  crear: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" />
    </svg>
  ),
  unirse: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" /><polyline points="10 17 15 12 10 7" /><line x1="15" y1="12" x2="3" y2="12" />
    </svg>
  ),
  reingresar: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" /><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
    </svg>
  ),
  tragaperras: (a: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={a ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="7" width="20" height="14" rx="2" ry="2" /><path d="M16 7V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v2" /><line x1="12" y1="12" x2="12" y2="16" /><line x1="10" y1="14" x2="14" y2="14" />
    </svg>
  ),
};

// ── Section header ──────────────────────────────────────────────────────────────

function SectionHeader({
  label,
  color,
  collapsed,
}: {
  label: string;
  color?: string;
  collapsed: boolean;
}) {
  if (collapsed) {
    return (
      <div className="flex justify-center py-2">
        <div
          className="w-4 h-0.5 rounded-full"
          style={{ background: color ?? "#ffffff15" }}
        />
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2 px-3 mt-4 mb-2">
      {color && (
        <span
          className="w-1.5 h-1.5 rounded-full shrink-0"
          style={{ background: color }}
        />
      )}
      <p className="text-[#9CA3AF] text-[10px] font-semibold uppercase tracking-widest">
        {label}
      </p>
    </div>
  );
}

// ── Nav link ────────────────────────────────────────────────────────────────────

function NavLink({
  item,
  collapsed,
  pathname,
  resolvedHref,
}: {
  item: NavItem;
  collapsed: boolean;
  pathname: string;
  resolvedHref?: string;
}) {
  const href = resolvedHref ?? item.href;
  const isLobby = item.href === "/lobby";
  const active = isLobby
    ? pathname === href || pathname.startsWith("/lobby/")
    : pathname === item.href || pathname.startsWith(item.href + "/");

  if (item.locked) {
    return (
      <div
        title={item.lockReason ?? "No disponible"}
        className={`relative flex items-center gap-3 rounded-xl text-sm font-medium text-[#9CA3AF]/30 cursor-not-allowed select-none ${
          collapsed ? "justify-center px-0 py-2.5" : "px-3 py-2.5"
        }`}
      >
        {item.icon(false)}
        {!collapsed && item.label}
        {!collapsed && (
          <span className="ml-auto">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="11" width="18" height="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
          </span>
        )}
      </div>
    );
  }

  return (
    <Link
      href={href}
      title={collapsed ? item.label : undefined}
      className={`relative flex items-center gap-3 rounded-xl text-sm font-medium transition-all duration-200 ${
        collapsed ? "justify-center px-0 py-2.5" : "px-3 py-2.5"
      } ${
        active
          ? "bg-[#8B5CF6]/10 text-[#8B5CF6]"
          : "text-[#9CA3AF] hover:bg-[#1A1F2E] hover:text-[#F3F4F6]"
      }`}
    >
      {item.icon(active)}
      {!collapsed && item.label}
      {!collapsed && active && !item.badge && (
        <span className="ml-auto w-1 h-4 rounded-full bg-[#8B5CF6]" />
      )}
      <SidebarBadge badge={item.badge ?? null} collapsed={collapsed} />
    </Link>
  );
}

// ── Collapse toggle helpers ─────────────────────────────────────────────────────

function getInitialCollapsed() {
  if (typeof window === "undefined") return false;
  return localStorage.getItem("mercatto:sidebar:collapsed") === "true";
}

// ── Main component ──────────────────────────────────────────────────────────────

export default function Sidebar() {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(getInitialCollapsed);

  const session = useSyncExternalStore(
    (cb) => {
      window.addEventListener("mercatto:store-change", cb);
      window.addEventListener("storage", cb);
      return () => {
        window.removeEventListener("mercatto:store-change", cb);
        window.removeEventListener("storage", cb);
      };
    },
    getSessionSnapshot,
    () => SERVER_SESSION,
  );

  const toggleCollapse = () => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem("mercatto:sidebar:collapsed", String(next));
      return next;
    });
  };

  // ── Build section items ───────────────────────────────────────────────

  const principalItems: NavItem[] = session.guest
    ? [
        {
          href: "/feed",
          label: "Feed",
          icon: icons.feed,
          badge: session.feedBadge,
        },
      ]
    : [
        { href: "/lobby", label: "Lobby", icon: icons.lobby },
        {
          href: "/squad",
          label: "Equipo",
          icon: icons.equipo,
          locked: !session.hasTeam && session.role !== "admin",
          lockReason: "Debes girar la ruleta primero",
        },
        {
          href: "/feed",
          label: "Feed",
          icon: icons.feed,
          badge: session.feedBadge,
          locked: !session.hasTeam && session.role !== "admin",
          lockReason: "Disponible tras el draft",
        },
        { href: "/market-history", label: "Historial", icon: icons.historial },
      ];

  const mercadoItems: NavItem[] = [
    { href: "/market", label: "Mercado", icon: icons.mercado, badge: session.marketBadge },
    { href: "/subastas", label: "Subastas", icon: icons.subastas },
  ];

  const torneoItems: NavItem[] = [
    {
      href: "/calendar",
      label: "Calendario",
      icon: icons.calendario,
      badge: session.torneoBadge,
    },
    { href: "/table", label: "Clasificación", icon: icons.clasificacion },
  ];

  const toolItems: NavItem[] = [
    { href: "/magic-link", label: "Mi Enlace", icon: icons.enlace },
    // { href: "/tragaperras", label: "Slots", icon: icons.tragaperras },
  ];

  const quickItems: NavItem[] = [
    { href: "/create", label: "Crear Torneo", icon: icons.crear },
    { href: "/join", label: "Unirse", icon: icons.unirse },
    { href: "/rejoin", label: "Reingresar", icon: icons.reingresar },
  ];

  return (
    <aside
      className={`min-h-screen bg-[#131722] border-r border-white/4 flex flex-col shrink-0 transition-all duration-200 ease-out ${
        collapsed ? "w-15" : "w-55"
      }`}
    >
      {/* Logo + collapse toggle */}
      <div className="border-b border-white/4">
        {collapsed ? (
          <button
            onClick={toggleCollapse}
            className="w-full flex items-center justify-center py-5 hover:bg-[#1A1F2E] transition-colors duration-200 cursor-pointer"
          >
            <img src="/mercatto-logo.svg" alt="Mercatto" className="w-7 h-auto" />
          </button>
        ) : (
          <div className="flex items-center justify-between px-5 py-5">
            <Link
              href="/"
              className="flex items-center gap-2.5 hover:opacity-80 transition-opacity duration-200"
            >
              <img src="/mercatto-logo.svg" alt="" className="w-7 h-auto" />
              <img src="/mercatto-text.svg" alt="Mercatto" className="h-3 w-auto brightness-0 invert" />
            </Link>
            <button
              onClick={toggleCollapse}
              className="w-6 h-6 rounded-md hover:bg-[#1A1F2E] flex items-center justify-center text-[#9CA3AF] hover:text-[#F3F4F6] transition-colors cursor-pointer"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="11 17 6 12 11 7" /><polyline points="18 17 13 12 18 7" />
              </svg>
            </button>
          </div>
        )}
      </div>

      {/* Navigation */}
      <nav className="flex flex-col gap-0.5 flex-1 p-3 pt-2 overflow-y-auto">
        {session.has ? (
          <>
            {/* ── Principal ── */}
            <SectionHeader label="Principal" collapsed={collapsed} />
            {principalItems.map((item) => (
              <NavLink
                key={item.href}
                item={item}
                collapsed={collapsed}
                pathname={pathname}
                resolvedHref={item.href === "/lobby" ? session.lobbyHref : undefined}
              />
            ))}

            {/* ── Mercado section (conditional, hidden for guests) ── */}
            {session.marketActive && !session.guest && (
              <div className="section-animate-in">
                <SectionHeader
                  label="Mercado"
                  color="#8B5CF6"
                  collapsed={collapsed}
                />
                {mercadoItems.map((item) => (
                  <NavLink
                    key={item.href}
                    item={item}
                    collapsed={collapsed}
                    pathname={pathname}
                  />
                ))}
              </div>
            )}

            {/* ── Torneo section (conditional) ── */}
            {(session.leagueActive || session.guest) && (
              <div className="section-animate-in">
                <SectionHeader
                  label="Torneo"
                  color="#3B82F6"
                  collapsed={collapsed}
                />
                {torneoItems.map((item) => (
                  <NavLink
                    key={item.href}
                    item={item}
                    collapsed={collapsed}
                    pathname={pathname}
                  />
                ))}
              </div>
            )}

            {/* ── Herramientas (hidden for guests) ── */}
            {!session.guest && (
              <>
                <SectionHeader label="Herramientas" collapsed={collapsed} />
                {toolItems.map((item) => (
                  <NavLink
                    key={item.href}
                    item={item}
                    collapsed={collapsed}
                    pathname={pathname}
                  />
                ))}
              </>
            )}
          </>
        ) : (
          <>
            <SectionHeader label="Acciones" collapsed={collapsed} />
            {quickItems.map((item) => (
              <NavLink
                key={item.href}
                item={item}
                collapsed={collapsed}
                pathname={pathname}
              />
            ))}
          </>
        )}
      </nav>

      {/* Expand button when collapsed */}
      {collapsed && (
        <div className="px-2 pb-2">
          <button
            onClick={toggleCollapse}
            className="w-full flex items-center justify-center py-2 rounded-lg hover:bg-[#1A1F2E] text-[#9CA3AF] hover:text-[#F3F4F6] transition-colors cursor-pointer"
          >
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="13 17 18 12 13 7" /><polyline points="6 17 11 12 6 7" />
            </svg>
          </button>
        </div>
      )}

      {/* User area */}
      <div className="p-3 border-t border-white/4">
        {session.displayName ? (
          collapsed ? (
            <div
              className="flex items-center justify-center"
              title={`${session.displayName}${session.teamName ? ` · ${session.teamName}` : ""}`}
            >
              {session.teamCrest ? (
                <img
                  src={session.teamCrest}
                  alt={session.teamName ?? ""}
                  className="w-8 h-8 object-contain"
                />
              ) : (
                <div className="w-8 h-8 rounded-full bg-linear-to-br from-[#8B5CF6] to-[#6D28D9] flex items-center justify-center shadow-md shadow-[#8B5CF6]/20">
                  <span className="text-white text-xs font-bold">
                    {session.displayName.charAt(0).toUpperCase()}
                  </span>
                </div>
              )}
            </div>
          ) : (
            <div className="flex items-center gap-3 px-3 py-2.5 rounded-xl bg-[#0D0F14]/60">
              {session.teamCrest ? (
                <img
                  src={session.teamCrest}
                  alt={session.teamName ?? ""}
                  className="w-8 h-8 object-contain shrink-0"
                />
              ) : (
                <div className="w-8 h-8 rounded-full bg-linear-to-br from-[#8B5CF6] to-[#6D28D9] flex items-center justify-center shrink-0 shadow-md shadow-[#8B5CF6]/20">
                  <span className="text-white text-xs font-bold">
                    {session.displayName.charAt(0).toUpperCase()}
                  </span>
                </div>
              )}
              <div className="min-w-0 flex-1">
                <p className="text-[#F3F4F6] text-xs font-semibold truncate leading-tight">
                  {session.displayName}
                </p>
                {session.teamName && (
                  <p className="text-[#9CA3AF] text-[10px] truncate">
                    {session.teamName}
                  </p>
                )}
                <div className="flex items-center gap-1.5 mt-0.5">
                  {session.role === "admin" ? (
                    <>
                      <span className="w-1.5 h-1.5 rounded-full bg-[#F59E0B] shrink-0" />
                      <span className="text-[#F59E0B] text-[10px] font-medium">
                        Admin
                      </span>
                    </>
                  ) : (
                    <>
                      <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E] shrink-0" />
                      <span className="text-[#22C55E] text-[10px] font-medium">
                        Participante
                      </span>
                    </>
                  )}
                </div>
              </div>
            </div>
          )
        ) : collapsed ? (
          <div className="flex items-center justify-center">
            <div className="w-8 h-8 rounded-full bg-white/5 border border-white/8 flex items-center justify-center">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" /><circle cx="12" cy="7" r="4" />
              </svg>
            </div>
          </div>
        ) : (
          <div className="flex items-center gap-3 px-3 py-2.5 rounded-xl">
            <div className="w-8 h-8 rounded-full bg-white/5 border border-white/8 flex items-center justify-center shrink-0">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" /><circle cx="12" cy="7" r="4" />
              </svg>
            </div>
            <div className="min-w-0">
              <p className="text-[#9CA3AF] text-xs font-medium">Sin sesión</p>
              <p className="text-[#9CA3AF]/50 text-[10px]">
                Crea o únete a un torneo
              </p>
            </div>
          </div>
        )}
      </div>
    </aside>
  );
}
