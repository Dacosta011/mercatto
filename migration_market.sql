-- ─── Market Phase Tables ──────────────────────────────────────────────────────

-- One market session per tournament
create table if not exists market_sessions (
  id             uuid primary key default gen_random_uuid(),
  tournament_id  uuid unique references tournaments(id) on delete cascade,
  status         text not null default 'pending',   -- pending | active | finished
  current_round  integer not null default 1,
  total_rounds   integer not null default 3,
  started_at     timestamptz,
  finished_at    timestamptz,
  created_at     timestamptz default now()
);

-- Turn order per round (one row = one participant slot per round)
create table if not exists market_turns (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid references market_sessions(id) on delete cascade,
  round_num     integer not null,
  position      integer not null,
  member_id     uuid references members(id) on delete cascade,
  status        text not null default 'pending',  -- pending | active | completed | skipped
  completed_at  timestamptz,
  unique(session_id, round_num, position)
);

-- Completed transfers (clause payments & accepted offers)
create table if not exists market_transfers (
  id              uuid primary key default gen_random_uuid(),
  session_id      uuid references market_sessions(id) on delete cascade,
  turn_id         uuid references market_turns(id),
  buyer_id        uuid references members(id),
  seller_id       uuid references members(id),
  seller_team_id  uuid references teams(id),   -- for clause-protection tracking
  player_id       uuid references players(id),
  transfer_type   text not null,                -- clause | offer | skip
  amount          bigint not null default 0,
  created_at      timestamptz default now()
);

-- Pending negotiated offers
create table if not exists market_offers (
  id            uuid primary key default gen_random_uuid(),
  session_id    uuid references market_sessions(id) on delete cascade,
  turn_id       uuid references market_turns(id),
  buyer_id      uuid references members(id),
  seller_id     uuid references members(id),
  player_id     uuid references players(id),
  amount        bigint not null,
  status        text not null default 'pending', -- pending | accepted | rejected | cancelled
  created_at    timestamptz default now(),
  responded_at  timestamptz
);

-- Track how many players each member has bought in the market
alter table members
  add column if not exists market_purchases integer not null default 0;
