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

  // Pick 6 random icon players, excluding any that are already claimed.
  // An icon is "claimed" if either:
  //   • It already lives in team_players (claimed in a previous season and
  //     materialized by /season/next, or assigned as part of a team's roster).
  //   • It was bought during the CURRENT market session (not yet materialized
  //     to team_players, but still off-limits).
  const { data: allIcons } = await supabase
    .from("players").select("id").eq("is_icon", true);

  if (!allIcons || allIcons.length === 0) {
    return NextResponse.json({ error: "No hay íconos disponibles." }, { status: 422 });
  }

  const allIconIds = (allIcons as any[]).map((p) => p.id);

  // 1) Icons currently sitting in some team's roster (materialized claims).
  const { data: ownedRows } = await supabase
    .from("team_players")
    .select("player_id")
    .in("player_id", allIconIds);
  const ownedIconIds = new Set((ownedRows ?? []).map((r: any) => r.player_id));

  // 2) Icons just bought in the active market session (still pending
  //    materialization until the next /season/next).
  const { data: currentTransfers } = await supabase
    .from("market_transfers")
    .select("player_id")
    .eq("session_id", sessionId)
    .in("transfer_type", ["clause", "offer", "icon_auction"])
    .in("player_id", allIconIds);
  const currentSessionIconIds = new Set((currentTransfers ?? []).map((t: any) => t.player_id));

  const availableIcons = allIconIds.filter(
    (id: string) => !ownedIconIds.has(id) && !currentSessionIconIds.has(id)
  );

  if (availableIcons.length === 0) {
    return NextResponse.json({ error: "Todos los íconos ya fueron subastados." }, { status: 422 });
  }

  const shuffled = shuffle(availableIcons);
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
