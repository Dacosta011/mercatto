"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, useSyncExternalStore } from "react";
import { getLastTournamentCode, hasTeamAssignment, getDisplayName, getRole, getTeamAssignment, getTeamCrest, getTournamentStatus } from "@/lib/tokenStorage";

let _lastCode: string | null = undefined as unknown as null;
let _lastHasTeam: boolean = false;
let _lastDisplayName: string | null = null;
let _lastRole: string | null = null;
let _lastTeamName: string | null = null;
let _lastTeamCrest: string | null = null;
let _lastStatus: string | null = null;
let _cachedSession = {
  lobbyHref: "/lobby",
  has: false,
  hasTeam: false,
  displayName: null as string | null,
  role: null as string | null,
  teamName: null as string | null,
  teamCrest: null as string | null,
  status: null as string | null,
};

function getSessionSnapshot() {
  const code = getLastTournamentCode();
  const hasTeam = code ? hasTeamAssignment(code) : false;
  const displayName = code ? getDisplayName(code) : null;
  const role = code ? getRole(code) : null;
  const teamName = code ? getTeamAssignment(code) : null;
  const teamCrest = code ? getTeamCrest(code) : null;
  const status = code ? getTournamentStatus(code) : null;

  if (
    code !== _lastCode ||
    hasTeam !== _lastHasTeam ||
    displayName !== _lastDisplayName ||
    role !== _lastRole ||
    teamName !== _lastTeamName ||
    teamCrest !== _lastTeamCrest ||
    status !== _lastStatus
  ) {
    _lastCode = code;
    _lastHasTeam = hasTeam;
    _lastDisplayName = displayName;
    _lastRole = role;
    _lastTeamName = teamName;
    _lastTeamCrest = teamCrest;
    _lastStatus = status;
    _cachedSession = code
      ? { lobbyHref: `/lobby/${code}`, has: true, hasTeam, displayName, role, teamName, teamCrest, status }
      : { lobbyHref: "/lobby", has: false, hasTeam: false, displayName: null, role: null, teamName: null, teamCrest: null, status: null };
  }
  return _cachedSession;
}

const SERVER_SESSION = {
  lobbyHref: "/lobby",
  has: false,
  hasTeam: false,
  displayName: null as string | null,
  role: null as string | null,
  teamName: null as string | null,
  teamCrest: null as string | null,
  status: null as string | null,
};

interface NavItem {
  href: string;
  label: string;
  icon: (active: boolean) => React.ReactNode;
}

const navItems: NavItem[] = [
  {
    href: "/lobby",
    label: "Lobby",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
        <circle cx="9" cy="7" r="4" />
        <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
        <path d="M16 3.13a4 4 0 0 1 0 7.75" />
      </svg>
    ),
  },
  {
    href: "/squad",
    label: "Mi Equipo",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
      </svg>
    ),
  },
  {
    href: "/market",
    label: "Mercado",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" />
        <polyline points="16 7 22 7 22 13" />
      </svg>
    ),
  },
  {
    href: "/subastas",
    label: "Subastas",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
      </svg>
    ),
  },
  {
    href: "/calendar",
    label: "Calendario",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <rect x="3" y="4" width="18" height="18" rx="2" ry="2"/>
        <line x1="16" y1="2" x2="16" y2="6"/>
        <line x1="8" y1="2" x2="8" y2="6"/>
        <line x1="3" y1="10" x2="21" y2="10"/>
      </svg>
    ),
  },
  {
    href: "/table",
    label: "Clasificación",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <path d="M18 20V10"/><path d="M12 20V4"/><path d="M6 20v-6"/>
      </svg>
    ),
  },
  {
    href: "/magic-link",
    label: "Mi Enlace",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
        <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
      </svg>
    ),
  },
];

const quickItems: NavItem[] = [
  {
    href: "/create",
    label: "Crear Torneo",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <line x1="12" y1="5" x2="12" y2="19" />
        <line x1="5" y1="12" x2="19" y2="12" />
      </svg>
    ),
  },
  {
    href: "/join",
    label: "Unirse",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" />
        <polyline points="10 17 15 12 10 7" />
        <line x1="15" y1="12" x2="3" y2="12" />
      </svg>
    ),
  },
  {
    href: "/rejoin",
    label: "Reingresar",
    icon: (active) => (
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={active ? "#8B5CF6" : "#9CA3AF"} strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
        <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
        <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
      </svg>
    ),
  },
];

function getInitialCollapsed() {
  if (typeof window === "undefined") return false;
  return localStorage.getItem("mercatto:sidebar:collapsed") === "true";
}

