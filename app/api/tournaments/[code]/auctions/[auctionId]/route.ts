import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken, verifyAdminToken } from "@/lib/supabase";
import { createNotification } from "@/lib/notifications";

type Params = { params: Promise<{ code: string; auctionId: string }> };

// ─── GET /api/tournaments/[code]/auctions/[auctionId] ─────────────────────────
// Returns full auction detail including bid history.

export async function GET(request: NextRequest, { params }: Params) {
  const { code, auctionId } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: auction } = await supabase
    .from("icon_auctions")
    .select("*")
    .eq("id", auctionId)
    .maybeSingle();

  if (!auction) {
    return NextResponse.json(
      { error: "Subasta no encontrada." },
      { status: 404 }
    );
  }

  const a = auction as any;

  // Get icon details
  let icon = null;
  if (a.selected_icon_id) {
    const { data: iconData } = await supabase
      .from("players")
      .select("id, name, ovr, position, country_name, headshot_url")
      .eq("id", a.selected_icon_id)
      .single();
    if (iconData) {
      icon = {
        id: (iconData as any).id,
        name: (iconData as any).name,
        ovr: (iconData as any).ovr,
        position: (iconData as any).position,
        nation: (iconData as any).country_name ?? "—",
        headshotUrl: (iconData as any).headshot_url ?? null,
      };
    }
  }

  // Get bid history
  const { data: bidsRaw } = await supabase
    .from("icon_bids")
    .select("id, member_id, amount, created_at")
    .eq("auction_id", auctionId)
    .eq("passed", false)
    .order("created_at", { ascending: false });

  const bidMemberIds = [
    ...new Set((bidsRaw ?? []).map((b: any) => b.member_id)),
  ];
  const { data: bidMembers } = bidMemberIds.length > 0
    ? await supabase
        .from("members")
        .select("id, display_name")
        .in("id", bidMemberIds)
    : { data: [] };

  const memberNameById: Record<string, string> = {};
  for (const m of bidMembers ?? [])
    memberNameById[(m as any).id] = (m as any).display_name;

  const bids = (bidsRaw ?? []).map((b: any) => ({
    id: b.id,
    memberId: b.member_id,
    memberName: memberNameById[b.member_id] ?? "—",
    amount: b.amount,
    createdAt: b.created_at,
    isMe: b.member_id === auth.memberId,
  }));

  // My budget & icon slot
  const { data: myMember } = await supabase
    .from("members")
    .select("budget, icon_slot_used")
    .eq("id", auth.memberId)
    .single();

  const now = Date.now();
  const endsAt = a.ends_at ? new Date(a.ends_at).getTime() : null;

  return NextResponse.json({
    auction: {
      id: a.id,
      phase: a.phase,
      startsAt: a.starts_at,
      endsAt: a.ends_at,
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
      icon,
      isMyBid: a.highest_bidder_id === auth.memberId,
      timeRemainingMs: endsAt ? Math.max(0, endsAt - now) : null,
    },
    bids,
    myBudget: (myMember as any)?.budget ?? 0,
    myIconSlotUsed: (myMember as any)?.icon_slot_used ?? false,
  });
}

// ─── PATCH /api/tournaments/[code]/auctions/[auctionId] ───────────────────────
// Admin force-ends an active auction. Resolves winner if there are bids.

