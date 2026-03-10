-- ============================================================================
-- Mercatto — Async Market v2 Migration
-- Run in Supabase SQL editor ONCE.
-- Transforms the synchronous turn-based market into a 24h async market.
-- ============================================================================

-- ─── 1. market_sessions: add time window columns ────────────────────────────
ALTER TABLE market_sessions
  ADD COLUMN IF NOT EXISTS opens_at  timestamptz,
  ADD COLUMN IF NOT EXISTS closes_at timestamptz,
  ADD COLUMN IF NOT EXISTS duration_hours integer NOT NULL DEFAULT 24;

-- ─── 2. market_offers: async negotiation support ────────────────────────────
-- expires_at: offer auto-expires if not responded
-- counter_amount: seller can counter with a different price
-- parent_offer_id: links counter-offer to original
ALTER TABLE market_offers
  ADD COLUMN IF NOT EXISTS expires_at      timestamptz,
  ADD COLUMN IF NOT EXISTS counter_amount  bigint,
  ADD COLUMN IF NOT EXISTS parent_offer_id uuid REFERENCES market_offers(id);

-- Drop the NOT NULL + turn_id FK requirement (async offers have no turn)
ALTER TABLE market_offers ALTER COLUMN turn_id DROP NOT NULL;

-- ─── 3. icon_auctions: eBay-style timed auctions ───────────────────────────
ALTER TABLE icon_auctions
  ADD COLUMN IF NOT EXISTS starts_at timestamptz,
  ADD COLUMN IF NOT EXISTS ends_at   timestamptz,
  ADD COLUMN IF NOT EXISTS min_bid   bigint NOT NULL DEFAULT 0;

-- ─── 4. members: icon auction slot tracking ─────────────────────────────────
ALTER TABLE members
  ADD COLUMN IF NOT EXISTS icon_slot_used boolean NOT NULL DEFAULT false;

-- ─── 5. notifications table ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id     uuid NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  tournament_id uuid NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  type          text NOT NULL,
  -- Types: offer_received, offer_accepted, offer_rejected, offer_expired,
  --        offer_countered, offer_expiring, clause_paid, clause_protected,
  --        auction_started, auction_outbid, auction_ending, auction_won,
  --        auction_lost, market_closing, market_closed, transfer_completed
  title         text NOT NULL,
  body          text,
  metadata      jsonb DEFAULT '{}'::jsonb,
  read          boolean NOT NULL DEFAULT false,
  created_at    timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notifications_member
  ON notifications(member_id, read, created_at DESC);

-- ─── 6. push_subscriptions table (Web Push API) ─────────────────────────────
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id  uuid NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  endpoint   text NOT NULL UNIQUE,
  p256dh     text NOT NULL,
  auth       text NOT NULL,
  created_at timestamptz DEFAULT now()
);

-- ─── 7. Realtime for notifications ──────────────────────────────────────────
ALTER TABLE notifications REPLICA IDENTITY FULL;
ALTER PUBLICATION supabase_realtime ADD TABLE notifications;

-- ─── 8. market_transfers: make turn_id nullable (async has no turns) ────────
ALTER TABLE market_transfers ALTER COLUMN turn_id DROP NOT NULL;
