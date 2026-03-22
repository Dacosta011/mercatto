// ─── Keys ─────────────────────────────────────────────────────────────────────

const ADMIN_KEY = (tournamentCode: string) =>
  `mercatto:admin:${tournamentCode}`;

const MEMBER_KEY = (tournamentCode: string) =>
  `mercatto:member:${tournamentCode}`;

const LAST_TOURNAMENT_KEY = "mercatto:lastTournament";

// ─── Admin token ──────────────────────────────────────────────────────────────

export function saveAdminToken(tournamentCode: string, token: string) {
  localStorage.setItem(ADMIN_KEY(tournamentCode), token);
  localStorage.setItem(LAST_TOURNAMENT_KEY, tournamentCode);
}

export function getAdminToken(tournamentCode: string): string | null {
  return localStorage.getItem(ADMIN_KEY(tournamentCode));
}

export function isAdmin(tournamentCode: string): boolean {
  return !!getAdminToken(tournamentCode);
}

export function clearAdminToken(tournamentCode: string) {
  localStorage.removeItem(ADMIN_KEY(tournamentCode));
}

// ─── Member token ─────────────────────────────────────────────────────────────

export function saveMemberToken(tournamentCode: string, token: string) {
  localStorage.setItem(MEMBER_KEY(tournamentCode), token);
  localStorage.setItem(LAST_TOURNAMENT_KEY, tournamentCode);
}

export function getMemberToken(tournamentCode: string): string | null {
  return localStorage.getItem(MEMBER_KEY(tournamentCode));
}

// ─── Equipo asignado (flag local para UI) ─────────────────────────────────────

const TEAM_KEY = (tournamentCode: string) =>
  `mercatto:team:${tournamentCode}`;
const TEAM_CREST_KEY = (tournamentCode: string) =>
  `mercatto:teamCrest:${tournamentCode}`;

export function saveTeamAssignment(tournamentCode: string, teamName: string, crestUrl?: string | null) {
  localStorage.setItem(TEAM_KEY(tournamentCode), teamName);
  if (crestUrl) localStorage.setItem(TEAM_CREST_KEY(tournamentCode), crestUrl);
}

export function getTeamAssignment(tournamentCode: string): string | null {
  return localStorage.getItem(TEAM_KEY(tournamentCode));
}

export function getTeamCrest(tournamentCode: string): string | null {
  return localStorage.getItem(TEAM_CREST_KEY(tournamentCode));
}

export function hasTeamAssignment(tournamentCode: string): boolean {
  return !!getTeamAssignment(tournamentCode);
}

// ─── Último torneo visitado ───────────────────────────────────────────────────

export function getLastTournamentCode(): string | null {
  return localStorage.getItem(LAST_TOURNAMENT_KEY);
}

// ─── Display name + rol del participante ─────────────────────────────────────

const DISPLAY_NAME_KEY = (tournamentCode: string) =>
  `mercatto:displayName:${tournamentCode}`;

const ROLE_KEY = (tournamentCode: string) =>
  `mercatto:role:${tournamentCode}`;

export function saveUserProfile(
  tournamentCode: string,
  displayName: string,
  role: "admin" | "member"
) {
  localStorage.setItem(DISPLAY_NAME_KEY(tournamentCode), displayName);
  localStorage.setItem(ROLE_KEY(tournamentCode), role);
}

export function getDisplayName(tournamentCode: string): string | null {
  return localStorage.getItem(DISPLAY_NAME_KEY(tournamentCode));
}

export function getRole(tournamentCode: string): "admin" | "member" | null {
  const r = localStorage.getItem(ROLE_KEY(tournamentCode));
  return r === "admin" || r === "member" ? r : null;
}

// ─── Member UUID (guardado al unirse, distinto al token hash) ────────────────

const MEMBER_ID_KEY = (tournamentCode: string) =>
  `mercatto:memberId:${tournamentCode}`;

export function saveMemberId(tournamentCode: string, memberId: string) {
  localStorage.setItem(MEMBER_ID_KEY(tournamentCode), memberId);
}

export function getMemberId(tournamentCode: string): string | null {
  return localStorage.getItem(MEMBER_ID_KEY(tournamentCode));
}

// ─── Estado / fase del torneo (caché local para RouteGuard) ──────────────────

