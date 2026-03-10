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
    .select("budget, icon_slot_used")
    .eq("id", auth.memberId)
    .single();

  if ((myMember as any)?.icon_slot_used) {
    return NextResponse.json(
      { error: "Ya usaste tu slot de ícono en este mercado." },
      { status: 422 }
    );
  }

  if ((myMember as any)?.budget < body.amount) {
    return NextResponse.json(
      { error: "Presupuesto insuficiente." },
      { status: 422 }
    );
  }

  // Bid must be higher than current highest and at least min_bid
  const minRequired = Math.max(a.min_bid ?? 0, (a.highest_bid ?? 0) + 1);
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
