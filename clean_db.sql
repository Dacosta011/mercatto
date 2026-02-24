-- ─── Limpieza completa de datos del torneo ───────────────────────────────────
-- Conserva: players, teams, team_players
-- Elimina todo lo demás en orden seguro (respetando foreign keys)

begin;

-- Liga
delete from suspensions;
delete from discipline;
delete from matchday_rests;
delete from fixtures;
delete from league_sessions;

-- Mercado
delete from market_offers;
delete from market_transfers;
delete from market_turns;
delete from market_sessions;

-- Torneo
delete from assignments;
delete from members;
delete from tournaments;

commit;