export type TournamentStatus =
  | "lobby"
  | "draft"
  | "market"
  | "league"
  | "complete";

const STATUS_KEY = (tournamentCode: string) =>
  `mercatto:status:${tournamentCode}`;

export function saveTournamentStatus(
  tournamentCode: string,
  status: TournamentStatus
) {
  localStorage.setItem(STATUS_KEY(tournamentCode), status);
  window.dispatchEvent(new Event("mercatto:store-change"));
}

export function getTournamentStatus(
  tournamentCode: string
): TournamentStatus | null {
  const v = localStorage.getItem(STATUS_KEY(tournamentCode));
  return v as TournamentStatus | null;
}

// ─── Suscripción a cambios del store (para RouteGuard) ───────────────────────

export function subscribeToStore(callback: () => void): () => void {
  window.addEventListener("mercatto:store-change", callback);
  return () => window.removeEventListener("mercatto:store-change", callback);
}

// ─── Market Open flag (hybrid state: market active during league) ─────────────

const MARKET_OPEN_KEY = (tournamentCode: string) =>
  `mercatto:marketOpen:${tournamentCode}`;

export function saveMarketOpen(tournamentCode: string, open: boolean) {
  if (open) {
    localStorage.setItem(MARKET_OPEN_KEY(tournamentCode), "true");
  } else {
    localStorage.removeItem(MARKET_OPEN_KEY(tournamentCode));
  }
  window.dispatchEvent(new Event("mercatto:store-change"));
}

export function getMarketOpen(tournamentCode: string): boolean {
  return localStorage.getItem(MARKET_OPEN_KEY(tournamentCode)) === "true";
}

// ─── Derived active-state helpers ────────────────────────────────────────────

export function isMarketActive(tournamentCode: string): boolean {
  const status = getTournamentStatus(tournamentCode);
  return status === "market" || getMarketOpen(tournamentCode);
}

export function isLeagueActive(tournamentCode: string): boolean {
  const status = getTournamentStatus(tournamentCode);
  return status === "league" || status === "complete";
}

// ─── Navigation badges ──────────────────────────────────────────────────────

export type BadgePriority = "critical" | "important" | "info";

export interface NavBadge {
  count: number;
  priority: BadgePriority;
}

const BADGE_KEY = (tournamentCode: string, tab: string) =>
  `mercatto:badge:${tab}:${tournamentCode}`;

export function saveNavBadge(
  tournamentCode: string,
  tab: string,
  badge: NavBadge | null
) {
  const key = BADGE_KEY(tournamentCode, tab);
  if (badge && badge.count > 0) {
    localStorage.setItem(key, JSON.stringify(badge));
  } else {
    localStorage.removeItem(key);
  }
  window.dispatchEvent(new Event("mercatto:store-change"));
}

export function getNavBadge(
  tournamentCode: string,
  tab: string
): NavBadge | null {
  const raw = localStorage.getItem(BADGE_KEY(tournamentCode, tab));
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function clearNavBadge(tournamentCode: string, tab: string) {
  localStorage.removeItem(BADGE_KEY(tournamentCode, tab));
  window.dispatchEvent(new Event("mercatto:store-change"));
}

// ─── Limpiar (logout de un torneo) ───────────────────────────────────────────

export function clearTournamentTokens(tournamentCode: string) {
  localStorage.removeItem(ADMIN_KEY(tournamentCode));
  localStorage.removeItem(MEMBER_KEY(tournamentCode));
  localStorage.removeItem(MEMBER_ID_KEY(tournamentCode));
  localStorage.removeItem(DISPLAY_NAME_KEY(tournamentCode));
  localStorage.removeItem(ROLE_KEY(tournamentCode));
  localStorage.removeItem(STATUS_KEY(tournamentCode));
  localStorage.removeItem(TEAM_CREST_KEY(tournamentCode));
  localStorage.removeItem(TEAM_KEY(tournamentCode));
  localStorage.removeItem(LAST_TOURNAMENT_KEY);
  localStorage.removeItem(MARKET_OPEN_KEY(tournamentCode));
  for (const tab of ["market", "torneo", "feed"]) {
    localStorage.removeItem(BADGE_KEY(tournamentCode, tab));
  }
  window.dispatchEvent(new Event("mercatto:store-change"));
}
