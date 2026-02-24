import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/market ───────────────────────────────────────

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // ── 1. Market session ─────────────────────────────────────────────────────
  const { data: session } = await supabase
    .from("market_sessions")
    .select("*")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session) {
    return NextResponse.json({ status: "pending", session: null });
  }

  // ── 2. All members + assignments + teams (for names everywhere) ───────────
  const { data: allMembersRaw } = await supabase
    .from("members")
    .select("id, display_name, budget, market_purchases")
    .eq("tournament_id", auth.tournamentId);

  const allMemberIds = (allMembersRaw ?? []).map((m: any) => m.id);

  // All assignments in the tournament
  const { data: allAssignments } = allMemberIds.length > 0
    ? await supabase
        .from("assignments")
        .select("member_id, team_id")
        .in("member_id", allMemberIds)
    : { data: [] };

  // All team names
  const allTeamIds = (allAssignments ?? []).map((a: any) => a.team_id);
  const { data: allTeamsRaw } = allTeamIds.length > 0
    ? await supabase.from("teams").select("id, name, crest_url").in("id", allTeamIds)
    : { data: [] };

  const teamNameById: Record<string, string> = {};
  const teamCrestById: Record<string, string | null> = {};
  for (const t of allTeamsRaw ?? []) {
    teamNameById[(t as any).id] = (t as any).name;
    teamCrestById[(t as any).id] = (t as any).crest_url ?? null;
  }

  const teamIdByMember: Record<string, string> = {};
  const memberIdByTeam: Record<string, string> = {};
  for (const a of allAssignments ?? []) {
    teamIdByMember[(a as any).member_id] = (a as any).team_id;
    memberIdByTeam[(a as any).team_id]   = (a as any).member_id;
  }

  const memberById: Record<string, any> = {};
  for (const m of allMembersRaw ?? []) memberById[(m as any).id] = m;

  const myTeamId = teamIdByMember[auth.memberId] ?? null;

  // ── 3. Turns for current round (with team names) ──────────────────────────
  const { data: turns } = await supabase
    .from("market_turns")
    .select("id, round_num, position, member_id, status, completed_at")
    .eq("session_id", (session as any).id)
    .eq("round_num", (session as any).current_round)
    .order("position");

  const turnsWithNames = (turns ?? []).map((t: any) => {
    const teamId = teamIdByMember[t.member_id];
    return {
      id: t.id,
      memberId: t.member_id,
      memberName: memberById[t.member_id]?.display_name ?? "—",
      teamName: teamId ? (teamNameById[teamId] ?? "—") : null,
      teamCrestUrl: teamId ? (teamCrestById[teamId] ?? null) : null,
      position: t.position,
      status: t.status,
      completedAt: t.completed_at,
    };
  });

  const currentTurn = turnsWithNames.find((t) => t.status === "active") ?? null;
  const allRoundDone = turnsWithNames.every(
    (t) => t.status === "completed" || t.status === "skipped"
  );

  // ── 4. My status ──────────────────────────────────────────────────────────
  const myMember = memberById[auth.memberId];

  const [{ data: clauseOnMyTeam }, { data: myPendingOffer }] = await Promise.all([
    myTeamId
      ? supabase
          .from("market_transfers")
          .select("id")
          .eq("session_id", (session as any).id)
          .eq("seller_team_id", myTeamId)
          .eq("transfer_type", "clause")
          .limit(1)
      : Promise.resolve({ data: [] }),
    supabase
      .from("market_offers")
      .select("id, player_id, amount")
      .eq("session_id", (session as any).id)
      .eq("buyer_id", auth.memberId)
      .eq("status", "pending")
      .limit(1),
  ]);

  // ── 5. Clause-protected teams ─────────────────────────────────────────────
  const { data: protectedTransfers } = await supabase
    .from("market_transfers")
    .select("seller_team_id")
    .eq("session_id", (session as any).id)
    .eq("transfer_type", "clause");

  const protectedTeamIds = new Set(
    (protectedTransfers ?? []).map((t: any) => t.seller_team_id)
  );

  // ── 6. Available players (other teams, excluding already transferred) ────────
  const otherTeamIds = (allAssignments ?? [])
    .filter((a: any) => a.member_id !== auth.memberId)
    .map((a: any) => a.team_id);

  // Players already sold in this market session cannot be re-purchased
  const { data: soldTransfers } = await supabase
    .from("market_transfers")
    .select("player_id")
    .eq("session_id", (session as any).id)
    .in("transfer_type", ["clause", "offer", "icon_auction"]);

  const soldPlayerIds = new Set((soldTransfers ?? []).map((t: any) => t.player_id));

  let availablePlayers: any[] = [];
  if (otherTeamIds.length > 0) {
    const { data: tp } = await supabase
      .from("team_players")
      .select("team_id, player_id")
      .in("team_id", otherTeamIds);

    const teamByPlayer: Record<string, string> = {};
    for (const r of tp ?? []) teamByPlayer[(r as any).player_id] = (r as any).team_id;

    const playerIds = (tp ?? []).map((r: any) => r.player_id);
    if (playerIds.length > 0) {
      const { data: players } = await supabase
        .from("players")
        .select("id, name, ovr, position, price, clause, headshot_url")
        .in("id", playerIds)
        .order("ovr", { ascending: false });

      for (const p of players ?? []) {
        // Skip players already sold in this market session
        if (soldPlayerIds.has((p as any).id)) continue;

        const tid = teamByPlayer[(p as any).id];
        const ownerId = memberIdByTeam[tid];
        availablePlayers.push({
          playerId: (p as any).id,
          playerName: (p as any).name,
          headshotUrl: (p as any).headshot_url ?? null,
          ovr: (p as any).ovr,
          position: (p as any).position ?? "—",
          price: (p as any).price ?? 0,
          clause: (p as any).clause ?? 0,
          teamId: tid,
          teamName: teamNameById[tid] ?? "—",
          ownerId,
          ownerName: memberById[ownerId]?.display_name ?? "—",
          clauseProtected: protectedTeamIds.has(tid),
        });
      }
    }
  }

  // ── 7. Recent activity: completed transfers + rejected offers ─────────────
  const isFinished = (session as any).status === "finished";
  const [{ data: recentTransfersRaw }, { data: rejectedOffersRaw }] = await Promise.all([
    supabase
      .from("market_transfers")
      .select("id, buyer_id, seller_id, seller_team_id, player_id, transfer_type, amount, created_at")
      .eq("session_id", (session as any).id)
      .order("created_at", { ascending: false })
      .limit(isFinished ? 200 : 30),
    supabase
      .from("market_offers")
      .select("id, buyer_id, seller_id, player_id, amount, responded_at")
      .eq("session_id", (session as any).id)
      .eq("status", "rejected")
      .order("responded_at", { ascending: false })
      .limit(30),
  ]);

  // Collect all player ids from both sources for a single lookup
  const allActivityPlayerIds = [
    ...new Set([
      ...(recentTransfersRaw ?? []).map((t: any) => t.player_id),
      ...(rejectedOffersRaw  ?? []).map((o: any) => o.player_id),
    ]),
  ];
  const { data: activityPlayers } = allActivityPlayerIds.length > 0
    ? await supabase.from("players").select("id, name").in("id", allActivityPlayerIds)
    : { data: [] };
  const playerNameById: Record<string, string> = {};
  for (const p of activityPlayers ?? []) playerNameById[(p as any).id] = (p as any).name;

  const completedTransfers = (recentTransfersRaw ?? []).map((t: any) => ({
    id: t.id,
    transferType: t.transfer_type as string,
    amount: t.amount,
    createdAt: t.created_at,
    buyerId: t.buyer_id,
    sellerId: t.seller_id,
    buyerName: memberById[t.buyer_id]?.display_name ?? "—",
    sellerName: memberById[t.seller_id]?.display_name ?? "—",
    sellerTeamName: teamNameById[t.seller_team_id] ?? "—",
    playerName: playerNameById[t.player_id] ?? "—",
  }));

  const rejectedOffers = (rejectedOffersRaw ?? []).map((o: any) => ({
    id: `rej-${o.id}`,
    transferType: "rejected" as string,
    amount: o.amount,
    createdAt: o.responded_at ?? o.id,
    buyerName: memberById[o.buyer_id]?.display_name ?? "—",
    sellerName: memberById[o.seller_id]?.display_name ?? "—",
    sellerTeamName: "—",
    playerName: playerNameById[o.player_id] ?? "—",
  }));

  // Merge and sort by date descending, cap at 40 entries
  const recentTransfers = [...completedTransfers, ...rejectedOffers]
    .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime())
    .slice(0, 40);

  // ── 8. Incoming offers (enriched with player name) ────────────────────────
  const { data: incomingOffersRaw } = await supabase
    .from("market_offers")
    .select("id, buyer_id, player_id, amount, created_at")
    .eq("session_id", (session as any).id)
    .eq("seller_id", auth.memberId)
    .eq("status", "pending");

  const offerPlayerIds = [...new Set((incomingOffersRaw ?? []).map((o: any) => o.player_id))];
  const { data: offerPlayersRaw } = offerPlayerIds.length > 0
    ? await supabase.from("players").select("id, name, ovr, position, headshot_url").in("id", offerPlayerIds)
    : { data: [] };
  const offerPlayerById: Record<string, any> = {};
  for (const p of offerPlayersRaw ?? []) offerPlayerById[(p as any).id] = p;

  const incomingOffers = (incomingOffersRaw ?? []).map((o: any) => {
    const player = offerPlayerById[o.player_id];
    return {
      id: o.id,
      buyerId: o.buyer_id,
      buyerName: memberById[o.buyer_id]?.display_name ?? "—",
      playerId: o.player_id,
      playerName: player?.name ?? o.player_id,
      playerOvr: player?.ovr ?? null,
      playerPosition: player?.position ?? "—",
      playerHeadshot: player?.headshot_url ?? null,
      amount: o.amount,
      createdAt: o.created_at,
    };
  });

  return NextResponse.json({
    status: (session as any).status,
    session: {
      id: (session as any).id,
      status: (session as any).status,
      currentRound: (session as any).current_round,
      totalRounds: (session as any).total_rounds,
      allRoundDone,
    },
    currentTurn,
    isMyTurn: currentTurn?.memberId === auth.memberId,
    turns: turnsWithNames,
    myStatus: {
      memberId: auth.memberId,
      budget: myMember?.budget ?? 0,
      purchasesUsed: myMember?.market_purchases ?? 0,
      maxPurchases: 3,
      myTeamId,
      myTeamName: myTeamId ? (teamNameById[myTeamId] ?? null) : null,
      teamClauseProtected: ((clauseOnMyTeam as any) ?? []).length > 0,
      hasPendingOffer: ((myPendingOffer as any) ?? []).length > 0,
    },
    availablePlayers,
    recentTransfers,
    incomingOffers,
    allMembers: (allMembersRaw ?? []).map((m: any) => {
      const tid = teamIdByMember[m.id];
      return {
        id: m.id,
        displayName: m.display_name,
        teamName: tid ? (teamNameById[tid] ?? null) : null,
        teamCrestUrl: tid ? (teamCrestById[tid] ?? null) : null,
        budget: m.budget,
        purchasesUsed: m.market_purchases ?? 0,
      };
    }),
  });
}
