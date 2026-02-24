import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/market/close ────────────────────────────────
// Admin only. Closes the market without reverting transfers.
// Sets market_session status → "finished" and tournament status → "lobby".

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Mark session as finished (may already be "finished" but make it explicit)
  await supabase
    .from("market_sessions")
    .update({ status: "finished" })
    .eq("tournament_id", auth.tournamentId);

  // Return tournament to lobby status → triggers PhaseRedirectGuard on all clients
  const { error } = await supabase
    .from("tournaments")
    .update({ status: "lobby" })
    .eq("id", auth.tournamentId);

  if (error) {
    return NextResponse.json({ error: "Error al cerrar el mercado." }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
