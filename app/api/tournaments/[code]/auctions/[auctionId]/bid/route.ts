import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { createNotification, createBulkNotifications } from "@/lib/notifications";

type Params = { params: Promise<{ code: string; auctionId: string }> };

const ANTI_SNIPE_THRESHOLD_MS = 2 * 60 * 1000;
const ANTI_SNIPE_EXTENSION_MS = 2 * 60 * 1000;

// ─── POST /api/tournaments/[code]/auctions/[auctionId]/bid ────────────────────
// Place a bid on an active eBay-style auction.
// Body: { amount }

export async function POST(request: NextRequest, { params }: Params) {
  const { code, auctionId } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { amount?: number };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (!body.amount || body.amount <= 0) {
    return NextResponse.json(
      { error: "Se requiere un monto válido." },
      { status: 400 }
    );
  }

  const { data: auction } = await supabase
    .from("icon_auctions")
    .select("*")
    .eq("id", auctionId)
    .maybeSingle();

  if (!auction) {
    return NextResponse.json(
      { error: "Subasta no encontrada." },
      { status: 404 }
    );
  }

  const a = auction as any;

  if (a.phase !== "active") {
    return NextResponse.json(
      { error: "La subasta no está activa." },
      { status: 409 }
    );
  }

  const now = Date.now();
  const endsAt = a.ends_at ? new Date(a.ends_at).getTime() : null;

  if (endsAt && endsAt < now) {
    return NextResponse.json(
      { error: "La subasta ha terminado." },
      { status: 409 }
    );
  }

  // Check icon slot
  const { data: myMember } = await supabase
    .from("members")
    .select("budget, budget_reserved, icon_slot_used")
    .eq("id", auth.memberId)
    .single();

  const mm = myMember as any;

  if (mm?.icon_slot_used) {
    return NextResponse.json(
      { error: "Ya usaste tu slot de ícono en este mercado." },
      { status: 422 }
    );
  }

  // Available budget = total budget minus reserved (for other auctions)
  // But if I already have a bid in THIS auction, that reservation should be freed
  const myCurrentReservation =
    a.highest_bidder_id === auth.memberId ? (a.highest_bid ?? 0) : 0;
  const availableBudget =
    (mm?.budget ?? 0) - (mm?.budget_reserved ?? 0) + myCurrentReservation;

  if (availableBudget < body.amount) {
    return NextResponse.json(
      { error: "Presupuesto disponible insuficiente." },
      { status: 422 }
    );
  }

  const BID_INCREMENT = 5_000_000;
  const minRequired = Math.max(a.min_bid ?? 0, (a.highest_bid ?? 0) + BID_INCREMENT);
  if (body.amount < minRequired) {
    return NextResponse.json(
      {
        error: `La puja debe ser al menos €${Math.ceil(minRequired / 1_000_000)}M.`,
      },
      { status: 422 }
    );
  }

  // Can't outbid yourself
  if (a.highest_bidder_id === auth.memberId) {
    return NextResponse.json(
      { error: "Ya tienes la puja más alta." },
      { status: 422 }
    );
  }

  // Record bid
  await supabase.from("icon_bids").insert({
    auction_id: auctionId,
    member_id: auth.memberId,
    amount: body.amount,
    passed: false,
  });

  const previousBidderId = a.highest_bidder_id;
  const previousBidAmount = a.highest_bid ?? 0;

  // Update auction highest bid
  const updateData: Record<string, any> = {
    highest_bid: body.amount,
    highest_bidder_id: auth.memberId,
  };

  // Anti-sniping: extend if bid in last 2 minutes
  if (endsAt && endsAt - now < ANTI_SNIPE_THRESHOLD_MS) {
    const newEndsAt = new Date(
      now + ANTI_SNIPE_EXTENSION_MS
    ).toISOString();
    updateData.ends_at = newEndsAt;
  }

  await supabase
    .from("icon_auctions")
    .update(updateData)
    .eq("id", auctionId);

  // Release previous bidder's reservation
  if (previousBidderId && previousBidderId !== auth.memberId) {
    const { data: prevMember } = await supabase
      .from("members")
      .select("budget_reserved")
      .eq("id", previousBidderId)
      .single();
    await supabase
      .from("members")
      .update({
        budget_reserved: Math.max(
          0,
          ((prevMember as any)?.budget_reserved ?? 0) - previousBidAmount
        ),
      })
      .eq("id", previousBidderId);
  }

  // Update my reservation: remove old reservation (if any) and add new
  const newReserved =
    (mm?.budget_reserved ?? 0) - myCurrentReservation + body.amount;
  await supabase
    .from("members")
    .update({ budget_reserved: Math.max(0, newReserved) })
    .eq("id", auth.memberId);

  // Get session for tournament_id
  const { data: sess } = await supabase
    .from("market_sessions")
    .select("tournament_id")
    .eq("id", a.session_id)
    .single();

  const tournamentId = (sess as any)?.tournament_id;

  // Get icon name and bidder name for notifications
  const { data: iconData } = await supabase
    .from("players")
    .select("name")
    .eq("id", a.selected_icon_id)
    .single();

  const iconName = (iconData as any)?.name ?? "ícono";

  const { data: bidderData } = await supabase
    .from("members")
    .select("display_name")
    .eq("id", auth.memberId)
    .single();

  const bidderName = (bidderData as any)?.display_name ?? "Alguien";

  // Notify previous highest bidder they've been outbid
  if (previousBidderId && previousBidderId !== auth.memberId && tournamentId) {
    await createNotification({
      supabase,
      memberId: previousBidderId,
      tournamentId,
      type: "auction_outbid",
      title: "Te han superado",
      body: `${bidderName} pujó €${Math.floor(body.amount / 1_000_000)}M por ${iconName}. ¡Contraataca!`,
      metadata: {
        auctionId,
        amount: body.amount,
        bidderId: auth.memberId,
      },
    });
  }

  return NextResponse.json({
    ok: true,
    newHighestBid: body.amount,
    endsAt: updateData.ends_at ?? a.ends_at,
    antiSnipeExtended: !!updateData.ends_at,
  });
}
