-- ============================================================
-- Slot Machine Backend Migration
-- Run in Supabase SQL editor
-- ============================================================

-- 1. Daily pool table
CREATE TABLE IF NOT EXISTS slot_machine_pool (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id        UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  pool_date            DATE NOT NULL,
  player_id            UUID NOT NULL REFERENCES players(id),
  ovr                  INTEGER NOT NULL,
  is_premium           BOOLEAN NOT NULL DEFAULT false,  -- OVR > 80 = premium (no replacement if claimed)
  status               TEXT NOT NULL DEFAULT 'available',  -- available | claimed | empty
  claimed_by_member_id UUID REFERENCES members(id),
  claimed_by_name      TEXT,
  claimed_at           TIMESTAMPTZ,
  UNIQUE(tournament_id, pool_date, player_id)
);

-- 2. Spin results (server-decided, tamper-proof)
CREATE TABLE IF NOT EXISTS slot_machine_spins (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id    UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  member_id        UUID NOT NULL REFERENCES members(id),
  pool_slot_id     UUID REFERENCES slot_machine_pool(id),  -- the pool slot that won
  reel1_player_id  UUID REFERENCES players(id),
  reel2_player_id  UUID REFERENCES players(id),
  reel3_player_id  UUID REFERENCES players(id),
  is_win           BOOLEAN NOT NULL DEFAULT false,
  win_player_id    UUID REFERENCES players(id),
  status           TEXT NOT NULL DEFAULT 'pending',  -- pending | accepted | rejected | expired
  spun_at          TIMESTAMPTZ DEFAULT now(),
  expires_at       TIMESTAMPTZ DEFAULT now() + interval '5 minutes',
  CONSTRAINT valid_status CHECK (status IN ('pending','accepted','rejected','expired'))
);

-- 3. Add salary column to players if it doesn't exist
ALTER TABLE players ADD COLUMN IF NOT EXISTS salary BIGINT DEFAULT 0;

-- 4. Realtime
ALTER TABLE slot_machine_pool  REPLICA IDENTITY FULL;
ALTER TABLE slot_machine_spins REPLICA IDENTITY FULL;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE slot_machine_pool;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE slot_machine_spins;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 5. Indexes
CREATE INDEX IF NOT EXISTS idx_smp_tournament_date ON slot_machine_pool(tournament_id, pool_date);
CREATE INDEX IF NOT EXISTS idx_sms_member ON slot_machine_spins(member_id, status);
