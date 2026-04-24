import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { createNotification } from "@/lib/notifications";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/market/clause ───────────────────────────────
// Async: any member can pay a clause at any time during the market window.
// Body: { playerId }

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { playerId?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (!body.playerId) {
    return NextResponse.json(
      { error: "Se requiere playerId." },
      { status: 400 }
    );
  }

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status, started_at, closes_at, market_type, winter_max_transfers, winter_clause_protection")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json(
      { error: "El mercado no está activo." },
      { status: 409 }
    );
  }

  const s = session as any;

  if (s.closes_at && new Date(s.closes_at) < new Date()) {
    return NextResponse.json(
      { error: "El mercado ha cerrado." },
      { status: 409 }
    );
  }

  // Tournament settings — winter sessions override with their own limits
  const { data: tSettings } = await supabase
    .from("tournaments")
    .select("max_transfers, clause_protection_limit")
    .eq("id", auth.tournamentId)
    .single();

  const isWinterSession = s.market_type === "winter";
  const maxTransfers = isWinterSession && s.winter_max_transfers != null
    ? s.winter_max_transfers
    : ((tSettings as any)?.max_transfers ?? 3);
  const clauseProtectionLimit: number = isWinterSession && s.winter_clause_protection != null
    ? s.winter_clause_protection
    : ((tSettings as any)?.clause_protection_limit ?? 1);

  // Check purchase limit
  const { data: myMember } = await supabase
    .from("members")
    .select("budget, budget_reserved, market_purchases")
    .eq("id", auth.memberId)
    .single();

  if ((myMember as any)?.market_purchases >= maxTransfers) {
    return NextResponse.json(
      { error: `Ya alcanzaste el límite de ${maxTransfers} fichajes.` },
      { status: 422 }
    );
  }

  // Get player
  const { data: player } = await supabase
    .from("players")
    .select("id, name, clause, is_icon")
    .eq("id", body.playerId)
    .single();

  if (!player) {
    return NextResponse.json(
      { error: "Jugador no encontrado." },
      { status: 404 }
    );
  }

  const clauseAmount = (player as any).clause ?? 0;

  const availableBudget = ((myMember as any)?.budget ?? 0) - ((myMember as any)?.budget_reserved ?? 0);
  if (availableBudget < clauseAmount) {
    return NextResponse.json(
      { error: "Presupuesto disponible insuficiente." },
      { status: 422 }
    );
  }

  // Find original team (base roster — icons won't be here)
  const { data: tp } = await supabase
    .from("team_players")
    .select("team_id")
    .eq("player_id", body.playerId)
    .maybeSingle();

  // Find effective seller from transfer history (auto_release wins as well)
  const { data: lastAnyTransfer } = await supabase
    .from("market_transfers")
    .select("buyer_id, transfer_type")
    .eq("session_id", s.id)
    .eq("player_id", body.playerId)
    .in("transfer_type", ["clause", "offer", "icon_auction", "auto_release"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (lastAnyTransfer && (lastAnyTransfer as any).transfer_type === "auto_release") {
    return NextResponse.json(
      { error: "Este jugador fue liberado por deuda y no está disponible en este mercado." },
      { status: 422 }
    );
  }

  const lastTransfer = lastAnyTransfer;

  if (!tp && !lastTransfer) {
    return NextResponse.json(
      { error: "El jugador no está en ningún equipo." },
      { status: 422 }
    );
  }

  const allMemberIds =
    (
      await supabase
        .from("members")
        .select("id")
        .eq("tournament_id", auth.tournamentId)
    ).data?.map((m: any) => m.id) ?? [];

  const { data: tournamentAssignments } = await supabase
    .from("assignments")
    .select("member_id, team_id")
    .in("member_id", allMemberIds);

  const teamByMember: Record<string, string> = {};
  const memberByTeam: Record<string, string> = {};
  for (const a of tournamentAssignments ?? []) {
    teamByMember[(a as any).member_id] = (a as any).team_id;
    memberByTeam[(a as any).team_id] = (a as any).member_id;
  }

  let sellerId: string;
  let sellerTeamId: string;

  if (lastTransfer) {
    sellerId = (lastTransfer as any).buyer_id;
    sellerTeamId = teamByMember[sellerId] ?? ((tp as any)?.team_id ?? "");
  } else {
    sellerTeamId = (tp as any).team_id;
    sellerId = memberByTeam[sellerTeamId] ?? "";
  }

  if (sellerId === auth.memberId) {
    return NextResponse.json(
      { error: "No puedes pagar la cláusula de tu propio jugador." },
      { status: 422 }
    );
  }

  if (clauseProtectionLimit > 0) {
    const { data: prot } = await supabase
      .from("market_transfers")
      .select("id")
      .eq("session_id", s.id)
      .eq("seller_team_id", sellerTeamId)
      .eq("transfer_type", "clause")
      .gte("created_at", s.started_at);

    if ((prot ?? []).length >= clauseProtectionLimit) {
      return NextResponse.json(
        { error: `Ese equipo ya alcanzó el límite de ${clauseProtectionLimit} cláusula${clauseProtectionLimit > 1 ? "s" : ""}.` },
        { status: 422 }
      );
    }
  }

  // ── Rejection check: if this buyer already attempted to clause this player
  //    in this market session and got rejected, they cannot try again.
  const { data: priorRejection } = await supabase
    .from("market_transfers")
    .select("id")
    .eq("session_id", s.id)
    .eq("buyer_id", auth.memberId)
    .eq("player_id", body.playerId)
    .eq("transfer_type", "clause_rejected")
    .limit(1);

  if ((priorRejection ?? []).length > 0) {
    return NextResponse.json(
      { error: "El jugador ya rechazó tu oferta en este mercado." },
      { status: 422 }
    );
  }

  // ── Player rejection roll: 25% chance the player turns the clause down.
  //    On rejection nothing moves (no money, no purchase counted) but we
  //    persist the event so the same buyer cannot retry the same player in
  //    this session.
  const REJECTION_CHANCE = 0.25;
  const rejected = Math.random() < REJECTION_CHANCE;

  if (rejected) {
    await supabase.from("market_transfers").insert({
      session_id: s.id,
      turn_id: null,
      buyer_id: auth.memberId,
      seller_id: sellerId,
      seller_team_id: sellerTeamId,
      player_id: body.playerId,
      transfer_type: "clause_rejected",
      amount: clauseAmount,
    });

    const buyerNameRow = await supabase
      .from("members")
      .select("display_name")
      .eq("id", auth.memberId)
      .single();
    const buyerName = (buyerNameRow.data as any)?.display_name ?? "—";

    // Notify the buyer in their own feed too — useful when the rejection
    // happens via push and they're not on the market screen.
    await createNotification({
      supabase,
      memberId: auth.memberId,
      tournamentId: auth.tournamentId,
      type: "clause_rejected",
      title: "Cláusula rechazada",
      body: `${(player as any).name} rechazó tu oferta de cláusula.`,
      metadata: { playerId: body.playerId, amount: clauseAmount },
    });

    if (sellerId) {
      await createNotification({
        supabase,
        memberId: sellerId,
        tournamentId: auth.tournamentId,
        type: "clause_rejected",
        title: "Cláusula rechazada",
        body: `${(player as any).name} rechazó la cláusula que pagó ${buyerName}.`,
        metadata: { playerId: body.playerId, buyerId: auth.memberId },
      });
    }

    return NextResponse.json({
      ok: true,
      rejected: true,
      amount: clauseAmount,
      playerName: (player as any).name,
    });
  }

  // Deduct buyer budget + increment purchases
  await supabase
    .from("members")
    .update({
      budget: (myMember as any).budget - clauseAmount,
      market_purchases: (myMember as any).market_purchases + 1,
    })
    .eq("id", auth.memberId);

  // Credit seller
  if (sellerId) {
    const { data: sellerMember } = await supabase
      .from("members")
      .select("budget")
      .eq("id", sellerId)
      .single();
    await supabase
      .from("members")
      .update({
        budget: ((sellerMember as any)?.budget ?? 0) + clauseAmount,
      })
      .eq("id", sellerId);
  }

  // Record transfer
  await supabase.from("market_transfers").insert({
    session_id: s.id,
    turn_id: null,
    buyer_id: auth.memberId,
    seller_id: sellerId,
    seller_team_id: sellerTeamId,
    player_id: body.playerId,
    transfer_type: "clause",
    amount: clauseAmount,
  });

  // Persist transfer amount as player price so salary-per-match reflects the
  // latest acquisition cost. Icons also refresh clause with +30% markup.
  if ((player as any).is_icon) {
    const newClause = Math.round(clauseAmount * 1.3);
    await supabase
      .from("players")
      .update({ price: clauseAmount, clause: newClause })
      .eq("id", body.playerId);
  } else {
    await supabase
      .from("players")
      .update({ price: clauseAmount })
      .eq("id", body.playerId);
  }

  // Cancel any pending offers for this player
  await supabase
    .from("market_offers")
    .update({ status: "cancelled", responded_at: new Date().toISOString() })
    .eq("session_id", s.id)
    .eq("player_id", body.playerId)
    .eq("status", "pending");

  const buyerName =
    (
      await supabase
        .from("members")
        .select("display_name")
        .eq("id", auth.memberId)
        .single()
    ).data?.display_name ?? "—";

  // Notify seller
  if (sellerId) {
    await createNotification({
      supabase,
      memberId: sellerId,
      tournamentId: auth.tournamentId,
      type: "clause_paid",
      title: "Cláusula pagada",
      body: `${buyerName} pagó la cláusula de ${(player as any).name} ($${(clauseAmount / 1_000_000).toFixed(0)}M)`,
      metadata: {
        playerId: body.playerId,
        buyerId: auth.memberId,
        amount: clauseAmount,
      },
    });
  }

  return NextResponse.json({ ok: true, rejected: false, amount: clauseAmount });
}
