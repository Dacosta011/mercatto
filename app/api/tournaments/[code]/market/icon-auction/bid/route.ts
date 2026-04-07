import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { getMinBid } from "@/lib/iconAuction";

type Params = { params: Promise<{ code: string }> };

async function finishAuction(
  supabase: ReturnType<typeof createServerClient>,
  auctionId: string,
  sessionId: string,
  tournamentId: string,
  selectedIconId: string,
  highestBid: number,
  highestBidderId: string,
  remaining: string[],
) {
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
    highest_bid: highestBid,
    highest_bidder_id: highestBidderId,
    bidder_order: remaining,
    winner_id: highestBidderId,
    final_amount: highestBid,
  }).eq("id", auctionId);

  return { ok: true, finished: true, winnerId: highestBidderId };
}

// POST /api/tournaments/[code]/market/icon-auction/bid
// Body: { amount: number }
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  const amount: number = body.amount;
  if (!amount || typeof amount !== "number" || amount <= 0) {
    return NextResponse.json({ error: "Cantidad inválida." }, { status: 400 });
  }

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

  const { data: member } = await supabase
    .from("members").select("budget, market_purchases")
    .eq("id", auth.memberId).single();

  const budget = (member as any)?.budget ?? 0;
  const purchases = (member as any)?.market_purchases ?? 0;

  if (purchases >= 3) {
    return NextResponse.json({ error: "Has alcanzado el límite de compras." }, { status: 422 });
  }

  // One icon per participant
  const { data: previousWin } = await supabase
    .from("icon_auctions").select("id")
    .eq("session_id", (session as any).id)
    .eq("winner_id", auth.memberId).maybeSingle();
  if (previousWin) {
    return NextResponse.json({ error: "Ya ganaste un ícono en este mercado." }, { status: 422 });
  }

  if (amount > budget) {
    return NextResponse.json({ error: "Presupuesto insuficiente." }, { status: 422 });
  }

  const selectedIconId = (auction as any).selected_icon_id;
  const { data: icon } = await supabase
    .from("players").select("ovr").eq("id", selectedIconId).single();
  const minBid = getMinBid((icon as any)?.ovr ?? 88);
  const highestBid: number = (auction as any).highest_bid ?? 0;

  if (amount < minBid) {
    return NextResponse.json({ error: `La puja mínima es ${minBid}.` }, { status: 422 });
  }
  if (amount <= highestBid) {
    return NextResponse.json({ error: `Debes superar la puja actual de ${highestBid}.` }, { status: 422 });
  }

  // Record the bid
  await supabase.from("icon_bids").insert({
    auction_id: auctionId, member_id: auth.memberId, amount, passed: false,
  });

  // After this bid, minimum required to outbid = amount + 5M
  const minNextBid = amount + 5_000_000;

  // Auto-remove from bidder order anyone who can't afford to outbid
  // The current bidder always stays regardless (they just bid)
  const others = bidderOrder.filter(id => id !== auth.memberId);
  let remaining: string[];

  if (others.length > 0) {
    const { data: budgets } = await supabase
      .from("members").select("id, budget").in("id", others);
    const canAffordSet = new Set(
      (budgets ?? []).filter((m: any) => (m.budget ?? 0) >= minNextBid).map((m: any) => m.id)
    );
    const keptOthers = others.filter(id => canAffordSet.has(id));
    remaining = [auth.memberId, ...keptOthers]; // current bidder first, then remaining others in their original relative order
    // Preserve original relative order
    remaining = bidderOrder.filter(id => id === auth.memberId || canAffordSet.has(id));
  } else {
    remaining = [auth.memberId];
  }

  // If only the current bidder remains, they win immediately
  if (remaining.length === 1) {
    const result = await finishAuction(
      supabase, auctionId, (session as any).id, auth.tournamentId,
      selectedIconId, amount, auth.memberId, remaining
    );
    return NextResponse.json(result);
  }

  // Advance to next bidder in the remaining list
  const myNewIndex = remaining.indexOf(auth.memberId);
  const nextIndex = (myNewIndex + 1) % remaining.length;

  await supabase.from("icon_auctions").update({
    highest_bid: amount,
    highest_bidder_id: auth.memberId,
    consecutive_passes: 0,
    current_bidder_index: nextIndex,
    bidder_order: remaining,
  }).eq("id", auctionId);

  return NextResponse.json({ ok: true, finished: false });
}
