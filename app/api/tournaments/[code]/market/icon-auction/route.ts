import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken, verifyAdminToken } from "@/lib/supabase";
import { getMinBid } from "@/lib/iconAuction";

type Params = { params: Promise<{ code: string }> };

// GET /api/tournaments/[code]/market/icon-auction
// Accepts both member tokens and admin tokens.
export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const supabase = createServerClient();

  // Try member token first, then admin token as fallback
  let tournamentId: string;
  let memberId: string | null = null;
  let isAdmin = false;

  const memberAuth = await verifyMemberToken(request, code);
  if (memberAuth.ok) {
    tournamentId = memberAuth.tournamentId;
    memberId = memberAuth.memberId;
  } else {
    const adminAuth = await verifyAdminToken(request, code);
    if (!adminAuth.ok) return NextResponse.json({ error: adminAuth.error }, { status: adminAuth.status });
    tournamentId = adminAuth.tournamentId;
    isAdmin = true;
  }

  // If came via member token, still check if they're also admin
  if (memberId) {
    const authHeader = request.headers.get("Authorization") ?? "";
    const rawToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    const { createHash } = await import("crypto");
    const tokenHash = createHash("sha256").update(rawToken).digest("hex");
    const { data: tournament } = await supabase
      .from("tournaments").select("admin_token_hash").eq("id", tournamentId).single();
    isAdmin = tokenHash === (tournament as any)?.admin_token_hash;
  }

  // Market session
  const { data: session } = await supabase
    .from("market_sessions").select("id, current_round, status")
    .eq("tournament_id", tournamentId).maybeSingle();

  // Members
  const { data: membersRaw } = await supabase
    .from("members").select("id, display_name, budget, market_purchases")
    .eq("tournament_id", tournamentId);

  const members = (membersRaw ?? []).map((m: any) => ({
    id: m.id,
    displayName: m.display_name,
    budget: m.budget ?? 0,
    purchasesUsed: m.market_purchases ?? 0,
  }));
  const memberNameById: Record<string, string> = {};
  for (const m of members) memberNameById[m.id] = m.displayName;

  if (!session) {
    return NextResponse.json({ auction: null, totalMembers: members.length, members, myVoteActivation: null, myVoteIcon: null, isAdmin });
  }

  // Current icon auction for this round
  const { data: auction } = await supabase
    .from("icon_auctions").select("*")
    .eq("session_id", (session as any).id)
    .eq("round_num", (session as any).current_round)
    .maybeSingle();

  if (!auction) {
    return NextResponse.json({ auction: null, totalMembers: members.length, members, myVoteActivation: null, myVoteIcon: null, isAdmin });
  }

  const auctionId = (auction as any).id;

  // ── Auto-resolve stuck auctions ──────────────────────────────────────────
  // If bidding phase has <=1 bidder remaining, finish automatically
  if ((auction as any).phase === "bidding") {
    const bidderOrder: string[] = (auction as any).bidder_order ?? [];
    const highestBid: number = (auction as any).highest_bid ?? 0;
    const highestBidderId: string | null = (auction as any).highest_bidder_id ?? null;
    const selectedIconId: string | null = (auction as any).selected_icon_id ?? null;

    if (selectedIconId) {
      if (bidderOrder.length === 0) {
        // No bidders — no winner
        await supabase.from("icon_auctions").update({
          phase: "finished",
          bidder_order: bidderOrder,
        }).eq("id", auctionId);

        const { data: updatedAuction } = await supabase
          .from("icon_auctions").select("*").eq("id", auctionId).single();
        Object.assign(auction as any, updatedAuction);
      } else if (bidderOrder.length === 1 && highestBid > 0 && highestBidderId) {
        // Single bidder with a bid — they win
        const { data: winnerMember } = await supabase
          .from("members").select("budget, market_purchases")
          .eq("id", highestBidderId).single();

        await supabase.from("members").update({
          budget: ((winnerMember as any)?.budget ?? 0) - highestBid,
          market_purchases: ((winnerMember as any)?.market_purchases ?? 0) + 1,
        }).eq("id", highestBidderId);

        await supabase.from("market_transfers").insert({
          session_id: (session as any).id,
          buyer_id: highestBidderId,
          player_id: selectedIconId,
          transfer_type: "icon_auction",
          amount: highestBid,
        });

        await supabase.from("icon_auctions").update({
          phase: "finished",
          bidder_order: bidderOrder,
          winner_id: highestBidderId,
          final_amount: highestBid,
        }).eq("id", auctionId);

        const { data: updatedAuction } = await supabase
          .from("icon_auctions").select("*").eq("id", auctionId).single();
        Object.assign(auction as any, updatedAuction);
      }
      // If 1 bidder remains but no bids yet — don't auto-finish, let them bid
    }
  }

  // Presented icons
  const presentedIds: string[] = (auction as any).presented_icon_ids ?? [];
  let presentedIcons: any[] = [];
  if (presentedIds.length > 0) {
    const { data: icons } = await supabase
      .from("players").select("id, name, ovr, position, country_name, headshot_url")
      .in("id", presentedIds);
    presentedIcons = (icons ?? []).map((p: any) => ({
      id: p.id, name: p.name, ovr: p.ovr,
      position: p.position, nation: p.country_name,
      minBid: getMinBid(p.ovr), headshotUrl: p.headshot_url ?? null,
    }));
    // Keep original order
    presentedIcons.sort((a, b) => presentedIds.indexOf(a.id) - presentedIds.indexOf(b.id));
  }

  // Activation votes
  const { data: activationVotesRaw } = await supabase
    .from("icon_activation_votes").select("member_id, vote").eq("auction_id", auctionId);
  const activationVotes = (activationVotesRaw ?? []).map((v: any) => ({ memberId: v.member_id, vote: v.vote }));
  const myVoteActivation = activationVotes.find((v) => v.memberId === memberId)?.vote ?? null;

  // Selected icon
  let selectedIcon = null;
  const selectedIconId = (auction as any).selected_icon_id;
  if (selectedIconId) {
    const { data: sIcon } = await supabase
      .from("players").select("id, name, ovr, position, country_name, headshot_url")
      .eq("id", selectedIconId).single();
    if (sIcon) {
      selectedIcon = {
        id: (sIcon as any).id, name: (sIcon as any).name, ovr: (sIcon as any).ovr,
        position: (sIcon as any).position, nation: (sIcon as any).country_name,
        minBid: getMinBid((sIcon as any).ovr), headshotUrl: (sIcon as any).headshot_url ?? null,
      };
    }
  }

  // Selection votes
  const { data: selVotesRaw } = await supabase
    .from("icon_selection_votes").select("member_id, icon_id").eq("auction_id", auctionId);
  const selectionVotes = (selVotesRaw ?? []).map((v: any) => ({ memberId: v.member_id, iconId: v.icon_id }));
  const myVoteIcon = selectionVotes.find((v) => v.memberId === memberId)?.iconId ?? null;

  // Check if current member already won an icon this session
  const { data: myWin } = memberId ? await supabase
    .from("icon_auctions")
    .select("id")
    .eq("session_id", (session as any).id)
    .eq("winner_id", memberId)
    .maybeSingle() : { data: null };
  const myIconWon = !!myWin;

  // Bids
  const { data: bidsRaw } = await supabase
    .from("icon_bids").select("member_id, amount, passed, created_at")
    .eq("auction_id", auctionId).order("created_at", { ascending: true });
  const bids = (bidsRaw ?? []).map((b: any) => ({
    memberId: b.member_id, memberName: memberNameById[b.member_id] ?? "—",
    amount: b.amount, passed: b.passed, createdAt: b.created_at,
  }));

  // Bidding state
  const bidderOrder: string[] = (auction as any).bidder_order ?? [];
  const currentBidderIndex = (auction as any).current_bidder_index ?? 0;
  const currentBidderId = bidderOrder.length > 0 ? bidderOrder[currentBidderIndex % bidderOrder.length] : null;
  const highestBidderId = (auction as any).highest_bidder_id ?? null;
  const winnerId = (auction as any).winner_id ?? null;

  return NextResponse.json({
    auction: {
      id: auctionId,
      phase: (auction as any).phase,
      roundNum: (auction as any).round_num,
      presentedIcons,
      activationVotes,
      activationVoteCount: activationVotes.length,
      selectedIcon,
      selectionVotes,
      selectionVoteCount: selectionVotes.length,
      highestBid: (auction as any).highest_bid ?? 0,
      highestBidderId,
      highestBidderName: highestBidderId ? (memberNameById[highestBidderId] ?? "—") : null,
      currentBidderId,
      currentBidderName: currentBidderId ? (memberNameById[currentBidderId] ?? "—") : null,
      bidderOrder,
      consecutivePasses: (auction as any).consecutive_passes ?? 0,
      bids,
      winnerId,
      winnerName: winnerId ? (memberNameById[winnerId] ?? "—") : null,
      finalAmount: (auction as any).final_amount ?? null,
    },
    totalMembers: members.length,
    members,
    myVoteActivation,
    myVoteIcon,
    myIconWon,
    isAdmin,
  });
}
