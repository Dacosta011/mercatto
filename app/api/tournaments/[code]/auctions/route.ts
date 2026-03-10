import { NextRequest, NextResponse } from "next/server";
import {
  createServerClient,
  verifyMemberToken,
  verifyAdminToken,
} from "@/lib/supabase";
import { createBulkNotifications } from "@/lib/notifications";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/auctions ─────────────────────────────────────
// Returns all auctions for the current market session.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  // Accept both member and admin tokens
  let authMemberId: string | null = null;
  let authTournamentId: string;
  const memberAuth = await verifyMemberToken(request, code);
  if (memberAuth.ok) {
    authMemberId = memberAuth.memberId;
    authTournamentId = memberAuth.tournamentId;
  } else {
    const adminAuth = await verifyAdminToken(request, code);
    if (!adminAuth.ok) {
      return NextResponse.json({ error: "Token inválido." }, { status: 403 });
    }
    authTournamentId = adminAuth.tournamentId;
  }

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status")
    .eq("tournament_id", authTournamentId)
    .maybeSingle();

  if (!session) {
    return NextResponse.json({ auctions: [] });
  }

  const sessionId = (session as any).id;

  // ── Lazy voting resolution ──────────────────────────────────────────────
  // If voting phase expired, auto-resolve the most-voted icon and start bidding.
  const { data: expiredVoting } = await supabase
    .from("icon_auctions")
    .select("id, candidate_ids, min_bid, session_id")
    .eq("session_id", sessionId)
    .eq("phase", "voting")
    .lt("vote_ends_at", new Date().toISOString());

  for (const ev of expiredVoting ?? []) {
    const evx = ev as any;
    const { data: votes } = await supabase
      .from("icon_votes")
      .select("icon_id")
      .eq("auction_id", evx.id);

    const voteCounts: Record<string, number> = {};
    for (const v of votes ?? []) {
      const iid = (v as any).icon_id;
      voteCounts[iid] = (voteCounts[iid] ?? 0) + 1;
    }

    let winningIconId: string | null = null;
    let maxVotes = 0;
    for (const [iconId, count] of Object.entries(voteCounts)) {
      if (count > maxVotes) {
        maxVotes = count;
        winningIconId = iconId;
      }
    }

    // If no votes, pick the first candidate
    if (!winningIconId && (evx.candidate_ids ?? []).length > 0) {
      winningIconId = evx.candidate_ids[0];
    }

    if (winningIconId) {
      const now = new Date();
      const biddingEndsAt = new Date(now.getTime() + 120 * 60 * 1000).toISOString();
      await supabase
        .from("icon_auctions")
        .update({
          phase: "active",
          selected_icon_id: winningIconId,
          starts_at: now.toISOString(),
          ends_at: biddingEndsAt,
        })
        .eq("id", evx.id);

      const { data: iconData } = await supabase
        .from("players")
        .select("name")
        .eq("id", winningIconId)
        .single();

      const { data: notifMembers } = await supabase
        .from("members")
        .select("id")
        .eq("tournament_id", authTournamentId);

      await createBulkNotifications(
        supabase,
        authTournamentId,
        (notifMembers ?? []).map((m: any) => m.id),
        "auction_started",
        "¡Subasta iniciada!",
        `${(iconData as any)?.name ?? "Un ícono"} fue elegido por votación. ¡Puja ahora!`,
        { auctionId: evx.id, iconId: winningIconId }
      );
    } else {
      await supabase
        .from("icon_auctions")
        .update({ phase: "finished" })
        .eq("id", evx.id);
    }
  }

  // ── Lazy auction resolution ─────────────────────────────────────────────
  // Resolve expired auctions on read so we don't need a frequent cron.
  const { data: expiredAuctions } = await supabase
    .from("icon_auctions")
    .select("id, selected_icon_id, highest_bid, highest_bidder_id, session_id")
    .eq("session_id", sessionId)
    .eq("phase", "active")
    .lt("ends_at", new Date().toISOString());

  for (const ea of expiredAuctions ?? []) {
    const ax = ea as any;
    if (ax.highest_bidder_id && ax.highest_bid > 0) {
      await supabase
        .from("icon_auctions")
        .update({
          phase: "finished",
          winner_id: ax.highest_bidder_id,
          final_amount: ax.highest_bid,
        })
        .eq("id", ax.id);

      // Deduct from real budget and clear reservation
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
    } else {
      await supabase
        .from("icon_auctions")
        .update({ phase: "finished" })
        .eq("id", ax.id);
    }
  }

  const { data: auctionsRaw } = await supabase
    .from("icon_auctions")
    .select(
      "id, phase, starts_at, ends_at, min_bid, selected_icon_id, highest_bid, highest_bidder_id, winner_id, final_amount, created_at, vote_ends_at, candidate_ids"
    )
    .eq("session_id", sessionId)
    .order("created_at", { ascending: false });

  if (!auctionsRaw || auctionsRaw.length === 0) {
    return NextResponse.json({ auctions: [] });
  }

  // Gather icon IDs (including candidates) and member IDs for lookups
  const iconIds = [
    ...new Set(
      (auctionsRaw as any[])
        .flatMap((a) => [a.selected_icon_id, ...(a.candidate_ids ?? [])])
        .filter(Boolean)
    ),
  ];
  const memberIds = [
    ...new Set(
      (auctionsRaw as any[])
        .flatMap((a) => [a.highest_bidder_id, a.winner_id])
        .filter(Boolean)
    ),
  ];

  const { data: iconsRaw } = iconIds.length > 0
    ? await supabase
        .from("players")
        .select("id, name, ovr, position, country_name, headshot_url")
        .in("id", iconIds)
    : { data: [] };

  const iconById: Record<string, any> = {};
  for (const p of iconsRaw ?? []) iconById[(p as any).id] = p;

  const { data: membersRaw } = memberIds.length > 0
    ? await supabase
        .from("members")
        .select("id, display_name")
        .in("id", memberIds)
    : { data: [] };

  const memberNameById: Record<string, string> = {};
  for (const m of membersRaw ?? [])
    memberNameById[(m as any).id] = (m as any).display_name;

  // My budget & icon slot (only if authenticated as member)
  let myMember: any = null;
  if (authMemberId) {
    const { data: mm } = await supabase
      .from("members")
      .select("budget, budget_reserved, icon_slot_used")
      .eq("id", authMemberId)
      .single();
    myMember = mm;
  }

  // Fetch votes for voting-phase auctions
  const votingAuctionIds = (auctionsRaw as any[])
    .filter((a) => a.phase === "voting")
    .map((a) => a.id);

  let votesByAuction: Record<string, { iconId: string; memberId: string }[]> = {};
  if (votingAuctionIds.length > 0) {
    const { data: votesRaw } = await supabase
      .from("icon_votes")
      .select("auction_id, icon_id, member_id")
      .in("auction_id", votingAuctionIds);

    for (const v of votesRaw ?? []) {
      const vx = v as any;
      if (!votesByAuction[vx.auction_id]) votesByAuction[vx.auction_id] = [];
      votesByAuction[vx.auction_id].push({
        iconId: vx.icon_id,
        memberId: vx.member_id,
      });
    }
  }

  // Total members for majority calculation
  const { data: allTournamentMembers } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", authTournamentId);
  const totalMembers = (allTournamentMembers ?? []).length;

  const auctions = (auctionsRaw as any[]).map((a) => {
    const icon = a.selected_icon_id ? iconById[a.selected_icon_id] : null;
    const now = Date.now();
    const endsAt = a.ends_at ? new Date(a.ends_at).getTime() : null;
    const startsAt = a.starts_at ? new Date(a.starts_at).getTime() : null;
    const voteEndsAt = a.vote_ends_at ? new Date(a.vote_ends_at).getTime() : null;

    let computedPhase = a.phase;
    if (a.phase === "active" && endsAt && endsAt < now) {
      computedPhase = "finished";
    }
    if (a.phase === "pending" && startsAt && startsAt <= now) {
      computedPhase = "active";
    }

    // Build candidates list for voting phase
    const candidates = (a.candidate_ids ?? []).map((cid: string) => {
      const ic = iconById[cid];
      return ic
        ? {
            id: ic.id,
            name: ic.name,
            ovr: ic.ovr,
            position: ic.position,
            nation: ic.country_name ?? "—",
            headshotUrl: ic.headshot_url ?? null,
          }
        : null;
    }).filter(Boolean);

    // Vote counts per icon
    const auctionVotes = votesByAuction[a.id] ?? [];
    const voteCounts: Record<string, number> = {};
    let myVoteIconId: string | null = null;
    for (const v of auctionVotes) {
      voteCounts[v.iconId] = (voteCounts[v.iconId] ?? 0) + 1;
      if (v.memberId === authMemberId) myVoteIconId = v.iconId;
    }

    return {
      id: a.id,
      phase: computedPhase,
      startsAt: a.starts_at,
      endsAt: a.ends_at,
      voteEndsAt: a.vote_ends_at,
      minBid: a.min_bid,
      highestBid: a.highest_bid ?? 0,
      highestBidderId: a.highest_bidder_id,
      highestBidderName: a.highest_bidder_id
        ? (memberNameById[a.highest_bidder_id] ?? "—")
        : null,
      winnerId: a.winner_id,
      winnerName: a.winner_id
        ? (memberNameById[a.winner_id] ?? "—")
        : null,
      finalAmount: a.final_amount,
      icon: icon
        ? {
            id: icon.id,
            name: icon.name,
            ovr: icon.ovr,
            position: icon.position,
            nation: icon.country_name ?? "—",
            headshotUrl: icon.headshot_url ?? null,
          }
        : null,
      candidates,
      voteCounts,
      myVoteIconId,
      totalMembers,
      totalVotes: auctionVotes.length,
      isMyBid: authMemberId ? a.highest_bidder_id === authMemberId : false,
      timeRemainingMs: endsAt ? Math.max(0, endsAt - now) : null,
      voteTimeRemainingMs: voteEndsAt ? Math.max(0, voteEndsAt - now) : null,
    };
  });

  return NextResponse.json({
    auctions,
    myBudget: myMember?.budget ?? 0,
    myBudgetReserved: myMember?.budget_reserved ?? 0,
    myIconSlotUsed: myMember?.icon_slot_used ?? false,
  });
}

