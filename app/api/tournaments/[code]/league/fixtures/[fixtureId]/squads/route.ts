import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string; fixtureId: string }> };

// GET /api/tournaments/[code]/league/fixtures/[fixtureId]/squads
// Returns players for both home and away members (base squad + market transfers)
export async function GET(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Get fixture to know both participants
  const { data: fixture } = await supabase
    .from("fixtures")
    .select("home_member_id, away_member_id, session_id")
    .eq("id", fixtureId)
    .single();

  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });

  const memberIds = [(fixture as any).home_member_id, (fixture as any).away_member_id];
  const sessionId = (fixture as any).session_id;

  // Get market session for this league session's tournament
  const { data: leagueSession } = await supabase
    .from("league_sessions")
    .select("tournament_id")
    .eq("id", sessionId)
    .single();

  const tournamentId = (leagueSession as any)?.tournament_id;

  // Get assignments for both members
  const { data: assignments } = await supabase
    .from("assignments")
    .select("member_id, team_id")
    .in("member_id", memberIds);

  const teamIdByMember: Record<string, string> = {};
  for (const a of assignments ?? []) teamIdByMember[(a as any).member_id] = (a as any).team_id;

  // Get member display names
  const { data: membersRaw } = await supabase
    .from("members")
    .select("id, display_name")
    .in("id", memberIds);

  const nameById: Record<string, string> = {};
  for (const m of membersRaw ?? []) nameById[(m as any).id] = (m as any).display_name;

  // Get teams names
  const teamIds = Object.values(teamIdByMember);
  const { data: teamsRaw } = teamIds.length > 0
    ? await supabase.from("teams").select("id, name").in("id", teamIds)
    : { data: [] };
  const teamNameById: Record<string, string> = {};
  for (const t of teamsRaw ?? []) teamNameById[(t as any).id] = (t as any).name;

  // Get market session (if any) to apply transfers
  let marketTransfers: Array<{ buyerMemberId: string; playerIds: string[]; sellerTeamId: string }> = [];
  if (tournamentId) {
    const { data: marketSession } = await supabase
      .from("market_sessions")
      .select("id")
      .eq("tournament_id", tournamentId)
      .maybeSingle();

    if (marketSession) {
      const { data: transfers } = await supabase
        .from("market_transfers")
        .select("buyer_id, seller_team_id, player_id, transfer_type")
        .eq("session_id", (marketSession as any).id)
        .in("transfer_type", ["clause", "offer", "icon_auction"]);

      // Group by buyer member
      const buyerMap: Record<string, string[]> = {};
      const soldFromTeam: Record<string, string[]> = {};
      for (const t of transfers ?? []) {
        const buyerId = (t as any).buyer_id;
        const sellerTeamId = (t as any).seller_team_id;
        const playerId = (t as any).player_id;
        if (!buyerMap[buyerId]) buyerMap[buyerId] = [];
        buyerMap[buyerId].push(playerId);
        if (!soldFromTeam[sellerTeamId]) soldFromTeam[sellerTeamId] = [];
        soldFromTeam[sellerTeamId].push(playerId);
      }
      for (const [buyerMemberId, playerIds] of Object.entries(buyerMap)) {
        const sellerTeamId = Object.keys(soldFromTeam).find(tid =>
          soldFromTeam[tid].some(pid => playerIds.includes(pid))
        ) ?? "";
        marketTransfers.push({ buyerMemberId, playerIds, sellerTeamId });
      }
    }
  }

  // Get current matchday to determine suspended players
  const { data: leagueSessionFull } = await supabase
    .from("league_sessions")
    .select("current_matchday")
    .eq("id", sessionId)
    .single();
  const currentMatchday = (leagueSessionFull as any)?.current_matchday ?? 1;

  const { data: suspensionsRaw } = await supabase
    .from("suspensions")
    .select("player_id, from_matchday, matches_remaining")
    .eq("session_id", sessionId);

  const suspendedPlayerIds = new Set(
    (suspensionsRaw ?? [])
      .filter((s: any) => s.player_id && s.from_matchday <= currentMatchday &&
        s.from_matchday + s.matches_remaining > currentMatchday)
      .map((s: any) => s.player_id)
  );

  // Build squads for each member
  const result: Record<string, { memberId: string; displayName: string; teamName: string; players: any[] }> = {};

  for (const memberId of memberIds) {
    const teamId = teamIdByMember[memberId];
    if (!teamId) continue;

    // Base squad from team_players
    const { data: teamPlayers } = await supabase
      .from("team_players")
      .select("player_id")
      .eq("team_id", teamId);

    const baseIds = new Set((teamPlayers ?? []).map((r: any) => r.player_id as string));

    // Remove sold players
    const soldIds = new Set<string>();
    for (const t of marketTransfers) {
      if (t.sellerTeamId === teamId) t.playerIds.forEach(id => soldIds.add(id));
    }

    // Add bought players
    const boughtIds = new Set<string>();
    for (const t of marketTransfers) {
      if (t.buyerMemberId === memberId) t.playerIds.forEach(id => boughtIds.add(id));
    }

    const finalIds = [...[...baseIds].filter(id => !soldIds.has(id)), ...boughtIds];

    let players: any[] = [];
    if (finalIds.length > 0) {
      const { data: playersData } = await supabase
        .from("players")
        .select("id, name, position, ovr")
        .in("id", finalIds)
        .order("ovr", { ascending: false });
      players = (playersData ?? []).map((p: any) => ({
        id: p.id, name: p.name, position: p.position ?? "—", ovr: p.ovr,
        suspended: suspendedPlayerIds.has(p.id),
      }));
    }

    result[memberId] = {
      memberId,
      displayName: nameById[memberId] ?? "—",
      teamName: teamNameById[teamId] ?? "—",
      players,
    };
  }

  return NextResponse.json({
    home: result[(fixture as any).home_member_id] ?? null,
    away: result[(fixture as any).away_member_id] ?? null,
  });
}
