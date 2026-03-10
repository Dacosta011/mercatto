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
    .select("id, status")
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
    .select("name")
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
  // For counter-offers (parent_offer_id is set), the roles are swapped:
  // buyer_id = original player owner (who countered), seller_id = original buyer (who accepts).
  // The ACTUAL buyer (who pays) is the person accepting = auth.memberId (seller_id in the offer).
  // The ACTUAL seller (who receives money) is the other party = buyer_id in the offer.
  const isCounterOffer = !!o.parent_offer_id;
  const actualBuyerId = isCounterOffer ? o.seller_id : o.buyer_id;
  const actualSellerId = isCounterOffer ? o.buyer_id : o.seller_id;

  const { data: tSettings } = await supabase
    .from("tournaments")
    .select("max_transfers")
    .eq("id", auth.tournamentId)
    .single();

  const maxTransfers = (tSettings as any)?.max_transfers ?? 3;

  const { data: buyer } = await supabase
    .from("members")
    .select("budget, market_purchases")
    .eq("id", actualBuyerId)
    .single();

  if ((buyer as any)?.market_purchases >= maxTransfers) {
    return NextResponse.json(
      { error: `El comprador ya alcanzó el límite de ${maxTransfers} fichajes.` },
      { status: 422 }
    );
  }
  if ((buyer as any)?.budget < o.amount) {
    return NextResponse.json(
      { error: "El comprador ya no tiene suficiente presupuesto." },
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

  const buyerName =
    (
      await supabase
        .from("members")
        .select("display_name")
        .eq("id", actualBuyerId)
        .single()
    ).data?.display_name ?? "—";

  await createNotification({
    supabase,
    memberId: actualBuyerId,
    tournamentId: auth.tournamentId,
    type: "offer_accepted",
    title: "Oferta aceptada",
    body: `${sellerName} aceptó tu oferta por ${playerName}. ¡Bienvenido al equipo!`,
    metadata: { offerId, playerId: o.player_id, amount: o.amount },
  });

  return NextResponse.json({ ok: true, action: "accepted" });
}
