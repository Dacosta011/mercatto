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

export function saveTeamAssignment(tournamentCode: string, teamName: string) {
  localStorage.setItem(TEAM_KEY(tournamentCode), teamName);
}

export function getTeamAssignment(tournamentCode: string): string | null {
  return localStorage.getItem(TEAM_KEY(tournamentCode));
}

export function hasTeamAssignment(tournamentCode: string): boolean {
  return !!getTeamAssignment(tournamentCode);
}

// ─── Último torneo visitado ───────────────────────────────────────────────────

export function getLastTournamentCode(): string | null {
  return localStorage.getItem(LAST_TOURNAMENT_KEY);
}

// ─── Limpiar (logout de un torneo) ───────────────────────────────────────────

export function clearTournamentTokens(tournamentCode: string) {
  localStorage.removeItem(ADMIN_KEY(tournamentCode));
  localStorage.removeItem(MEMBER_KEY(tournamentCode));
}
