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
    .select("id, status, started_at, closes_at")
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

  // Tournament settings
  const { data: tSettings } = await supabase
    .from("tournaments")
    .select("max_transfers, clause_protection")
    .eq("id", auth.tournamentId)
    .single();

  const maxTransfers = (tSettings as any)?.max_transfers ?? 3;
  const clauseProtectionEnabled = (tSettings as any)?.clause_protection ?? true;

  // Check purchase limit
  const { data: myMember } = await supabase
    .from("members")
    .select("budget, market_purchases")
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
    .select("id, name, clause")
    .eq("id", body.playerId)
    .single();

  if (!player) {
    return NextResponse.json(
      { error: "Jugador no encontrado." },
      { status: 404 }
    );
  }

  const clauseAmount = (player as any).clause ?? 0;

  if ((myMember as any)?.budget < clauseAmount) {
    return NextResponse.json(
      { error: "Presupuesto insuficiente." },
      { status: 422 }
    );
  }

  // Find original team
  const { data: tp } = await supabase
    .from("team_players")
    .select("team_id")
    .eq("player_id", body.playerId)
    .single();

  if (!tp) {
    return NextResponse.json(
      { error: "El jugador no está en ningún equipo." },
      { status: 422 }
    );
  }

  // Effective seller
  const { data: lastTransfer } = await supabase
    .from("market_transfers")
    .select("buyer_id")
    .eq("session_id", s.id)
    .eq("player_id", body.playerId)
    .in("transfer_type", ["clause", "offer", "icon_auction"])
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

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
    sellerTeamId = teamByMember[sellerId] ?? (tp as any).team_id;
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

  // Clause protection check (only if enabled)
  if (clauseProtectionEnabled) {
    const { data: prot } = await supabase
      .from("market_transfers")
      .select("id")
      .eq("session_id", s.id)
      .eq("seller_team_id", sellerTeamId)
      .eq("transfer_type", "clause")
      .gte("created_at", s.started_at)
      .limit(1);

    if ((prot ?? []).length > 0) {
      return NextResponse.json(
        { error: "Ese equipo ya está protegido contra cláusulas." },
        { status: 422 }
      );
    }
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

  return NextResponse.json({ ok: true, amount: clauseAmount });
}
