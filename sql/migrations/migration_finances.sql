-- Migration: club finances
-- Adds:
--   * club_expenses ledger (per member, per fixture).
--   * "auto_release" / "salary" / "yellow_card" / "red_card" semantics
--     are stored in club_expenses.expense_type.
--   * No schema change to market_transfers itself; the new transfer_type
--     "auto_release" is a free-form text value (transfer_type is text).
--
-- Run this in the Supabase SQL editor.

create table if not exists club_expenses (
  id            uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references tournaments(id) on delete cascade,
  member_id     uuid not null references members(id) on delete cascade,
  fixture_id    uuid references fixtures(id) on delete set null,
  matchday      integer,
  expense_type  text not null,         -- salary | yellow_card | red_card | auto_release
  player_id     uuid references players(id) on delete set null,
  player_name   text,
  amount        bigint not null,       -- positive = expense; for auto_release this is the cash recovered (sign-flipped meaning, see below)
  is_credit     boolean not null default false, -- true when this row CREDITS the budget (e.g. auto_release recovery)
  created_at    timestamptz not null default now()
);

create index if not exists idx_club_expenses_member  on club_expenses(member_id);
create index if not exists idx_club_expenses_fixture on club_expenses(fixture_id);
create index if not exists idx_club_expenses_tournament_created
  on club_expenses(tournament_id, created_at desc);

comment on table club_expenses is
  'Per-member ledger of finance movements derived from league activity (salaries, card fines, auto-released signings).';
