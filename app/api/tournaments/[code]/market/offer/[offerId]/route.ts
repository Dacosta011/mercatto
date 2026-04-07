import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import {
  createNotification,
  offerExpiresAt,
} from "@/lib/notifications";

type Params = { params: Promise<{ code: string; offerId: string }> };

// ─── PATCH /api/tournaments/[code]/market/offer/[offerId] ─────────────────────
// Seller accepts, rejects, or counters an offer.
// Body: { action: "accept" | "reject" | "counter", counterAmount?: number }

export async function PATCH(request: NextRequest, { params }: Params) {
  const { code, offerId } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: {
    action: "accept" | "reject" | "counter";
    counterAmount?: number;
  };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  const { data: offer } = await supabase
    .from("market_offers")
    .select("*")
    .eq("id", offerId)
    .eq("seller_id", auth.memberId)
    .eq("status", "pending")
    .maybeSingle();

  if (!offer) {
    return NextResponse.json(
      { error: "Oferta no encontrada." },
      { status: 404 }
    );
  }

  const o = offer as any;

  // Check if offer expired
  if (o.expires_at && new Date(o.expires_at) < new Date()) {
    await supabase
      .from("market_offers")
      .update({ status: "expired", responded_at: new Date().toISOString() })
      .eq("id", offerId);
    return NextResponse.json(
      { error: "Esta oferta ha expirado." },
      { status: 410 }
    );
  }

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status, market_type, winter_max_transfers")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json(
      { error: "El mercado no está activo." },
      { status: 409 }
    );
  }

  const { data: playerData } = await supabase
    .from("players")
    .select("name, is_icon")
    .eq("id", o.player_id)
    .single();
  const playerName = (playerData as any)?.name ?? "jugador";

  const sellerName =
    (
      await supabase
        .from("members")
        .select("display_name")
        .eq("id", auth.memberId)
        .single()
    ).data?.display_name ?? "—";

  // ── Reject ────────────────────────────────────────────────────────────────
  if (body.action === "reject") {
    await supabase
      .from("market_offers")
      .update({ status: "rejected", responded_at: new Date().toISOString() })
      .eq("id", offerId);

    await createNotification({
      supabase,
      memberId: o.buyer_id,
      tournamentId: auth.tournamentId,
      type: "offer_rejected",
      title: "Oferta rechazada",
      body: `${sellerName} rechazó tu oferta por ${playerName}`,
      metadata: { offerId, playerId: o.player_id },
    });

    return NextResponse.json({ ok: true, action: "rejected" });
  }

  // ── Counter ───────────────────────────────────────────────────────────────
  if (body.action === "counter") {
    if (!body.counterAmount || body.counterAmount <= 0) {
      return NextResponse.json(
        { error: "Se requiere un monto de contra-oferta válido." },
        { status: 400 }
      );
    }

    // Mark original as countered
    await supabase
      .from("market_offers")
      .update({
        status: "countered",
        counter_amount: body.counterAmount,
        responded_at: new Date().toISOString(),
      })
      .eq("id", offerId);

    // Create new counter-offer with roles swapped so the original buyer
    // becomes the respondent (seller_id) and can accept/reject/counter.
    const expiresAt = offerExpiresAt();
    const { data: counterOffer } = await supabase
      .from("market_offers")
      .insert({
        session_id: (session as any).id,
        buyer_id: auth.memberId,
        seller_id: o.buyer_id,
        player_id: o.player_id,
        amount: body.counterAmount,
        expires_at: expiresAt,
        parent_offer_id: offerId,
      })
      .select("id")
      .single();

    await createNotification({
      supabase,
      memberId: o.buyer_id,
      tournamentId: auth.tournamentId,
      type: "offer_countered",
      title: "Contra-oferta recibida",
      body: `${sellerName} pide $${(body.counterAmount / 1_000_000).toFixed(0)}M por ${playerName}`,
      metadata: {
        offerId: (counterOffer as any)?.id,
        originalOfferId: offerId,
        playerId: o.player_id,
        counterAmount: body.counterAmount,
      },
    });

    return NextResponse.json({
      ok: true,
      action: "countered",
      counterOfferId: (counterOffer as any)?.id,
    });
  }

  // ── Accept ────────────────────────────────────────────────────────────────
  // Walk up the counter-offer chain to find the ROOT offer. The root offer
  // (parent_offer_id = null) always has the correct original roles:
  //   root.buyer_id  = the person who WANTS the player (actual buyer)
  //   root.seller_id = the person who OWNS the player (actual seller)
  let rootOffer = o;
  while (rootOffer.parent_offer_id) {
    const { data: parentOffer } = await supabase
      .from("market_offers")
      .select("*")
      .eq("id", rootOffer.parent_offer_id)
      .single();
    if (!parentOffer) break;
    rootOffer = parentOffer as any;
  }

  const actualBuyerId = rootOffer.buyer_id;
  const actualSellerId = rootOffer.seller_id;

  const { data: tSettings } = await supabase
    .from("tournaments")
    .select("max_transfers")
    .eq("id", auth.tournamentId)
    .single();

  const isWinterSession = (session as any).market_type === "winter";
  const maxTransfers = isWinterSession && (session as any).winter_max_transfers != null
    ? (session as any).winter_max_transfers
    : ((tSettings as any)?.max_transfers ?? 3);

  const { data: buyer } = await supabase
    .from("members")
    .select("budget, budget_reserved, market_purchases")
    .eq("id", actualBuyerId)
    .single();

  if ((buyer as any)?.market_purchases >= maxTransfers) {
    return NextResponse.json(
      { error: `El comprador ya alcanzó el límite de ${maxTransfers} fichajes.` },
      { status: 422 }
    );
  }
  const buyerAvailable = ((buyer as any)?.budget ?? 0) - ((buyer as any)?.budget_reserved ?? 0);
  if (buyerAvailable < o.amount) {
    return NextResponse.json(
      { error: "El comprador ya no tiene suficiente presupuesto disponible." },
      { status: 422 }
    );
  }

  // Resolve seller team for transfer record
  const { data: sellerAssignment } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("member_id", actualSellerId)
    .maybeSingle();

  const sellerTeamId = (sellerAssignment as any)?.team_id ?? null;

  // Deduct buyer budget + increment purchases
  await supabase
    .from("members")
    .update({
      budget: (buyer as any).budget - o.amount,
      market_purchases: (buyer as any).market_purchases + 1,
    })
    .eq("id", actualBuyerId);

  // Credit seller
  const { data: sellerMember } = await supabase
    .from("members")
    .select("budget")
    .eq("id", actualSellerId)
    .single();

  await supabase
    .from("members")
    .update({
      budget: ((sellerMember as any)?.budget ?? 0) + o.amount,
    })
    .eq("id", actualSellerId);

  // Record transfer
  await supabase.from("market_transfers").insert({
    session_id: (session as any).id,
    turn_id: null,
    buyer_id: actualBuyerId,
    seller_id: actualSellerId,
    seller_team_id: sellerTeamId,
    player_id: o.player_id,
    transfer_type: "offer",
    amount: o.amount,
  });

  // If icon, update clause to sale price + 30% so new owner doesn't lose money
  if ((playerData as any)?.is_icon) {
    const newClause = Math.round(o.amount * 1.3);
    await supabase.from("players").update({ clause: newClause }).eq("id", o.player_id);
  }

  // Mark offer accepted
  await supabase
    .from("market_offers")
    .update({ status: "accepted", responded_at: new Date().toISOString() })
    .eq("id", offerId);

  // Cancel all other pending offers for this player
  await supabase
    .from("market_offers")
    .update({ status: "cancelled", responded_at: new Date().toISOString() })
    .eq("session_id", (session as any).id)
    .eq("player_id", o.player_id)
    .eq("status", "pending");

  // Notify both parties with correct roles
  const buyerNameRes = await supabase
    .from("members")
    .select("display_name")
    .eq("id", actualBuyerId)
    .single();
  const actualBuyerName = buyerNameRes.data?.display_name ?? "—";

  const sellerNameRes = await supabase
    .from("members")
    .select("display_name")
    .eq("id", actualSellerId)
    .single();
  const actualSellerName = sellerNameRes.data?.display_name ?? "—";

  // Notify buyer: you got the player
  await createNotification({
    supabase,
    memberId: actualBuyerId,
    tournamentId: auth.tournamentId,
    type: "offer_accepted",
    title: "Fichaje completado",
    body: `¡Compraste a ${playerName} por $${(o.amount / 1_000_000).toFixed(0)}M!`,
    metadata: { offerId, playerId: o.player_id, amount: o.amount },
  });

  // Notify seller: you sold the player
  await createNotification({
    supabase,
    memberId: actualSellerId,
    tournamentId: auth.tournamentId,
    type: "offer_accepted",
    title: "Jugador vendido",
    body: `Vendiste a ${playerName} a ${actualBuyerName} por $${(o.amount / 1_000_000).toFixed(0)}M`,
    metadata: { offerId, playerId: o.player_id, amount: o.amount },
  });

  return NextResponse.json({ ok: true, action: "accepted" });
}
