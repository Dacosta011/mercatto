import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";
import { shuffle } from "@/lib/iconAuction";

type Params = { params: Promise<{ code: string }> };

// POST /api/tournaments/[code]/market/icon-auction/initiate
// Admin only. Starts Phase A voting for the current round.
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions").select("id, current_round, status")
    .eq("tournament_id", auth.tournamentId).maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json({ error: "El mercado no está activo." }, { status: 409 });
  }

  const sessionId = (session as any).id;
  const currentRound = (session as any).current_round;

  // Check auction doesn't already exist for this round
  const { data: existing } = await supabase
    .from("icon_auctions").select("id, phase")
    .eq("session_id", sessionId).eq("round_num", currentRound).maybeSingle();

  if (existing) {
    return NextResponse.json({ error: "Ya existe una subasta para esta ronda.", auction: existing }, { status: 409 });
  }

  // Verify all turns in current round are done
  const { data: activeTurns } = await supabase
    .from("market_turns").select("id")
    .eq("session_id", sessionId).eq("round_num", currentRound)
    .in("status", ["pending", "active"]);

  if ((activeTurns ?? []).length > 0) {
    return NextResponse.json({ error: "La ronda aún no ha terminado." }, { status: 400 });
  }

  // Pick 6 random icon players to present
  const { data: allIcons } = await supabase
    .from("players").select("id").eq("is_icon", true);

  if (!allIcons || allIcons.length === 0) {
    return NextResponse.json({ error: "No hay íconos disponibles." }, { status: 422 });
  }

  const shuffled = shuffle((allIcons as any[]).map((p) => p.id));
  const presentedIds = shuffled.slice(0, Math.min(6, shuffled.length));

  const { data: auction, error } = await supabase
    .from("icon_auctions").insert({
      session_id: sessionId,
      round_num: currentRound,
      phase: "vote_activation",
      presented_icon_ids: presentedIds,
    }).select("id").single();

  if (error || !auction) {
    return NextResponse.json({ error: "Error al crear la subasta." }, { status: 500 });
  }

  return NextResponse.json({ ok: true, auctionId: (auction as any).id });
}
