import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { createNotification, offerExpiresAt } from "@/lib/notifications";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/market/offer ────────────────────────────────
// Async: any member can create an offer at any time during the market window.
// Body: { playerId, amount }

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { playerId?: string; amount?: number };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (!body.playerId || !body.amount || body.amount <= 0) {
    return NextResponse.json(
      { error: "Se requieren playerId y amount válidos." },
      { status: 400 }
    );
  }

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status, started_at, closes_at, market_type, winter_max_transfers")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json(
      { error: "El mercado no está activo." },
      { status: 409 }
    );
  }

  const s = session as any;

  // Check if market window has expired
  if (s.closes_at && new Date(s.closes_at) < new Date()) {
    return NextResponse.json(
      { error: "El mercado ha cerrado." },
      { status: 409 }
    );
  }

  // Tournament settings — winter sessions override with their own limits
  const { data: tSettings } = await supabase
    .from("tournaments")
    .select("max_transfers")
    .eq("id", auth.tournamentId)
    .single();

  const isWinterSession = s.market_type === "winter";
  const maxTransfers = isWinterSession && s.winter_max_transfers != null
    ? s.winter_max_transfers
    : ((tSettings as any)?.max_transfers ?? 3);

  // Check purchase limit
  const { data: myMember } = await supabase
    .from("members")
    .select("budget, budget_reserved, market_purchases")
    .eq("id", auth.memberId)
    .single();

  const mm = myMember as any;

  if (mm?.market_purchases >= maxTransfers) {
    return NextResponse.json(
      { error: `Ya alcanzaste el límite de ${maxTransfers} fichajes.` },
      { status: 422 }
    );
  }

  const availableBudget = (mm?.budget ?? 0) - (mm?.budget_reserved ?? 0);
  if (availableBudget < body.amount) {
    return NextResponse.json(
      { error: "Presupuesto disponible insuficiente para esa oferta." },
      { status: 422 }
    );
  }

  // Check player was not already sold in this market iteration
  const { data: alreadySold } = await supabase
    .from("market_transfers")
    .select("id")
    .eq("session_id", s.id)
    .eq("player_id", body.playerId)
    .in("transfer_type", ["clause", "offer", "icon_auction"])
    .gte("created_at", s.started_at)
    .limit(1);

  if ((alreadySold ?? []).length > 0) {
    return NextResponse.json(
      { error: "Este jugador ya fue transferido en este mercado." },
      { status: 422 }
    );
  }

  // Find effective seller (icons won't be in team_players)
  const { data: tp } = await supabase
    .from("team_players")
    .select("team_id")
    .eq("player_id", body.playerId)
    .maybeSingle();

  const { data: lastTransfer } = await supabase
    .from("market_transfers")
    .select("buyer_id")
    .eq("session_id", s.id)
    .eq("player_id", body.playerId)
    .in("transfer_type", ["clause", "offer", "icon_auction"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!tp && !lastTransfer) {
    return NextResponse.json(
      { error: "Jugador no encontrado en ningún equipo." },
      { status: 422 }
    );
  }

  let sellerId: string | undefined;
  if (lastTransfer) {
    sellerId = (lastTransfer as any).buyer_id;
  } else {
    const allMemberIds = (
      await supabase
        .from("members")
        .select("id")
        .eq("tournament_id", auth.tournamentId)
    ).data?.map((m: any) => m.id) ?? [];

    const { data: sellerAssignment } = await supabase
      .from("assignments")
      .select("member_id")
      .eq("team_id", (tp as any).team_id)
      .in("member_id", allMemberIds)
      .maybeSingle();

    sellerId = (sellerAssignment as any)?.member_id;
  }

  if (!sellerId || sellerId === auth.memberId) {
    return NextResponse.json(
      { error: "No puedes ofertar por tu propio jugador." },
      { status: 422 }
    );
  }

  // Prevent duplicate pending offers by the same buyer for the same player
  const { data: existingOffer } = await supabase
    .from("market_offers")
    .select("id")
    .eq("session_id", s.id)
    .eq("buyer_id", auth.memberId)
    .eq("player_id", body.playerId)
    .eq("status", "pending")
    .is("parent_offer_id", null)
    .limit(1);

  if ((existingOffer ?? []).length > 0) {
    return NextResponse.json(
      { error: "Ya tienes una oferta pendiente por este jugador." },
      { status: 422 }
    );
  }

  // Calculate offer expiration
  const expiresAt = offerExpiresAt();

  const { data: offer, error: offerErr } = await supabase
    .from("market_offers")
    .insert({
      session_id: s.id,
      turn_id: null,
      buyer_id: auth.memberId,
      seller_id: sellerId,
      player_id: body.playerId,
      amount: body.amount,
      expires_at: expiresAt,
    })
    .select("id")
    .single();

  if (offerErr) {
    return NextResponse.json(
      { error: "Error al crear la oferta." },
      { status: 500 }
    );
  }

  // Get player name for notification
  const { data: player } = await supabase
    .from("players")
    .select("name")
    .eq("id", body.playerId)
    .single();

  const buyerName = (
    await supabase
      .from("members")
      .select("display_name")
      .eq("id", auth.memberId)
      .single()
  ).data?.display_name ?? "Alguien";

  await createNotification({
    supabase,
    memberId: sellerId,
    tournamentId: auth.tournamentId,
    type: "offer_received",
    title: "Nueva oferta recibida",
    body: `${buyerName} ofrece $${(body.amount / 1_000_000).toFixed(0)}M por ${(player as any)?.name ?? "un jugador"}`,
    metadata: {
      offerId: (offer as any).id,
      playerId: body.playerId,
      buyerId: auth.memberId,
      amount: body.amount,
    },
  });

  return NextResponse.json(
    { ok: true, offerId: (offer as any).id, expiresAt },
    { status: 201 }
  );
}
