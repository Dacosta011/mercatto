import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/market ───────────────────────────────────────
// Returns full async market state for the requesting member.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // ── 0. Tournament settings ───────────────────────────────────────────────
  const { data: tournamentSettings } = await supabase
    .from("tournaments")
    .select("max_transfers, clause_protection_limit")
    .eq("id", auth.tournamentId)
    .single();

  const tournamentMaxTransfers = (tournamentSettings as any)?.max_transfers ?? 3;
  const tournamentClauseProtection: number = (tournamentSettings as any)?.clause_protection_limit ?? 1;

  // ── 1. Market session ─────────────────────────────────────────────────────
  const { data: session } = await supabase
    .from("market_sessions")
    .select("*")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session) {
    return NextResponse.json({ status: "pending", session: null });
  }

  const s = session as any;
  const isWinterSession = s.market_type === "winter";
  const maxTransfers = isWinterSession && s.winter_max_transfers != null
    ? s.winter_max_transfers
    : tournamentMaxTransfers;
  const clauseProtection: number = isWinterSession && s.winter_clause_protection != null
    ? s.winter_clause_protection
    : tournamentClauseProtection;

  // ── Lazy expiration (replaces frequent cron) ────────────────────────────
  // Expire overdue offers on read so we don't need a cron every 2 minutes.
  const now = new Date().toISOString();

  if (s.status === "active") {
    await supabase
      .from("market_offers")
      .update({ status: "expired", responded_at: now })
      .eq("session_id", s.id)
      .eq("status", "pending")
      .lt("expires_at", now);

    // Auto-close market if time is up
    if (s.closes_at && new Date(s.closes_at).getTime() < Date.now()) {
      await supabase
        .from("market_sessions")
        .update({ status: "finished", finished_at: now })
        .eq("id", s.id);
      await supabase
        .from("market_offers")
        .update({ status: "expired", responded_at: now })
        .eq("session_id", s.id)
        .eq("status", "pending");
      const { data: activeAuctions } = await supabase
        .from("icon_auctions")
        .select("id, selected_icon_id, highest_bid, highest_bidder_id, session_id")
        .eq("session_id", s.id)
        .in("phase", ["active", "voting"]);

      for (const ea of activeAuctions ?? []) {
        const ax = ea as any;
        if (ax.highest_bidder_id && ax.highest_bid > 0) {
          await supabase
            .from("icon_auctions")
            .update({ phase: "finished", winner_id: ax.highest_bidder_id, final_amount: ax.highest_bid })
            .eq("id", ax.id);

          const { data: winner } = await supabase
            .from("members")
            .select("budget, budget_reserved")
            .eq("id", ax.highest_bidder_id)
            .single();
          const wn = winner as any;
          await supabase
            .from("members")
            .update({
              budget: Math.max(0, (wn?.budget ?? 0) - ax.highest_bid),
              budget_reserved: Math.max(0, (wn?.budget_reserved ?? 0) - ax.highest_bid),
              icon_slot_used: true,
            })
            .eq("id", ax.highest_bidder_id);

          await supabase.from("market_transfers").insert({
            session_id: ax.session_id,
            player_id: ax.selected_icon_id,
            buyer_id: ax.highest_bidder_id,
            seller_id: null,
            amount: ax.highest_bid,
            transfer_type: "icon_auction",
          });

          // Set icon clause to auction price + 30% markup
          const newClause = Math.round(ax.highest_bid * 1.3);
          await supabase
            .from("players")
            .update({ clause: newClause })
            .eq("id", ax.selected_icon_id);
        } else {
          await supabase
            .from("icon_auctions")
            .update({ phase: "finished" })
            .eq("id", ax.id);
        }
      }
      s.status = "finished";
    }
  }

  // ── 2. All members + assignments + teams ──────────────────────────────────
  const { data: allMembersRaw } = await supabase
    .from("members")
    .select("id, display_name, budget, budget_reserved, market_purchases, icon_slot_used")
    .eq("tournament_id", auth.tournamentId);

  const allMemberIds = (allMembersRaw ?? []).map((m: any) => m.id);

  const { data: allAssignments } = allMemberIds.length > 0
    ? await supabase
        .from("assignments")
        .select("member_id, team_id")
        .in("member_id", allMemberIds)
    : { data: [] };

  const allTeamIds = (allAssignments ?? []).map((a: any) => a.team_id);

  const { data: allTeamsRaw } = allTeamIds.length > 0
    ? await supabase
        .from("teams")
        .select("id, name, crest_url")
        .in("id", allTeamIds)
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
    memberIdByTeam[(a as any).team_id] = (a as any).member_id;
  }

  const memberById: Record<string, any> = {};
  for (const m of allMembersRaw ?? []) memberById[(m as any).id] = m;

  const myTeamId = teamIdByMember[auth.memberId] ?? null;
  const myMember = memberById[auth.memberId];

  // ── 3. Effective ownership ────────────────────────────────────────────────
  const { data: allTeamPlayers } = allTeamIds.length > 0
    ? await supabase
        .from("team_players")
        .select("team_id, player_id")
        .in("team_id", allTeamIds)
    : { data: [] };

  const effectiveOwner: Record<string, string> = {};
  const effectiveTeam: Record<string, string> = {};
  for (const r of allTeamPlayers ?? []) {
    const mid = memberIdByTeam[(r as any).team_id];
    if (mid) {
      effectiveOwner[(r as any).player_id] = mid;
      effectiveTeam[(r as any).player_id] = (r as any).team_id;
    }
  }

  const { data: allTransfers } = await supabase
    .from("market_transfers")
    .select("buyer_id, player_id, transfer_type, amount")
    .eq("session_id", s.id)
    .in("transfer_type", ["clause", "offer", "icon_auction"])
    .order("created_at", { ascending: true });

  // Track the last transfer amount for each player (used for icon clause computation)
  const lastTransferAmount: Record<string, number> = {};

  for (const t of allTransfers ?? []) {
    effectiveOwner[t.player_id] = t.buyer_id;
    const buyerTeam = teamIdByMember[t.buyer_id];
    if (buyerTeam) effectiveTeam[t.player_id] = buyerTeam;
    if (t.amount) lastTransferAmount[t.player_id] = t.amount;
  }

  // ── 4. Clause protection + sold players (current market iteration) ────────
  const sessionStartedAt = s.started_at;

  const { data: currentIterationTransfers } = await supabase
    .from("market_transfers")
    .select("id, player_id, seller_team_id, transfer_type")
    .eq("session_id", s.id)
    .in("transfer_type", ["clause", "offer", "icon_auction"])
    .gte("created_at", sessionStartedAt);

  const soldPlayerIds = new Set(
    (currentIterationTransfers ?? []).map((t: any) => t.player_id)
  );

  const clauseCountByTeam: Record<string, number> = {};
  for (const t of (currentIterationTransfers ?? []).filter((t: any) => t.transfer_type === "clause")) {
    const tid = (t as any).seller_team_id;
    clauseCountByTeam[tid] = (clauseCountByTeam[tid] ?? 0) + 1;
  }

  // ── 5. Available players ──────────────────────────────────────────────────
  const otherPlayerIds = Object.keys(effectiveOwner).filter(
    (pid) => effectiveOwner[pid] !== auth.memberId
  );

  let availablePlayers: any[] = [];
  if (otherPlayerIds.length > 0) {
    const { data: players } = await supabase
      .from("players")
      .select("id, name, ovr, position, price, clause, headshot_url, is_icon")
      .in("id", otherPlayerIds)
      .order("ovr", { ascending: false });

    // Collect icon IDs that need clause fixes
    const iconClauseFixes: { id: string; clause: number }[] = [];

    for (const p of players ?? []) {
      if (soldPlayerIds.has((p as any).id)) continue;

      const ownerId = effectiveOwner[(p as any).id];
      const ownerTeamId = effectiveTeam[(p as any).id];

      let playerClause = (p as any).clause ?? 0;
      let playerPrice = (p as any).price ?? 0;

      // For icons with missing clause, compute from last transfer amount
      if ((p as any).is_icon && playerClause === 0) {
        const transferAmount = lastTransferAmount[(p as any).id];
        if (transferAmount && transferAmount > 0) {
          playerClause = Math.round(transferAmount * 1.3);
          playerPrice = transferAmount;
          iconClauseFixes.push({ id: (p as any).id, clause: playerClause });
        }
      }

      availablePlayers.push({
        playerId: (p as any).id,
        playerName: (p as any).name,
        headshotUrl: (p as any).headshot_url ?? null,
        ovr: (p as any).ovr,
        position: (p as any).position ?? "—",
        price: playerPrice,
        clause: playerClause,
        isIcon: (p as any).is_icon ?? false,
        teamId: ownerTeamId,
        teamName: teamNameById[ownerTeamId] ?? "—",
        teamCrestUrl: teamCrestById[ownerTeamId] ?? null,
        ownerId,
        ownerName: memberById[ownerId]?.display_name ?? "—",
        clauseProtected: clauseProtection > 0 && (clauseCountByTeam[ownerTeamId] ?? 0) >= clauseProtection,
        inNegotiation: false,
      });
    }

    // Self-heal: persist corrected clause values so future reads are accurate
    for (const fix of iconClauseFixes) {
      await supabase.from("players").update({ clause: fix.clause }).eq("id", fix.id);
    }
  }

  // ── 6. Pending offers — mark players "in negotiation" ─────────────────────
  const { data: allPendingOffers } = await supabase
    .from("market_offers")
    .select(
      "id, buyer_id, seller_id, player_id, amount, expires_at, counter_amount, parent_offer_id, created_at"
    )
    .eq("session_id", s.id)
    .eq("status", "pending")
    .order("created_at", { ascending: false });

  const pendingPlayerIds = new Set(
    (allPendingOffers ?? []).map((o: any) => o.player_id)
  );

  for (const p of availablePlayers) {
    if (pendingPlayerIds.has(p.playerId)) {
      p.inNegotiation = true;
    }
  }

  // ── 7. My pending actions ─────────────────────────────────────────────────
  const myIncomingOffers: any[] = [];
  const myOutgoingOffers: any[] = [];

  const offerPlayerIds = [
    ...new Set((allPendingOffers ?? []).map((o: any) => o.player_id)),
  ];
  const { data: offerPlayersRaw } = offerPlayerIds.length > 0
    ? await supabase
        .from("players")
        .select("id, name, ovr, position, headshot_url, price, clause")
        .in("id", offerPlayerIds)
    : { data: [] };

  const offerPlayerById: Record<string, any> = {};
  for (const p of offerPlayersRaw ?? [])
    offerPlayerById[(p as any).id] = p;

  for (const o of allPendingOffers ?? []) {
    const player = offerPlayerById[o.player_id];
    const entry = {
      id: o.id,
      buyerId: o.buyer_id,
      buyerName: memberById[o.buyer_id]?.display_name ?? "—",
      sellerId: o.seller_id,
      sellerName: memberById[o.seller_id]?.display_name ?? "—",
      playerId: o.player_id,
      playerName: player?.name ?? "—",
      playerOvr: player?.ovr ?? null,
      playerPosition: player?.position ?? "—",
      playerHeadshot: player?.headshot_url ?? null,
      playerPrice: player?.price ?? 0,
      playerClause: player?.clause ?? 0,
      amount: o.amount,
      expiresAt: o.expires_at,
      counterAmount: o.counter_amount,
      parentOfferId: o.parent_offer_id,
      createdAt: o.created_at,
    };

    if (o.seller_id === auth.memberId) myIncomingOffers.push(entry);
    if (o.buyer_id === auth.memberId) myOutgoingOffers.push(entry);
  }

  // ── 8. Recent activity feed ───────────────────────────────────────────────
  const isFinished = s.status === "finished";
  const [
    { data: recentTransfersRaw },
    { data: rejectedOffersRaw },
  ] = await Promise.all([
    supabase
      .from("market_transfers")
      .select(
        "id, buyer_id, seller_id, seller_team_id, player_id, transfer_type, amount, created_at"
      )
      .eq("session_id", s.id)
      .order("created_at", { ascending: false })
      .limit(isFinished ? 200 : 40),
    supabase
      .from("market_offers")
      .select("id, buyer_id, seller_id, player_id, amount, responded_at")
      .eq("session_id", s.id)
      .eq("status", "rejected")
      .order("responded_at", { ascending: false })
      .limit(30),
  ]);

  const allActivityPlayerIds = [
    ...new Set([
      ...(recentTransfersRaw ?? []).map((t: any) => t.player_id),
      ...(rejectedOffersRaw ?? []).map((o: any) => o.player_id),
      ...(allPendingOffers ?? []).map((o: any) => o.player_id),
    ]),
  ];

  const { data: activityPlayers } = allActivityPlayerIds.length > 0
    ? await supabase
        .from("players")
        .select("id, name")
        .in("id", allActivityPlayerIds)
    : { data: [] };

  const playerNameById: Record<string, string> = {};
  for (const p of activityPlayers ?? [])
    playerNameById[(p as any).id] = (p as any).name;

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

  const pendingOfferEntries = (allPendingOffers ?? []).map((o: any) => {
    const sellerTeamId = teamIdByMember[o.seller_id];
    return {
      id: `pend-${o.id}`,
      transferType: "pending_offer" as string,
      amount: o.amount,
      createdAt: o.created_at,
      buyerId: o.buyer_id,
      sellerId: o.seller_id,
      buyerName: memberById[o.buyer_id]?.display_name ?? "—",
      sellerName: memberById[o.seller_id]?.display_name ?? "—",
      sellerTeamName: sellerTeamId
        ? (teamNameById[sellerTeamId] ?? "—")
        : "—",
      playerName: playerNameById[o.player_id] ?? "—",
    };
  });

  const recentTransfers = [
    ...completedTransfers,
    ...rejectedOffers,
    ...pendingOfferEntries,
  ]
    .sort(
      (a, b) =>
        new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    )
    .slice(0, 50);

  // ── 9. Unread notification count ──────────────────────────────────────────
  const { count: unreadNotifications } = await supabase
    .from("notifications")
    .select("id", { count: "exact", head: true })
    .eq("member_id", auth.memberId)
    .eq("tournament_id", auth.tournamentId)
    .eq("read", false);

  // ── 10. Market timer ──────────────────────────────────────────────────────
  const nowDate = new Date();
  const closesAt = s.closes_at ? new Date(s.closes_at) : null;
  const timeRemainingMs = closesAt
    ? Math.max(0, closesAt.getTime() - nowDate.getTime())
    : null;

  return NextResponse.json({
    status: s.status,
    session: {
      id: s.id,
      status: s.status,
      opensAt: s.opens_at,
      closesAt: s.closes_at,
      durationHours: s.duration_hours,
      startedAt: s.started_at,
      finishedAt: s.finished_at,
      marketType: s.market_type ?? "regular",
    },
    timer: {
      closesAt: s.closes_at,
      timeRemainingMs,
      isClosingSoon: timeRemainingMs !== null && timeRemainingMs < 2 * 60 * 60 * 1000,
      isUrgent: timeRemainingMs !== null && timeRemainingMs < 30 * 60 * 1000,
    },
    myStatus: {
      memberId: auth.memberId,
      budget: myMember?.budget ?? 0,
      budgetReserved: myMember?.budget_reserved ?? 0,
      purchasesUsed: myMember?.market_purchases ?? 0,
      maxPurchases: maxTransfers,
      iconSlotUsed: myMember?.icon_slot_used ?? false,
      myTeamId,
      myTeamName: myTeamId ? (teamNameById[myTeamId] ?? null) : null,
      myTeamCrestUrl: myTeamId ? (teamCrestById[myTeamId] ?? null) : null,
      pendingIncoming: myIncomingOffers.length,
      pendingOutgoing: myOutgoingOffers.length,
    },
    availablePlayers,
    myIncomingOffers,
    myOutgoingOffers,
    recentTransfers,
    clauseProtectionEnabled: clauseProtection,
    unreadNotifications: unreadNotifications ?? 0,
    allMembers: (allMembersRaw ?? []).map((m: any) => {
      const tid = teamIdByMember[m.id];
      return {
        id: m.id,
        displayName: m.display_name,
        teamName: tid ? (teamNameById[tid] ?? null) : null,
        teamCrestUrl: tid ? (teamCrestById[tid] ?? null) : null,
        purchasesUsed: m.market_purchases ?? 0,
        // Clauses already paid AGAINST this member's team during the current
        // market iteration. The cap is the same for everyone:
        // `clauseProtectionEnabled` (returned at the top level).
        clausesUsed: tid ? (clauseCountByTeam[tid] ?? 0) : 0,
      };
    }),
  });
}
