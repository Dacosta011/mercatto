import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { shuffle, getMinBid } from "@/lib/iconAuction";

type Params = { params: Promise<{ code: string }> };

// POST /api/tournaments/[code]/market/icon-auction/vote-icon
// Body: { iconId: string }
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  if (!body.iconId) return NextResponse.json({ error: "iconId requerido." }, { status: 400 });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions").select("id, current_round")
    .eq("tournament_id", auth.tournamentId).maybeSingle();
  if (!session) return NextResponse.json({ error: "Mercado no activo." }, { status: 409 });

  const { data: auction } = await supabase
    .from("icon_auctions").select("id, phase, presented_icon_ids")
    .eq("session_id", (session as any).id)
    .eq("round_num", (session as any).current_round).maybeSingle();

  if (!auction || (auction as any).phase !== "vote_icon") {
    return NextResponse.json({ error: "No hay votación de ícono activa." }, { status: 409 });
  }

  const auctionId = (auction as any).id;
  const presentedIds: string[] = (auction as any).presented_icon_ids ?? [];

  if (!presentedIds.includes(body.iconId)) {
    return NextResponse.json({ error: "Ícono no válido." }, { status: 400 });
  }

  // Already voted?
  const { data: existing } = await supabase
    .from("icon_selection_votes").select("id")
    .eq("auction_id", auctionId).eq("member_id", auth.memberId).maybeSingle();
  if (existing) return NextResponse.json({ error: "Ya votaste." }, { status: 409 });

  await supabase.from("icon_selection_votes").insert({
    auction_id: auctionId, member_id: auth.memberId, icon_id: body.iconId,
  });

  // Check if all members voted
  const { data: members } = await supabase
    .from("members").select("id, budget, market_purchases").eq("tournament_id", auth.tournamentId);
  const total = (members ?? []).length;

  const { data: allVotes } = await supabase
    .from("icon_selection_votes").select("icon_id").eq("auction_id", auctionId);

  if ((allVotes ?? []).length >= total) {
    // Count votes per icon
    const counts: Record<string, number> = {};
    for (const v of allVotes ?? []) {
      const id = (v as any).icon_id;
      counts[id] = (counts[id] ?? 0) + 1;
    }

    // Find max votes and pick winner (random tie-break)
    const maxVotes = Math.max(...Object.values(counts));
    const tied = Object.entries(counts).filter(([, c]) => c === maxVotes).map(([id]) => id);
    const selectedIconId = shuffle(tied)[0];

    // Get the icon's OVR to determine minimum bid
    const { data: iconData } = await supabase
      .from("players").select("ovr").eq("id", selectedIconId).single();
    const minBid = getMinBid((iconData as any)?.ovr ?? 88);

    // Check who already won an icon this session (can't win twice)
    const { data: prevWins } = await supabase
      .from("icon_auctions").select("winner_id")
      .eq("session_id", (session as any).id)
      .not("winner_id", "is", null);
    const alreadyWonSet = new Set((prevWins ?? []).map((w: any) => w.winner_id));

    // Only include members who can afford the minimum bid AND haven't won an icon AND have purchases remaining
    const eligible = (members ?? []).filter((m: any) =>
      (m.budget ?? 0) >= minBid &&
      (m.market_purchases ?? 0) < 3 &&
      !alreadyWonSet.has(m.id)
    ).map((m: any) => m.id);

    const bidderOrder = eligible.length > 0 ? shuffle(eligible) : [];

    await supabase.from("icon_auctions").update({
      phase: "bidding",
      selected_icon_id: selectedIconId,
      bidder_order: bidderOrder,
      current_bidder_index: 0,
      highest_bid: 0,
      consecutive_passes: 0,
    }).eq("id", auctionId);

    return NextResponse.json({ ok: true, phase: "bidding", selectedIconId, eligibleCount: bidderOrder.length });
  }

  return NextResponse.json({ ok: true, phase: "vote_icon" });
}
