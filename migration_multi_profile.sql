-- ─── Multi-profile social feed migration ─────────────────────────────────────
-- Run in Supabase SQL Editor BEFORE deploying the code changes.
--
-- What this does:
--   1. Removes the UNIQUE(member_id, tournament_id) constraint so a member
--      can have multiple social profiles per tournament.
--   2. Adds a `verified` boolean column to social_profiles.
--   3. Keeps existing profiles intact.

-- 1. Drop the unique constraint that was preventing multiple profiles
ALTER TABLE social_profiles
  DROP CONSTRAINT IF EXISTS social_profiles_member_id_tournament_id_key;

-- 2. Add verified column (defaults false)
ALTER TABLE social_profiles
  ADD COLUMN IF NOT EXISTS verified BOOLEAN NOT NULL DEFAULT FALSE;

-- 3. Add index for fast lookups by member + tournament
CREATE INDEX IF NOT EXISTS idx_social_profiles_member_tournament
  ON social_profiles(member_id, tournament_id);
