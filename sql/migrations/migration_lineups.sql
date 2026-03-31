-- ─── Lineup Persistence ──────────────────────────────────────────────────────
-- One saved lineup per member (formation + slot-to-player mapping).
-- Run this in the Supabase SQL editor.

create table if not exists lineups (
  id          uuid primary key default gen_random_uuid(),
  member_id   uuid unique references members(id) on delete cascade,
  formation   text not null default '4-3-3',
  slots       jsonb not null default '{}',
  updated_at  timestamptz default now()
);
