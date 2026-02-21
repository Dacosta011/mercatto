import { createClient, SupabaseClient } from "@supabase/supabase-js";

// ─── Browser Supabase singleton ───────────────────────────────────────────────
// Safe to import in Client Components. Uses NEXT_PUBLIC_ env vars.
// One instance per browser tab — Realtime channels are multiplexed over it.

let _client: SupabaseClient | null = null;

export function getBrowserClient(): SupabaseClient {
  if (_client) return _client;

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) {
    throw new Error("Faltan NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY");
  }

  _client = createClient(url, key, {
    realtime: { params: { eventsPerSecond: 10 } },
  });

  return _client;
}
