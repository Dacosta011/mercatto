import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

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