export async function PATCH(request: NextRequest, { params }: Params) {
  const { code, auctionId } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: auction } = await supabase
    .from("icon_auctions")
    .select("*")
    .eq("id", auctionId)
    .maybeSingle();

  if (!auction) {
    return NextResponse.json({ error: "Subasta no encontrada." }, { status: 404 });
  }

  const a = auction as any;

  if (a.phase === "finished") {
    return NextResponse.json({ error: "La subasta ya terminó." }, { status: 409 });
  }

  // If voting phase: resolve the vote and start bidding
  if (a.phase === "voting") {
    const candidateIds: string[] = a.candidate_ids ?? [];

    // Count votes per icon
    const { data: votes } = await supabase
      .from("icon_votes")
      .select("icon_id")
      .eq("auction_id", auctionId);

    const voteCounts: Record<string, number> = {};
    for (const v of votes ?? []) {
      const iconId = (v as any).icon_id;
      voteCounts[iconId] = (voteCounts[iconId] ?? 0) + 1;
    }

    // Pick the most-voted icon, or first candidate if no votes
    let winningIconId: string | null = null;
    let maxVotes = 0;
    for (const [iconId, count] of Object.entries(voteCounts)) {
      if (count > maxVotes) {
        maxVotes = count;
        winningIconId = iconId;
      }
    }
    if (!winningIconId && candidateIds.length > 0) {
      winningIconId = candidateIds[0];
    }

    if (winningIconId) {
      const now = new Date();
      const biddingEndsAt = new Date(now.getTime() + 30 * 60 * 1000).toISOString();
      await supabase
        .from("icon_auctions")
        .update({
          phase: "active",
          selected_icon_id: winningIconId,
          starts_at: now.toISOString(),
          ends_at: biddingEndsAt,
        })
        .eq("id", auctionId);

      const { data: members } = await supabase
        .from("members")
        .select("id")
        .eq("tournament_id", auth.tournamentId);

      const { data: iconData } = await supabase
        .from("players")
        .select("name")
        .eq("id", winningIconId)
        .single();

      const { createBulkNotifications } = await import("@/lib/notifications");
      await createBulkNotifications(
        supabase,
        auth.tournamentId,
        (members ?? []).map((m: any) => m.id),
        "auction_started",
        "Subasta iniciada",
        `La subasta por ${(iconData as any)?.name ?? "un ícono"} ha comenzado. ¡30 minutos para pujar!`,
        { auctionId }
      );

      return NextResponse.json({ ok: true, action: "bidding_started", iconId: winningIconId });
    } else {
      await supabase
        .from("icon_auctions")
        .update({ phase: "finished", ends_at: new Date().toISOString() })
        .eq("id", auctionId);
      return NextResponse.json({ ok: true, action: "finished_no_candidates" });
    }
  }

  // Resolve winner for active auctions
  if (a.highest_bidder_id && a.highest_bid > 0) {
    await supabase
      .from("icon_auctions")
      .update({
        phase: "finished",
        ends_at: new Date().toISOString(),
        winner_id: a.highest_bidder_id,
        final_amount: a.highest_bid,
      })
      .eq("id", auctionId);

    // Budget was already reserved via budget_reserved, now finalize:
    // Deduct the reserved amount and mark icon_slot_used
    const { data: winner } = await supabase
      .from("members")
      .select("budget, budget_reserved")
      .eq("id", a.highest_bidder_id)
      .single();

    const wn = winner as any;
    await supabase
      .from("members")
      .update({
        budget: Math.max(0, (wn?.budget ?? 0) - a.highest_bid),
        budget_reserved: Math.max(0, (wn?.budget_reserved ?? 0) - a.highest_bid),
        icon_slot_used: true,
      })
      .eq("id", a.highest_bidder_id);

    await supabase.from("market_transfers").insert({
      session_id: a.session_id,
      player_id: a.selected_icon_id,
      buyer_id: a.highest_bidder_id,
      seller_id: null,
      amount: a.highest_bid,
      transfer_type: "icon_auction",
    });

    const { data: iconData } = await supabase
      .from("players")
      .select("name")
      .eq("id", a.selected_icon_id)
      .single();

    await createNotification({
      supabase,
      memberId: a.highest_bidder_id,
      tournamentId: auth.tournamentId,
      type: "auction_won",
      title: "¡Ganaste la subasta!",
      body: `Has ganado a ${(iconData as any)?.name ?? "un ícono"} por €${Math.floor(a.highest_bid / 1_000_000)}M`,
      metadata: { auctionId, amount: a.highest_bid },
    });
  } else {
    await supabase
      .from("icon_auctions")
      .update({ phase: "finished", ends_at: new Date().toISOString() })
      .eq("id", auctionId);
  }

  return NextResponse.json({ ok: true });
}
