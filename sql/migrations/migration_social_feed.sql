-- ─── Social Feed Migration ───────────────────────────────────────────────────
-- Run this in your Supabase SQL editor before using the Feed feature.

-- Social profiles (one per member per tournament)
CREATE TABLE IF NOT EXISTS social_profiles (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  member_id    UUID        NOT NULL REFERENCES members(id)     ON DELETE CASCADE,
  tournament_id UUID       NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  username     TEXT        NOT NULL CHECK (char_length(trim(username)) >= 2),
  photo_url    TEXT,       -- base64 data URL or external URL
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(member_id, tournament_id)
);

-- Posts
CREATE TABLE IF NOT EXISTS posts (
  id            UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  member_id     UUID        NOT NULL REFERENCES members(id)     ON DELETE CASCADE,
  tournament_id UUID        NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
  content       TEXT,
  image_url     TEXT,       -- base64 data URL for attached images
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT content_or_image CHECK (content IS NOT NULL OR image_url IS NOT NULL)
);

-- Post likes (unique per user per post)
CREATE TABLE IF NOT EXISTS post_likes (
  id         UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  post_id    UUID        NOT NULL REFERENCES posts(id)   ON DELETE CASCADE,
  member_id  UUID        NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(post_id, member_id)
);
