-- ─── Postpone / Reactivate agreement fields ─────────────────────────────────
-- Run this in the Supabase SQL editor after migration_league.sql

-- Track who requested a postpone (null = no request pending)
alter table fixtures add column if not exists postpone_requested_by uuid references members(id);

-- Track who requested a reactivate (null = no request pending)
alter table fixtures add column if not exists reactivate_requested_by uuid references members(id);
