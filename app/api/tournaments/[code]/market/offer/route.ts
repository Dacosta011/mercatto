import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/market/offer ────────────────────────────────
// Create a pending offer. Does NOT advance the turn — the turn advances when
// the seller accepts or rejects (PATCH /offer/[offerId]).
// Body: { playerId, amount }

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { playerId?: string; amount?: number };
  try { body = await request.json(); } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (!body.playerId || !body.amount) {
    return NextResponse.json({ error: "Se requieren playerId y amount." }, { status: 400 });
  }

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status, current_round")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json({ error: "El mercado no está activo." }, { status: 409 });
  }

  // Verify it's this member's active turn
  const { data: activeTurn } = await supabase
    .from("market_turns")
    .select("id")
    .eq("session_id", (session as any).id)
    .eq("round_num", (session as any).current_round)
    .eq("member_id", auth.memberId)
    .eq("status", "active")
    .maybeSingle();

  if (!activeTurn) return NextResponse.json({ error: "No es tu turno." }, { status: 403 });

  // Verify buyer hasn't hit purchase limit
  const { data: myMember } = await supabase
    .from("members")
    .select("budget, market_purchases")
    .eq("id", auth.memberId)
    .single();

  if ((myMember as any)?.market_purchases >= 3) {
    return NextResponse.json({ error: "Ya alcanzaste el límite de 3 compras." }, { status: 422 });
  }
  if ((myMember as any)?.budget < body.amount) {
    return NextResponse.json({ error: "Presupuesto insuficiente para esa oferta." }, { status: 422 });
  }

  // Block offers on players already sold in this session
  const { data: alreadySold } = await supabase
    .from("market_transfers")
    .select("id")
    .eq("session_id", (session as any).id)
    .eq("player_id", body.playerId)
    .limit(1);

  if ((alreadySold ?? []).length > 0) {
    return NextResponse.json({ error: "Este jugador ya fue transferido en este mercado." }, { status: 422 });
  }

  // Find player's current team + owner
  const { data: tp } = await supabase
    .from("team_players")
    .select("team_id")
    .eq("player_id", body.playerId)
    .single();

  if (!tp) return NextResponse.json({ error: "Jugador no encontrado en ningún equipo." }, { status: 422 });

  // Find the member who owns this team IN THIS tournament (not globally)
  const { data: sellerMember } = await supabase
    .from("members")
    .select("id, assignments!inner(team_id)")
    .eq("tournament_id", auth.tournamentId)
    .eq("assignments.team_id", (tp as any).team_id)
    .maybeSingle();

  const sellerId = (sellerMember as any)?.id;
  if (!sellerId || sellerId === auth.memberId) {
    return NextResponse.json({ error: "Jugador inválido." }, { status: 422 });
  }

  // Create offer — turn stays "active" until seller responds
  const { data: offer, error: offerErr } = await supabase
    .from("market_offers")
    .insert({
      session_id: (session as any).id,
      turn_id: (activeTurn as any).id,
      buyer_id: auth.memberId,
      seller_id: sellerId,
      player_id: body.playerId,
      amount: body.amount,
    })
    .select("id")
    .single();

  if (offerErr) return NextResponse.json({ error: "Error al crear la oferta." }, { status: 500 });

  return NextResponse.json({ ok: true, offerId: (offer as any).id }, { status: 201 });
}
