-- ─── Discipline: player-level tracking ───────────────────────────────────────
-- Run this after migration_league.sql

-- Add player reference to discipline events
alter table discipline
  add column if not exists player_id uuid references players(id),
  add column if not exists player_name text; -- denormalized for fast reads

-- Add player reference to suspensions
alter table suspensions
  add column if not exists player_id uuid references players(id),
  add column if not exists player_name text;

-- Store pending player cards as JSON until the second player confirms
alter table fixtures
  add column if not exists pending_cards jsonb default '[]'::jsonb;
