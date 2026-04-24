import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { shuffle } from "@/lib/iconAuction";

type Params = { params: Promise<{ code: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
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

  const { data: auction } = await supabase
    .from("icon_auctions").select("id, phase, reroll_votes, presented_icon_ids")
    .eq("session_id", sessionId).eq("round_num", currentRound).maybeSingle();

  if (!auction || (auction as any).phase !== "vote_icon") {
    return NextResponse.json({ error: "No hay votación de ícono activa." }, { status: 400 });
  }

  const auctionId = (auction as any).id;
  const currentVotes: string[] = (auction as any).reroll_votes ?? [];

  if (currentVotes.includes(auth.memberId)) {
    return NextResponse.json({ error: "Ya votaste por reroll." }, { status: 409 });
  }

  const { data: membersRaw } = await supabase
    .from("members").select("id")
    .eq("tournament_id", auth.tournamentId);
  const totalMembers = membersRaw?.length ?? 0;
  const majority = Math.ceil(totalMembers / 2);

  const newVotes = [...currentVotes, auth.memberId];

  if (newVotes.length >= majority) {
    // Majority reached: reshuffle icons, reset votes, clear selection votes
    const { data: allIcons } = await supabase
      .from("players").select("id").eq("is_icon", true);

    if (!allIcons || allIcons.length === 0) {
      return NextResponse.json({ error: "No hay íconos disponibles." }, { status: 422 });
    }

    const allIconIds = (allIcons as any[]).map((p: any) => p.id);

    // Same filter logic as /icon-auction/initiate: exclude icons that already
    // live in team_players (materialized claims) and icons just bought in the
    // current market session.
    const { data: ownedRows } = await supabase
      .from("team_players")
      .select("player_id")
      .in("player_id", allIconIds);
    const ownedIconIds = new Set((ownedRows ?? []).map((r: any) => r.player_id));

    const { data: currentTransfers } = await supabase
      .from("market_transfers")
      .select("player_id")
      .eq("session_id", sessionId)
      .in("transfer_type", ["clause", "offer", "icon_auction"])
      .in("player_id", allIconIds);
    const currentSessionIconIds = new Set((currentTransfers ?? []).map((t: any) => t.player_id));

    const oldIds: string[] = (auction as any).presented_icon_ids ?? [];
    const allAvailable = allIconIds.filter(
      (id: string) => !ownedIconIds.has(id) && !currentSessionIconIds.has(id)
    );
    const available = allAvailable.filter((id: string) => !oldIds.includes(id));
    const pool = available.length >= 6 ? available : allAvailable;
    const newPresented = shuffle(pool).slice(0, Math.min(6, pool.length));

    await supabase
      .from("icon_selection_votes").delete().eq("auction_id", auctionId);

    await supabase
      .from("icon_auctions").update({
        presented_icon_ids: newPresented,
        reroll_votes: [],
      }).eq("id", auctionId);

    return NextResponse.json({ ok: true, rerolled: true });
  }

  await supabase
    .from("icon_auctions").update({ reroll_votes: newVotes }).eq("id", auctionId);

  return NextResponse.json({ ok: true, rerolled: false, votes: newVotes.length, needed: majority });
}