// ─── POST /api/tournaments/[code]/auctions ────────────────────────────────────
// Admin starts a new auction. This creates a VOTING phase where 6 random icons
// are presented to all members. After majority vote or 2h timeout, bidding starts.
// Body (optional): { votingMinutes?, biddingMinutes?, minBid? }

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { votingMinutes?: number; biddingMinutes?: number; minBid?: number } = {};
  try {
    body = await request.json();
  } catch {
    /* no body is fine */
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

  const sessionId = (session as any).id;

  // Check no active/voting auction
  const { data: activeAuction } = await supabase
    .from("icon_auctions")
    .select("id")
    .eq("session_id", sessionId)
    .in("phase", ["active", "pending", "voting"])
    .limit(1);

  if ((activeAuction ?? []).length > 0) {
    return NextResponse.json(
      { error: "Ya hay una subasta activa o en votación." },
      { status: 409 }
    );
  }

  // Get icons already won in this session
  const { data: wonIcons } = await supabase
    .from("icon_auctions")
    .select("selected_icon_id")
    .eq("session_id", sessionId)
    .not("winner_id", "is", null);

  const wonIds = new Set((wonIcons ?? []).map((w: any) => w.selected_icon_id).filter(Boolean));

  // Pick 6 random icons not already won
  const { data: allIcons } = await supabase
    .from("players")
    .select("id")
    .eq("is_icon", true);

  const available = (allIcons ?? [])
    .map((p: any) => p.id)
    .filter((id: string) => !wonIds.has(id));

  if (available.length === 0) {
    return NextResponse.json(
      { error: "No quedan íconos disponibles para subastar." },
      { status: 422 }
    );
  }

  // Shuffle and pick up to 6
  const shuffled = available.sort(() => Math.random() - 0.5);
  const candidateIds = shuffled.slice(0, Math.min(6, shuffled.length));

  const votingMinutes = body.votingMinutes ?? 120;
  const now = new Date();
  const voteEndsAt = new Date(now.getTime() + votingMinutes * 60 * 1000).toISOString();

  // Get next round_num
  const { data: lastAuction } = await supabase
    .from("icon_auctions")
    .select("round_num")
    .eq("session_id", sessionId)
    .order("round_num", { ascending: false })
    .limit(1)
    .maybeSingle();

  const roundNum = ((lastAuction as any)?.round_num ?? 0) + 1;

  const { data: auction, error: auctionErr } = await supabase
    .from("icon_auctions")
    .insert({
      session_id: sessionId,
      round_num: roundNum,
      phase: "voting",
      selected_icon_id: null,
      starts_at: null,
      ends_at: null,
      min_bid: body.minBid ?? 50_000_000,
      highest_bid: 0,
      presented_icon_ids: candidateIds,
      candidate_ids: candidateIds,
      vote_ends_at: voteEndsAt,
    })
    .select("id")
    .single();

  if (auctionErr) {
    return NextResponse.json(
      { error: "Error al crear la subasta." },
      { status: 500 }
    );
  }

  // Notify all members
  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  await createBulkNotifications(
    supabase,
    auth.tournamentId,
    (members ?? []).map((m: any) => m.id),
    "auction_started",
    "Votación de subasta iniciada",
    `Elige el ícono a subastar. Tienes ${votingMinutes >= 60 ? `${Math.floor(votingMinutes / 60)}h` : `${votingMinutes}min`} para votar.`,
    { auctionId: (auction as any).id }
  );

  return NextResponse.json(
    { ok: true, auctionId: (auction as any).id, voteEndsAt, candidateIds },
    { status: 201 }
  );
}
