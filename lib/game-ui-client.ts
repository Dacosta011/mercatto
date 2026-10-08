import type { GameState, GameCompetition, GameMarket } from './game-types';
import { saveMemberId, saveUserProfile, saveTeamAssignment, saveTournamentStatus, saveMarketOpen, getAdminToken } from './tokenStorage';

// Retain the same operation key after a transport failure, including across reloads.
// Request signatures contain no tokens; only the key is stored in sessionStorage.
export async function gamePost(path: string, body: object, token?: string) {
  const signature = JSON.stringify([path, body]);
  const storageKey = `mercatto:request:${signature}`;
  const key = sessionStorage.getItem(storageKey) || crypto.randomUUID();
  sessionStorage.setItem(storageKey, key);
  const response = await fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Idempotency-Key': key, ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
  const data = await response.json();
  if (!response.ok) {
    if (response.status < 500) sessionStorage.removeItem(storageKey);
    throw new Error(data.error || 'No se pudo completar la operación.');
  }
  sessionStorage.removeItem(storageKey);
  return data;
}

export function syncGameNavigation(state: GameState, competition: GameCompetition, market: GameMarket) {
  const code = state.code;
  saveMemberId(code, state.memberId);
  saveUserProfile(code, state.members.find(m => m.id === state.memberId)?.name || 'Participante', getAdminToken(code) ? 'admin' : 'member');
  const club = state.clubs.find(c => c.memberId === state.memberId);
  if (club) saveTeamAssignment(code, club.name);
  else {
    localStorage.removeItem(`mercatto:team:${code}`);
    localStorage.removeItem(`mercatto:teamCrest:${code}`);
  }
  saveTournamentStatus(code, competition.phase === 'finished' ? 'complete' : competition.phase === 'league' ? 'league' : market.window?.status === 'open' ? 'market' : 'lobby');
  saveMarketOpen(code, market.window?.status === 'open');
}
