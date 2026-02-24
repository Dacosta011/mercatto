import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/market/action ───────────────────────────────
// Body: { type: "clause" | "skip", playerId?: string }

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { type: string; playerId?: string };
  try { body = await request.json(); } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  // ── Verify session ────────────────────────────────────────────────────────
  const { data: session } = await supabase
    .from("market_sessions")
    .select("*")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json({ error: "El mercado no está activo." }, { status: 409 });
  }

  // ── Verify it's this member's turn ────────────────────────────────────────
  const { data: activeTurn } = await supabase
    .from("market_turns")
    .select("id, position")
    .eq("session_id", (session as any).id)
    .eq("round_num", (session as any).current_round)
    .eq("member_id", auth.memberId)
    .eq("status", "active")
    .maybeSingle();

  if (!activeTurn) {
    return NextResponse.json({ error: "No es tu turno." }, { status: 403 });
  }

  const turnId = (activeTurn as any).id;

  // ── Clause payment ────────────────────────────────────────────────────────
  if (body.type === "clause") {
    if (!body.playerId) {
      return NextResponse.json({ error: "Se requiere playerId." }, { status: 400 });
    }

    // Check purchase limit
    const { data: myMember } = await supabase
      .from("members")
      .select("budget, market_purchases")
      .eq("id", auth.memberId)
      .single();

    if ((myMember as any)?.market_purchases >= 3) {
      return NextResponse.json({ error: "Ya compraste el máximo de 3 jugadores." }, { status: 422 });
    }

    // Get player
    const { data: player } = await supabase
      .from("players")
      .select("id, name, clause")
      .eq("id", body.playerId)
      .single();

    if (!player) return NextResponse.json({ error: "Jugador no encontrado." }, { status: 404 });

    const clauseAmount = (player as any).clause ?? 0;

    if ((myMember as any)?.budget < clauseAmount) {
      return NextResponse.json({ error: "Presupuesto insuficiente." }, { status: 422 });
    }

    // Find player's current team
    const { data: tp } = await supabase
      .from("team_players")
      .select("team_id")
      .eq("player_id", body.playerId)
      .single();

    if (!tp) return NextResponse.json({ error: "El jugador no está en ningún equipo." }, { status: 422 });
    const sellerTeamId = (tp as any).team_id;

    // Check clause protection
    const { data: prot } = await supabase
      .from("market_transfers")
      .select("id")
      .eq("session_id", (session as any).id)
      .eq("seller_team_id", sellerTeamId)
      .eq("transfer_type", "clause")
      .limit(1);

    if ((prot ?? []).length > 0) {
      return NextResponse.json({ error: "Ese equipo ya está protegido contra cláusulas." }, { status: 422 });
    }

    // Find seller member scoped to THIS tournament
    const { data: sellerMember } = await supabase
      .from("members")
      .select("id, assignments!inner(team_id)")
      .eq("tournament_id", auth.tournamentId)
      .eq("assignments.team_id", sellerTeamId)
      .maybeSingle();
    const sellerId = (sellerMember as any)?.id;

    // Deduct buyer budget + increment purchases
    await supabase
      .from("members")
      .update({
        budget: (myMember as any).budget - clauseAmount,
        market_purchases: (myMember as any).market_purchases + 1,
      })
      .eq("id", auth.memberId);

    // Add clause amount to seller's budget
    if (sellerId) {
      const { data: sellerMember } = await supabase
        .from("members")
        .select("budget")
        .eq("id", sellerId)
        .single();
      await supabase
        .from("members")
        .update({ budget: ((sellerMember as any)?.budget ?? 0) + clauseAmount })
        .eq("id", sellerId);
    }

    // Record transfer
    await supabase.from("market_transfers").insert({
      session_id: (session as any).id,
      turn_id: turnId,
      buyer_id: auth.memberId,
      seller_id: sellerId,
      seller_team_id: sellerTeamId,
      player_id: body.playerId,
      transfer_type: "clause",
      amount: clauseAmount,
    });

  }

  // ── Complete turn + advance ───────────────────────────────────────────────
  await supabase
    .from("market_turns")
    .update({
      status: body.type === "skip" ? "skipped" : "completed",
      completed_at: new Date().toISOString(),
    })
    .eq("id", turnId);

  return NextResponse.json(await advanceTurn(supabase, session));
}

// ─── Shared: advance to next pending turn ─────────────────────────────────────
// Auto-skips members who already reached the 3-purchase limit.
export async function advanceTurn(supabase: any, session: any) {
  // eslint-disable-next-line no-constant-condition
  while (true) {
    const { data: nextTurn } = await supabase
      .from("market_turns")
      .select("id, member_id")
      .eq("session_id", session.id)
      .eq("round_num", session.current_round)
      .eq("status", "pending")
      .order("position")
      .limit(1)
      .maybeSingle();

    if (!nextTurn) break;

    const { data: member } = await supabase
      .from("members")
      .select("market_purchases")
      .eq("id", (nextTurn as any).member_id)
      .single();

    if ((member as any)?.market_purchases >= 3) {
      await supabase.from("market_turns").update({
        status: "skipped",
        completed_at: new Date().toISOString(),
      }).eq("id", (nextTurn as any).id);
      continue;
    }

    await supabase.from("market_turns").update({ status: "active" }).eq("id", (nextTurn as any).id);
    return { ok: true, roundDone: false };
  }

  // Round complete
  const newRound = session.current_round + 1;
  if (newRound > session.total_rounds) {
    await supabase
      .from("market_sessions")
      .update({ status: "finished", finished_at: new Date().toISOString() })
      .eq("id", session.id);
    return { ok: true, roundDone: true, marketFinished: true };
  }

  return { ok: true, roundDone: true, nextRound: newRound };
}
