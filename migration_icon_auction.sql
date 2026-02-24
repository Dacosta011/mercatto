-- ============================================================================
-- Mercatto — Icon Auction migration
-- Run in Supabase SQL editor ONCE.
-- ============================================================================

-- 1. Add is_icon flag to players
ALTER TABLE players ADD COLUMN IF NOT EXISTS is_icon boolean DEFAULT false;

-- 2. Seed icon players (legendary players, separate from regular squad)
INSERT INTO players (name, ovr, position, country_name, is_icon, price, clause) VALUES
  ('Ronaldo Nazário',       94, 'DC',  'Brasil',     true, 0, 0),
  ('Carles Puyol',          89, 'DFC', 'España',     true, 0, 0),
  ('Andrés Iniesta',        92, 'MCO', 'España',     true, 0, 0),
  ('Iván Córdoba',          87, 'DFC', 'Colombia',   true, 0, 0),
  ('Thierry Henry',         91, 'EI',  'Francia',    true, 0, 0),
  ('Andrea Pirlo',          90, 'MCD', 'Italia',     true, 0, 0),
  ('Xabi Alonso',           87, 'MC',  'España',     true, 0, 0),
  ('Steven Gerrard',        88, 'MC',  'Inglaterra', true, 0, 0),
  ('Zlatan Ibrahimović',    91, 'DC',  'Suecia',     true, 0, 0),
  ('Lilian Thuram',         88, 'DFC', 'Francia',    true, 0, 0),
  ('Agáchate y conócelo',   89, 'MC',  'Colombia',   true, 0, 0),
  ('Samuel Eto''o',         89, 'DC',  'Camerún',    true, 0, 0),
  ('Patrick Vieira',        88, 'MC',  'Francia',    true, 0, 0)
ON CONFLICT (name, ovr, position) DO NOTHING;

-- 3. Icon auctions table (one per market round per tournament)
CREATE TABLE IF NOT EXISTS icon_auctions (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id            uuid NOT NULL REFERENCES market_sessions(id) ON DELETE CASCADE,
  round_num             integer NOT NULL,
  phase                 text NOT NULL DEFAULT 'vote_activation',
  -- phase: vote_activation | vote_icon | bidding | finished | skipped
  presented_icon_ids    jsonb NOT NULL DEFAULT '[]'::jsonb,
  selected_icon_id      uuid REFERENCES players(id),
  bidder_order          jsonb,          -- JSON array of member IDs
  current_bidder_index  integer DEFAULT 0,
  highest_bid           bigint DEFAULT 0,
  highest_bidder_id     uuid REFERENCES members(id),
  consecutive_passes    integer DEFAULT 0,
  winner_id             uuid REFERENCES members(id),
  final_amount          bigint,
  created_at            timestamptz DEFAULT now(),
  UNIQUE(session_id, round_num)
);

-- 4. Phase A: Yes/No votes
CREATE TABLE IF NOT EXISTS icon_activation_votes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id  uuid NOT NULL REFERENCES icon_auctions(id) ON DELETE CASCADE,
  member_id   uuid NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  vote        boolean NOT NULL,
  created_at  timestamptz DEFAULT now(),
  UNIQUE(auction_id, member_id)
);

-- 5. Phase B: Icon selection votes
CREATE TABLE IF NOT EXISTS icon_selection_votes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id  uuid NOT NULL REFERENCES icon_auctions(id) ON DELETE CASCADE,
  member_id   uuid NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  icon_id     uuid NOT NULL REFERENCES players(id),
  created_at  timestamptz DEFAULT now(),
  UNIQUE(auction_id, member_id)
);

-- 6. Phase C: Bids
CREATE TABLE IF NOT EXISTS icon_bids (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id  uuid NOT NULL REFERENCES icon_auctions(id) ON DELETE CASCADE,
  member_id   uuid NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  amount      bigint NOT NULL,
  passed      boolean NOT NULL DEFAULT false,
  created_at  timestamptz DEFAULT now()
);

-- 7. Realtime
ALTER TABLE icon_auctions         REPLICA IDENTITY FULL;
ALTER TABLE icon_activation_votes REPLICA IDENTITY FULL;
ALTER TABLE icon_selection_votes  REPLICA IDENTITY FULL;
ALTER TABLE icon_bids             REPLICA IDENTITY FULL;

ALTER PUBLICATION supabase_realtime ADD TABLE icon_auctions;
ALTER PUBLICATION supabase_realtime ADD TABLE icon_activation_votes;
ALTER PUBLICATION supabase_realtime ADD TABLE icon_selection_votes;
ALTER PUBLICATION supabase_realtime ADD TABLE icon_bids;
