-- ─── Multi-Season Support ────────────────────────────────────────────────────
-- Run this in the Supabase SQL editor.
-- Adds the ability to play several seasons inside the same lobby:
--   • Each tournament tracks its current season number.
--   • When a new season is started, the previous season is archived into
--     season_archives + season_archive_fixtures + season_archive_assignments
--     (so champions, standings and matches stay queryable forever).

-- 1) Per-tournament season counter
alter table tournaments
  add column if not exists current_season integer not null default 1;

-- 2) One archive row per finished season
create table if not exists season_archives (
  id                     uuid primary key default gen_random_uuid(),
  tournament_id          uuid not null references tournaments(id) on delete cascade,
  season_number          integer not null,
  started_at             timestamptz,
  finished_at            timestamptz not null default now(),
  total_matchdays        integer,
  champion_member_id     uuid references members(id) on delete set null,
  champion_display_name  text,
  champion_team_id       uuid references teams(id) on delete set null,
  champion_team_name     text,
  standings              jsonb not null default '[]'::jsonb,
  discipline             jsonb not null default '[]'::jsonb,
  created_at             timestamptz not null default now(),
  unique (tournament_id, season_number)
);

create index if not exists idx_season_archives_tournament
  on season_archives (tournament_id, season_number desc);

grant delete, insert, references, select, trigger, truncate, update on season_archives to anon;
grant delete, insert, references, select, trigger, truncate, update on season_archives to authenticated;
grant delete, insert, references, select, trigger, truncate, update on season_archives to service_role;

-- 3) Snapshot of every fixture (so historical matches survive even if a
--    member or the active league_session is later deleted).
create table if not exists season_archive_fixtures (
  id                uuid primary key default gen_random_uuid(),
  archive_id        uuid not null references season_archives(id) on delete cascade,
  matchday          integer not null,
  home_member_id    uuid references members(id) on delete set null,
  away_member_id    uuid references members(id) on delete set null,
  home_display_name text,
  away_display_name text,
  home_team_name    text,
  away_team_name    text,
  home_goals        integer,
  away_goals        integer,
  status            text,
  finished_at       timestamptz
);

create index if not exists idx_season_archive_fixtures_archive
  on season_archive_fixtures (archive_id, matchday);

grant delete, insert, references, select, trigger, truncate, update on season_archive_fixtures to anon;
grant delete, insert, references, select, trigger, truncate, update on season_archive_fixtures to authenticated;
grant delete, insert, references, select, trigger, truncate, update on season_archive_fixtures to service_role;

-- 4) Snapshot of which team each member had when the season ended
create table if not exists season_archive_assignments (
  archive_id    uuid not null references season_archives(id) on delete cascade,
  member_id     uuid references members(id) on delete set null,
  display_name  text not null,
  team_id       uuid references teams(id) on delete set null,
  team_name     text not null,
  primary key (archive_id, display_name)
);

grant delete, insert, references, select, trigger, truncate, update on season_archive_assignments to anon;
grant delete, insert, references, select, trigger, truncate, update on season_archive_assignments to authenticated;
grant delete, insert, references, select, trigger, truncate, update on season_archive_assignments to service_role;

-- 5) Per-team budget carry-over between seasons. When a season ends, the
--    member's final budget is snapshotted onto the team they had. The next
--    time someone spins that team in this tournament, they inherit that
--    balance instead of recalculating from OVR. Teams that were never owned
--    fall back to the original OVR-based formula on spin.
create table if not exists team_budgets (
  tournament_id uuid not null references tournaments(id) on delete cascade,
  team_id       uuid not null references teams(id) on delete cascade,
  budget        bigint not null,
  updated_at    timestamptz not null default now(),
  primary key (tournament_id, team_id)
);

create index if not exists idx_team_budgets_tournament
  on team_budgets (tournament_id);

grant delete, insert, references, select, trigger, truncate, update on team_budgets to anon;
grant delete, insert, references, select, trigger, truncate, update on team_budgets to authenticated;
grant delete, insert, references, select, trigger, truncate, update on team_budgets to service_role;
