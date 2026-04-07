import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { getMinBid } from "@/lib/iconAuction";

type Params = { params: Promise<{ code: string }> };

// Shared helper: finish the auction with a winner or no winner
async function finishAuction(
  supabase: ReturnType<typeof createServerClient>,
  auctionId: string,
  sessionId: string,
  tournamentId: string,
  selectedIconId: string,
  highestBid: number,
  highestBidderId: string | null,
  remaining: string[],
) {
  if (highestBid > 0 && highestBidderId) {
    const { data: winnerMember } = await supabase
      .from("members").select("budget, market_purchases")
      .eq("id", highestBidderId).single();

    await supabase.from("members").update({
      budget: ((winnerMember as any)?.budget ?? 0) - highestBid,
      market_purchases: ((winnerMember as any)?.market_purchases ?? 0) + 1,
    }).eq("id", highestBidderId);

    await supabase.from("market_transfers").insert({
      session_id: sessionId,
      buyer_id: highestBidderId,
      player_id: selectedIconId,
      transfer_type: "icon_auction",
      amount: highestBid,
    });

    // Set icon clause to auction price + 30% markup
    const newClause = Math.round(highestBid * 1.3);
    await supabase.from("players").update({ clause: newClause }).eq("id", selectedIconId);

    await supabase.from("icon_auctions").update({
      phase: "finished",
      bidder_order: remaining,
      winner_id: highestBidderId,
      final_amount: highestBid,
    }).eq("id", auctionId);

    return { ok: true, finished: true, winnerId: highestBidderId };
  }

  // No bids — no winner
  await supabase.from("icon_auctions").update({
    phase: "finished",
    bidder_order: remaining,
  }).eq("id", auctionId);

  return { ok: true, finished: true, winnerId: null };
}

// POST /api/tournaments/[code]/market/icon-auction/pass
// Permanently retires the member from the auction.
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions").select("id, current_round")
    .eq("tournament_id", auth.tournamentId).maybeSingle();
  if (!session) return NextResponse.json({ error: "Mercado no activo." }, { status: 409 });

  const { data: auction } = await supabase
    .from("icon_auctions").select("*")
    .eq("session_id", (session as any).id)
    .eq("round_num", (session as any).current_round).maybeSingle();

  if (!auction || (auction as any).phase !== "bidding") {
    return NextResponse.json({ error: "No hay subasta activa." }, { status: 409 });
  }

  const auctionId = (auction as any).id;
  const bidderOrder: string[] = (auction as any).bidder_order ?? [];
  const currentIndex: number = (auction as any).current_bidder_index ?? 0;
  const currentBidderId = bidderOrder[currentIndex % Math.max(1, bidderOrder.length)];

  if (currentBidderId !== auth.memberId) {
    return NextResponse.json({ error: "No es tu turno." }, { status: 403 });
  }

  const highestBid: number = (auction as any).highest_bid ?? 0;
  const highestBidderId: string | null = (auction as any).highest_bidder_id ?? null;
  const selectedIconId: string = (auction as any).selected_icon_id;

  // Record the retirement
  await supabase.from("icon_bids").insert({
    auction_id: auctionId, member_id: auth.memberId, amount: 0, passed: true,
  });

  // Permanently remove the current member from the bidder order
  let remaining = bidderOrder.filter(id => id !== auth.memberId);

  // Auto-remove anyone who can no longer afford the minimum next bid
  if (remaining.length > 0) {
    const { data: iconData } = await supabase
      .from("players").select("ovr").eq("id", selectedIconId).single();
    const minBid = getMinBid((iconData as any)?.ovr ?? 88);
    const minNextBid = highestBid > 0 ? highestBid + 5_000_000 : minBid;

    const { data: budgets } = await supabase
      .from("members").select("id, budget").in("id", remaining);
    const canAffordSet = new Set(
      (budgets ?? []).filter((m: any) => (m.budget ?? 0) >= minNextBid).map((m: any) => m.id)
    );
    remaining = remaining.filter(id => canAffordSet.has(id));
  }

  // No bidders left — finish with no winner
  if (remaining.length === 0) {
    const result = await finishAuction(
      supabase, auctionId, (session as any).id, auth.tournamentId,
      selectedIconId, highestBid, highestBidderId, remaining
    );
    return NextResponse.json(result);
  }

  // 1 bidder left AND there's already a highest bid — that bidder wins
  if (remaining.length === 1 && highestBid > 0 && highestBidderId) {
    const result = await finishAuction(
      supabase, auctionId, (session as any).id, auth.tournamentId,
      selectedIconId, highestBid, highestBidderId, remaining
    );
    return NextResponse.json(result);
  }

  // 1 bidder left but no bids yet — let them take their turn instead of finishing

  // Advance: the retired member was at currentIndex, so the next element
  // in the new array is already at currentIndex (array shrunk).
  const newIndex = currentIndex % remaining.length;

  await supabase.from("icon_auctions").update({
    bidder_order: remaining,
    current_bidder_index: newIndex,
  }).eq("id", auctionId);

  return NextResponse.json({ ok: true, finished: false });
}
