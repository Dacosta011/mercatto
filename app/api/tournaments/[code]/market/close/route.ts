import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/market/close ────────────────────────────────
// Admin only. Marks market as finished and returns tournament to lobby.
// Transfers are preserved as ownership history for future market sessions.

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  await supabase
    .from("market_sessions")
    .update({ status: "finished", finished_at: new Date().toISOString() })
    .eq("tournament_id", auth.tournamentId);

  const { error } = await supabase
    .from("tournaments")
    .update({ status: "lobby" })
    .eq("id", auth.tournamentId);

  if (error) {
    return NextResponse.json({ error: "Error al cerrar el mercado." }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
