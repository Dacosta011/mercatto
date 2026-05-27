import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/market/history ────────────────────────────────
// Without ?sessionId  → list of all market sessions for this tournament
// With    ?sessionId  → full per-member breakdown for that session

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();
  const sessionId = request.nextUrl.searchParams.get("sessionId");

  // ── List of sessions ────────────────────────────────────────────────────────
  const { data: sessions } = await supabase
    .from("market_sessions")
    .select("id, status, market_type, started_at, finished_at, closes_at")
    .eq("tournament_id", auth.tournamentId)
    .order("started_at", { ascending: false });

  if (!sessionId) {
    // Enrich each session with a transfer count
    const sessionList = await Promise.all(
      (sessions ?? []).map(async (s: any) => {
        const { count } = await supabase
          .from("market_transfers")
          .select("id", { count: "exact", head: true })
          .eq("session_id", s.id)
          .gte("created_at", s.started_at)
          .in("transfer_type", ["clause", "offer", "icon_auction"]);

        return {
          id: s.id,
          status: s.status,
          marketType: s.market_type ?? "regular",
          startedAt: s.started_at,
          finishedAt: s.finished_at,
          closesAt: s.closes_at,
          transferCount: count ?? 0,
        };
      })
    );

    return NextResponse.json({ sessions: sessionList });
  }

  // ── Full breakdown for a specific session ───────────────────────────────────
  const session = (sessions ?? []).find((s: any) => s.id === sessionId);
  if (!session) {
    return NextResponse.json({ error: "Sesión no encontrada." }, { status: 404 });
  }
  const s = session as any;

  // Members + teams
  const { data: allMembersRaw } = await supabase
    .from("members")
    .select("id, display_name")
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

  const memberById: Record<string, any> = {};
  for (const m of allMembersRaw ?? []) memberById[(m as any).id] = m;

  const teamIdByMember: Record<string, string> = {};
  for (const a of allAssignments ?? []) {
    teamIdByMember[(a as any).member_id] = (a as any).team_id;
  }

  const teamNameById: Record<string, string> = {};
  const teamCrestById: Record<string, string | null> = {};
  for (const t of allTeamsRaw ?? []) {
    teamNameById[(t as any).id] = (t as any).name;
    teamCrestById[(t as any).id] = (t as any).crest_url ?? null;
  }

  // Transfers for this session (scoped to started_at so restarts don't bleed)
  const { data: transfersRaw } = await supabase
    .from("market_transfers")
    .select("id, buyer_id, seller_id, seller_team_id, player_id, transfer_type, amount, created_at")
    .eq("session_id", sessionId)
    .gte("created_at", s.started_at)
    .in("transfer_type", ["clause", "offer", "icon_auction"])
    .order("created_at", { ascending: false })
    .limit(1000);

  // Player names
  const playerIds = [...new Set((transfersRaw ?? []).map((t: any) => t.player_id))];
  const { data: playersRaw } = playerIds.length > 0
    ? await supabase.from("players").select("id, name").in("id", playerIds)
    : { data: [] };

  const playerNameById: Record<string, string> = {};
  for (const p of playersRaw ?? []) playerNameById[(p as any).id] = (p as any).name;

  const transfers = (transfersRaw ?? []).map((t: any) => ({
    id: t.id,
    transferType: t.transfer_type as string,
    amount: t.amount as number,
    createdAt: t.created_at as string,
    buyerId: t.buyer_id as string | null,
    sellerId: t.seller_id as string | null,
    buyerName: memberById[t.buyer_id]?.display_name ?? "—",
    sellerName: memberById[t.seller_id]?.display_name ?? "—",
    sellerTeamName: teamNameById[t.seller_team_id] ?? "—",
    playerName: playerNameById[t.player_id] ?? "—",
  }));

  // Per-member breakdown
  const transfersByMember: Record<string, { bought: any[]; sold: any[] }> = {};
  for (const m of allMembersRaw ?? []) {
    transfersByMember[(m as any).id] = { bought: [], sold: [] };
  }
  for (const t of transfers) {
    if (t.buyerId && transfersByMember[t.buyerId])
      transfersByMember[t.buyerId].bought.push(t);
    if (t.sellerId && transfersByMember[t.sellerId])
      transfersByMember[t.sellerId].sold.push(t);
  }

  const members = (allMembersRaw ?? []).map((m: any) => {
    const tid = teamIdByMember[m.id];
    const tx = transfersByMember[m.id] ?? { bought: [], sold: [] };
    return {
      id: m.id,
      displayName: m.display_name,
      teamName: tid ? (teamNameById[tid] ?? null) : null,
      teamCrestUrl: tid ? (teamCrestById[tid] ?? null) : null,
      bought: tx.bought,
      sold: tx.sold,
      totalSpent: tx.bought.reduce((s: number, t: any) => s + (t.amount ?? 0), 0),
    };
  }).sort((a, b) => (b.bought.length + b.sold.length) - (a.bought.length + a.sold.length));

  const totalSpent = transfers.reduce((s, t) => s + (t.amount ?? 0), 0);
  const biggestDeal = transfers.length > 0
    ? transfers.reduce((a, b) => (b.amount ?? 0) > (a.amount ?? 0) ? b : a)
    : null;

  return NextResponse.json({
    session: {
      id: s.id,
      status: s.status,
      marketType: s.market_type ?? "regular",
      startedAt: s.started_at,
      finishedAt: s.finished_at,
    },
    stats: {
      totalTransfers: transfers.length,
      totalSpent,
      clauseCount: transfers.filter(t => t.transferType === "clause").length,
      auctionCount: transfers.filter(t => t.transferType === "icon_auction").length,
      offerCount: transfers.filter(t => t.transferType === "offer").length,
      biggestDeal,
    },
    members,
    transfers,
  });
}
