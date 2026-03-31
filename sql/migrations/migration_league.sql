-- ─── League Phase Tables ──────────────────────────────────────────────────────
-- Run this in the Supabase SQL editor after migration_market.sql

-- One league session per tournament
create table if not exists league_sessions (
  id                uuid primary key default gen_random_uuid(),
  tournament_id     uuid unique references tournaments(id) on delete cascade,
  status            text not null default 'pending',   -- pending | active | finished
  current_matchday  integer not null default 1,
  total_matchdays   integer not null default 0,
  started_at        timestamptz,
  finished_at       timestamptz,
  created_at        timestamptz default now()
);

-- One row per match (home vs away)
create table if not exists fixtures (
  id                      uuid primary key default gen_random_uuid(),
  session_id              uuid references league_sessions(id) on delete cascade,
  matchday                integer not null,
  home_member_id          uuid references members(id),
  away_member_id          uuid references members(id),
  status                  text not null default 'pending',  -- pending | in_progress | finished
  -- Start confirmations
  home_confirmed          boolean not null default false,
  away_confirmed          boolean not null default false,
  -- Pending result (first player to submit)
  pending_home_goals      integer,
  pending_away_goals      integer,
  pending_home_yellow     integer,
  pending_away_yellow     integer,
  pending_home_red        integer,
  pending_away_red        integer,
  result_submitter_id     uuid references members(id),
  -- Final confirmed result
  home_goals              integer,
  away_goals              integer,
  home_yellow             integer not null default 0,
  away_yellow             integer not null default 0,
  home_red                integer not null default 0,
  away_red                integer not null default 0,
  started_at              timestamptz,
  finished_at             timestamptz,
  created_at              timestamptz default now()
);

-- Who rests each matchday when odd number of participants
create table if not exists matchday_rests (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid references league_sessions(id) on delete cascade,
  matchday    integer not null,
  member_id   uuid references members(id),
  unique(session_id, matchday)
);

-- Individual card events (derived from fixture results for discipline tracking)
create table if not exists discipline (
  id          uuid primary key default gen_random_uuid(),
  session_id  uuid references league_sessions(id) on delete cascade,
  member_id   uuid references members(id),
  fixture_id  uuid references fixtures(id),
  card_type   text not null,   -- yellow | red
  matchday    integer not null,
  created_at  timestamptz default now()
);

-- Active suspensions per member
create table if not exists suspensions (
  id                uuid primary key default gen_random_uuid(),
  session_id        uuid references league_sessions(id) on delete cascade,
  member_id         uuid references members(id),
  reason            text not null,    -- red_card | yellow_accumulation
  from_matchday     integer not null, -- suspension starts (member misses this matchday)
  matches_remaining integer not null default 1,
  created_at        timestamptz default now()
);

-- Enable realtime for live updates
alter publication supabase_realtime add table fixtures;
alter publication supabase_realtime add table league_sessions;
alter publication supabase_realtime add table suspensions;