export default function Sidebar() {
  const pathname = usePathname();
  const [collapsed, setCollapsed] = useState(getInitialCollapsed);

  const { lobbyHref, has: hasTournament, hasTeam, displayName, role, teamName, teamCrest, status } = useSyncExternalStore(
    (cb) => {
      window.addEventListener("mercatto:store-change", cb);
      window.addEventListener("storage", cb);
      return () => {
        window.removeEventListener("mercatto:store-change", cb);
        window.removeEventListener("storage", cb);
      };
    },
    getSessionSnapshot,
    () => SERVER_SESSION
  );

  const toggleCollapse = () => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem("mercatto:sidebar:collapsed", String(next));
      return next;
    });
  };

  const resolveHref = (href: string) =>
    href === "/lobby" ? lobbyHref : href;

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
            <div className="w-7 h-7 rounded-lg bg-[#8B5CF6] flex items-center justify-center shadow-lg shadow-[#8B5CF6]/30">
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path d="M7 1L9.5 5.5H13L9.5 8.5L11 13L7 10.5L3 13L4.5 8.5L1 5.5H4.5L7 1Z" fill="white" />
              </svg>
            </div>
          </button>
        ) : (
          <div className="flex items-center justify-between px-5 py-5">
            <Link href="/" className="flex items-center gap-3 hover:opacity-80 transition-opacity duration-200">
              <div className="w-7 h-7 rounded-lg bg-[#8B5CF6] flex items-center justify-center shadow-lg shadow-[#8B5CF6]/30">
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M7 1L9.5 5.5H13L9.5 8.5L11 13L7 10.5L3 13L4.5 8.5L1 5.5H4.5L7 1Z" fill="white" />
                </svg>
              </div>
              <span className="text-[#F3F4F6] font-semibold tracking-widest text-xs">MERCATTO</span>
            </Link>
            <button
              onClick={toggleCollapse}
              className="w-6 h-6 rounded-md hover:bg-[#1A1F2E] flex items-center justify-center text-[#9CA3AF] hover:text-[#F3F4F6] transition-colors cursor-pointer"
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="11 17 6 12 11 7" />
                <polyline points="18 17 13 12 18 7" />
              </svg>
            </button>
          </div>
        )}
      </div>

      {/* Nav items */}
      <nav className="flex flex-col gap-1 flex-1 p-3 pt-4 overflow-y-auto">
        {hasTournament ? (
          <>
            {!collapsed && (
              <p className="text-[#9CA3AF] text-[10px] font-semibold uppercase tracking-widest px-3 mb-2">
                Navegación
              </p>
            )}
            {navItems.map(({ href, label, icon }) => {
              const resolved = resolveHref(href);
              const isLobby = href === "/lobby";
              const active = isLobby
                ? pathname === resolved || pathname.startsWith("/lobby/")
                : pathname === href || pathname.startsWith(href + "/");

              const noTeam = href === "/squad" && !hasTeam;
              const marketLocked = (href === "/market" || href === "/subastas") && status !== "market";
              const leagueLocked = (href === "/calendar" || href === "/table") && status !== "league";
              const locked = noTeam || marketLocked || leagueLocked;

              if (locked) {
                const lockReason = noTeam
                  ? "Debes girar la ruleta primero"
                  : marketLocked
                  ? "Disponible durante el mercado"
                  : leagueLocked
                  ? "Disponible durante la liga"
                  : "No disponible";
                return (
                  <div
                    key={href}
                    title={lockReason}
                    className={`flex items-center gap-3 rounded-xl text-sm font-medium text-[#9CA3AF]/30 cursor-not-allowed select-none ${
                      collapsed ? "justify-center px-0 py-2.5" : "px-3 py-2.5"
                    }`}
                  >
                    {icon(false)}
                    {!collapsed && label}
                    {!collapsed && (
                      <span className="ml-auto">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                          <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                          <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                        </svg>
                      </span>
                    )}
                  </div>
                );
              }

              return (
                <Link
                  key={href}
                  href={resolved}
                  title={collapsed ? label : undefined}
                  className={`flex items-center gap-3 rounded-xl text-sm font-medium transition-all duration-200 ${
                    collapsed ? "justify-center px-0 py-2.5" : "px-3 py-2.5"
                  } ${
                    active
                      ? "bg-[#8B5CF6]/10 text-[#8B5CF6]"
                      : "text-[#9CA3AF] hover:bg-[#1A1F2E] hover:text-[#F3F4F6]"
                  }`}
                >
                  {icon(active)}
                  {!collapsed && label}
                  {!collapsed && active && <span className="ml-auto w-1 h-4 rounded-full bg-[#8B5CF6]" />}
                </Link>
              );
            })}
          </>
        ) : (
          <>
            {!collapsed && (
              <p className="text-[#9CA3AF] text-[10px] font-semibold uppercase tracking-widest px-3 mb-2">
                Acciones
              </p>
            )}
            {quickItems.map(({ href, label, icon }) => {
              const active = pathname === href || pathname.startsWith(href + "/");
              return (
                <Link
                  key={href}
                  href={href}
                  title={collapsed ? label : undefined}
                  className={`flex items-center gap-3 rounded-xl text-sm font-medium transition-all duration-200 ${
                    collapsed ? "justify-center px-0 py-2.5" : "px-3 py-2.5"
                  } ${
                    active
                      ? "bg-[#8B5CF6]/10 text-[#8B5CF6]"
                      : "text-[#9CA3AF] hover:bg-[#1A1F2E] hover:text-[#F3F4F6]"
                  }`}
                >
                  {icon(active)}
                  {!collapsed && label}
                  {!collapsed && active && <span className="ml-auto w-1 h-4 rounded-full bg-[#8B5CF6]" />}
                </Link>
              );
            })}
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
              <polyline points="13 17 18 12 13 7" />
              <polyline points="6 17 11 12 6 7" />
            </svg>
          </button>
        </div>
      )}

      {/* User area */}
      <div className="p-3 border-t border-white/4">
        {displayName ? (
          collapsed ? (
            <div className="flex items-center justify-center" title={`${displayName}${teamName ? ` · ${teamName}` : ""}`}>
              {teamCrest ? (
                <img src={teamCrest} alt={teamName ?? ""} className="w-8 h-8 object-contain" />
              ) : (
                <div className="w-8 h-8 rounded-full bg-linear-to-br from-[#8B5CF6] to-[#6D28D9] flex items-center justify-center shadow-md shadow-[#8B5CF6]/20">
                  <span className="text-white text-xs font-bold">
                    {displayName.charAt(0).toUpperCase()}
                  </span>
                </div>
              )}
            </div>
          ) : (
            <div className="flex items-center gap-3 px-3 py-2.5 rounded-xl bg-[#0D0F14]/60">
              {teamCrest ? (
                <img src={teamCrest} alt={teamName ?? ""} className="w-8 h-8 object-contain shrink-0" />
              ) : (
                <div className="w-8 h-8 rounded-full bg-linear-to-br from-[#8B5CF6] to-[#6D28D9] flex items-center justify-center shrink-0 shadow-md shadow-[#8B5CF6]/20">
                  <span className="text-white text-xs font-bold">
                    {displayName.charAt(0).toUpperCase()}
                  </span>
                </div>
              )}
              <div className="min-w-0 flex-1">
                <p className="text-[#F3F4F6] text-xs font-semibold truncate leading-tight">
                  {displayName}
                </p>
                {teamName && (
                  <p className="text-[#9CA3AF] text-[10px] truncate">{teamName}</p>
                )}
                <div className="flex items-center gap-1.5 mt-0.5">
                  {role === "admin" ? (
                    <>
                      <span className="w-1.5 h-1.5 rounded-full bg-[#F59E0B] shrink-0" />
                      <span className="text-[#F59E0B] text-[10px] font-medium">Admin</span>
                    </>
                  ) : (
                    <>
                      <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E] shrink-0" />
                      <span className="text-[#22C55E] text-[10px] font-medium">Participante</span>
                    </>
                  )}
                </div>
              </div>
            </div>
          )
        ) : (
          collapsed ? (
            <div className="flex items-center justify-center">
              <div className="w-8 h-8 rounded-full bg-white/5 border border-white/8 flex items-center justify-center">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                  <circle cx="12" cy="7" r="4" />
                </svg>
              </div>
            </div>
          ) : (
            <div className="flex items-center gap-3 px-3 py-2.5 rounded-xl">
              <div className="w-8 h-8 rounded-full bg-white/5 border border-white/8 flex items-center justify-center shrink-0">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                  <circle cx="12" cy="7" r="4" />
                </svg>
              </div>
              <div className="min-w-0">
                <p className="text-[#9CA3AF] text-xs font-medium">Sin sesión</p>
                <p className="text-[#9CA3AF]/50 text-[10px]">Crea o únete a un torneo</p>
              </div>
            </div>
          )
        )}
      </div>
    </aside>
  );
}
