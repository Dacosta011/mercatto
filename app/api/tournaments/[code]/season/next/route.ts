import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/season/next ─────────────────────────────────
// Admin only. Closes the current season and opens the next one in the same lobby:
//   1. Snapshot the finished league into season_archives + child tables.
//   2. Materialize all market transfers into team_players (carryover_all),
//      so whoever picks a given team next season inherits the final roster
//      with all signings made during the previous season.
//   3. Wipe per-tournament state: league_session, market_session, assignments,
//      lineups, member_roster.
//   4. Reset member fields (rerolls_used, budget, market_purchases, etc).
//   5. Increment tournaments.current_season and set status back to "lobby".
//
// IMPORTANT: this permanently mutates team_players. The "original" team
// rosters are NOT preserved. To reset clubs to their seed rosters you would
// need to re-run the team_players seed manually.

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // ── 0. Pre-conditions ───────────────────────────────────────────────────────
  const { data: tournament } = await supabase
    .from("tournaments")
    .select("id, current_season")
    .eq("id", auth.tournamentId)
    .single();

  if (!tournament) {
    return NextResponse.json({ error: "Torneo no encontrado." }, { status: 404 });
  }

  const currentSeason = (tournament as any).current_season ?? 1;

  const { data: leagueSession } = await supabase
    .from("league_sessions")
    .select("id, status, total_matchdays, started_at, finished_at")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!leagueSession || (leagueSession as any).status !== "finished") {
    return NextResponse.json(
      { error: "Solo se puede iniciar una nueva temporada cuando la liga ha finalizado." },
      { status: 409 },
    );
  }

  const leagueSessionId = (leagueSession as any).id as string;

  // ── 1. Build snapshot data (mirror of /league GET, lines 130-238) ──────────
  const [{ data: membersRaw }, { data: assignmentsRaw }, { data: teamsRaw }, { data: fixturesRaw }, { data: disciplineRaw }] =
    await Promise.all([
      supabase.from("members").select("id, display_name, budget").eq("tournament_id", auth.tournamentId),
      supabase.from("assignments").select("member_id, team_id").eq("tournament_id", auth.tournamentId),
      supabase.from("teams").select("id, name, crest_url"),
      supabase
        .from("fixtures")
        .select("matchday, home_member_id, away_member_id, status, home_goals, away_goals, finished_at")
        .eq("session_id", leagueSessionId)
        .order("matchday", { ascending: true }),
      supabase
        .from("discipline")
        .select("member_id, player_id, player_name, card_type, matchday")
        .eq("session_id", leagueSessionId),
    ]);

  const teamById: Record<string, { name: string; crestUrl: string | null }> = {};
  for (const t of teamsRaw ?? []) {
    teamById[(t as any).id] = { name: (t as any).name, crestUrl: (t as any).crest_url ?? null };
  }

  const teamByMember: Record<string, string> = {};
  for (const a of assignmentsRaw ?? []) teamByMember[(a as any).member_id] = (a as any).team_id;

  const memberById: Record<string, { displayName: string; teamId: string | null; teamName: string }> = {};
  for (const m of membersRaw ?? []) {
    const tid = teamByMember[(m as any).id] ?? null;
    memberById[(m as any).id] = {
      displayName: (m as any).display_name,
      teamId: tid,
      teamName: tid ? (teamById[tid]?.name ?? "—") : "—",
    };
  }

  // Standings (only members with a team assignment)
  interface TableRow {
    memberId: string; displayName: string; teamName: string; crestUrl: string | null;
    played: number; wins: number; draws: number; losses: number;
    gf: number; ga: number; gd: number; points: number;
  }
  const tableMap: Record<string, TableRow> = {};
  const assignedMemberIds = new Set((assignmentsRaw ?? []).map((a: any) => a.member_id as string));
  for (const m of membersRaw ?? []) {
    const mid = (m as any).id;
    if (!assignedMemberIds.has(mid)) continue;
    const info = memberById[mid];
    tableMap[mid] = {
      memberId: mid,
      displayName: info?.displayName ?? "—",
      teamName: info?.teamName ?? "—",
      crestUrl: info?.teamId ? (teamById[info.teamId]?.crestUrl ?? null) : null,
      played: 0, wins: 0, draws: 0, losses: 0,
      gf: 0, ga: 0, gd: 0, points: 0,
    };
  }

  for (const f of fixturesRaw ?? []) {
    if ((f as any).status !== "finished") continue;
    const hg = (f as any).home_goals ?? 0;
    const ag = (f as any).away_goals ?? 0;
    const hRow = tableMap[(f as any).home_member_id];
    const aRow = tableMap[(f as any).away_member_id];
    if (!hRow || !aRow) continue;
    hRow.played++; aRow.played++;
    hRow.gf += hg; hRow.ga += ag;
    aRow.gf += ag; aRow.ga += hg;
    if (hg > ag) { hRow.wins++; hRow.points += 3; aRow.losses++; }
    else if (hg < ag) { aRow.wins++; aRow.points += 3; hRow.losses++; }
    else { hRow.draws++; hRow.points += 1; aRow.draws++; aRow.points += 1; }
  }
  for (const row of Object.values(tableMap)) row.gd = row.gf - row.ga;

  const standings = Object.values(tableMap).sort((a, b) =>
    b.points - a.points || b.gd - a.gd || b.gf - a.gf
  );

  const champion = standings[0] ?? null;

  // Discipline aggregated per player
  const disciplineByPlayer: Record<string, { playerName: string; memberId: string; yellows: number; reds: number }> = {};
  for (const d of disciplineRaw ?? []) {
    const pid = (d as any).player_id;
    if (!pid) continue;
    if (!disciplineByPlayer[pid]) {
      disciplineByPlayer[pid] = {
        playerName: (d as any).player_name ?? pid,
        memberId: (d as any).member_id,
        yellows: 0,
        reds: 0,
      };
    }
    if ((d as any).card_type === "yellow") disciplineByPlayer[pid].yellows++;
    else disciplineByPlayer[pid].reds++;
  }
  const disciplineSnapshot = Object.entries(disciplineByPlayer).map(([pid, stats]) => ({
    playerId: pid,
    playerName: stats.playerName,
    memberId: stats.memberId,
    displayName: memberById[stats.memberId]?.displayName ?? "—",
    teamName: memberById[stats.memberId]?.teamName ?? "—",
    yellows: stats.yellows,
    reds: stats.reds,
  }));

  // ── 2. Insert season_archives row ──────────────────────────────────────────
  const { data: archive, error: archiveErr } = await supabase
    .from("season_archives")
    .insert({
      tournament_id: auth.tournamentId,
      season_number: currentSeason,
      started_at: (leagueSession as any).started_at,
      finished_at: (leagueSession as any).finished_at ?? new Date().toISOString(),
      total_matchdays: (leagueSession as any).total_matchdays,
      champion_member_id: champion?.memberId ?? null,
      champion_display_name: champion?.displayName ?? null,
      champion_team_id: champion ? (memberById[champion.memberId]?.teamId ?? null) : null,
      champion_team_name: champion?.teamName ?? null,
      standings,
      discipline: disciplineSnapshot,
    })
    .select("id")
    .single();

  if (archiveErr || !archive) {
    console.error("[season/next] archive", archiveErr);
    return NextResponse.json({ error: "Error al archivar la temporada." }, { status: 500 });
  }
  const archiveId = (archive as any).id as string;

  // Archive fixtures (one row per match, names denormalised)
  const fixtureRows = (fixturesRaw ?? []).map((f: any) => ({
    archive_id: archiveId,
    matchday: f.matchday,
    home_member_id: f.home_member_id,
    away_member_id: f.away_member_id,
    home_display_name: memberById[f.home_member_id]?.displayName ?? null,
    away_display_name: memberById[f.away_member_id]?.displayName ?? null,
    home_team_name: memberById[f.home_member_id]?.teamName ?? null,
    away_team_name: memberById[f.away_member_id]?.teamName ?? null,
    home_goals: f.home_goals,
    away_goals: f.away_goals,
    status: f.status,
    finished_at: f.finished_at,
  }));
  if (fixtureRows.length > 0) {
    await supabase.from("season_archive_fixtures").insert(fixtureRows);
  }

  // Archive assignments (final team each member had this season)
  const assignmentRows = Object.entries(memberById)
    .filter(([, info]) => info.teamId)
    .map(([mid, info]) => ({
      archive_id: archiveId,
      member_id: mid,
      display_name: info.displayName,
      team_id: info.teamId,
      team_name: info.teamName,
    }));
  if (assignmentRows.length > 0) {
    await supabase.from("season_archive_assignments").insert(assignmentRows);
  }

  // ── 3. Materialize transfers into team_players (carryover_all) ─────────────
  const { data: marketSession } = await supabase
    .from("market_sessions")
    .select("id")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  const marketSessionId = marketSession ? ((marketSession as any).id as string) : null;

  if (marketSessionId) {
    const { data: transfers } = await supabase
      .from("market_transfers")
      .select("buyer_id, player_id, transfer_type")
      .eq("session_id", marketSessionId)
      .in("transfer_type", ["clause", "offer", "icon_auction"])
      .order("created_at", { ascending: true });

    // Walk transfers in chronological order to compute the final team per player
    const finalTeamByPlayer: Record<string, string> = {};
    for (const t of transfers ?? []) {
      const buyerTeam = teamByMember[(t as any).buyer_id];
      if (buyerTeam) finalTeamByPlayer[(t as any).player_id] = buyerTeam;
    }

    if (Object.keys(finalTeamByPlayer).length > 0) {
      // Fetch current team_players rows for these players
      const playerIds = Object.keys(finalTeamByPlayer);
      const { data: currentLinks } = await supabase
        .from("team_players")
        .select("team_id, player_id")
        .in("player_id", playerIds);

      const currentTeamByPlayer: Record<string, string | null> = {};
      for (const l of currentLinks ?? []) {
        currentTeamByPlayer[(l as any).player_id] = (l as any).team_id;
      }

      // Apply diff: delete old link if different, insert new link
      for (const [playerId, finalTeamId] of Object.entries(finalTeamByPlayer)) {
        const oldTeamId = currentTeamByPlayer[playerId] ?? null;
        if (oldTeamId === finalTeamId) continue;
        if (oldTeamId) {
          await supabase
            .from("team_players")
            .delete()
            .eq("team_id", oldTeamId)
            .eq("player_id", playerId);
        }
        await supabase
          .from("team_players")
          .insert({ team_id: finalTeamId, player_id: playerId });
      }
    }
  }

  // ── 4. Wipe per-tournament active state ────────────────────────────────────
  // 4a. Market session (and its dependents)
  if (marketSessionId) {
    const { data: auctions } = await supabase
      .from("icon_auctions")
      .select("id")
      .eq("session_id", marketSessionId);
    const auctionIds = (auctions ?? []).map((a: any) => a.id as string);
    if (auctionIds.length > 0) {
      await supabase.from("icon_bids").delete().in("auction_id", auctionIds);
      await supabase.from("icon_selection_votes").delete().in("auction_id", auctionIds);
      await supabase.from("icon_activation_votes").delete().in("auction_id", auctionIds);
      await supabase.from("icon_votes").delete().in("auction_id", auctionIds);
    }
    await supabase.from("icon_auctions").delete().eq("session_id", marketSessionId);
    await supabase.from("market_offers").delete().eq("session_id", marketSessionId);
    await supabase.from("market_transfers").delete().eq("session_id", marketSessionId);
    await supabase.from("market_turns").delete().eq("session_id", marketSessionId);
    await supabase.from("market_sessions").delete().eq("id", marketSessionId);
  }

  // 4b. League session (cascades to fixtures, discipline, suspensions, matchday_rests)
  await supabase.from("league_sessions").delete().eq("tournament_id", auth.tournamentId);

  // 4c. Snapshot end-of-season budget onto each member's team. Whoever spins
  //     this team in a future season inherits that balance (per_team carry-over).
  //     Teams that nobody had this season are NOT inserted, so the next spin on
  //     them will fall back to the OVR-based formula in /spin.
  const budgetByMember: Record<string, number | null> = {};
  for (const m of membersRaw ?? []) {
    budgetByMember[(m as any).id] = (m as any).budget ?? null;
  }
  const teamBudgetRows = Object.entries(memberById)
    .filter(([mid, info]) => info.teamId && budgetByMember[mid] != null)
    .map(([mid, info]) => ({
      tournament_id: auth.tournamentId,
      team_id: info.teamId as string,
      budget: budgetByMember[mid] as number,
    }));
  if (teamBudgetRows.length > 0) {
    await supabase.from("team_budgets").upsert(teamBudgetRows, {
      onConflict: "tournament_id,team_id",
    });
  }

  // 4d. Assignments
  await supabase.from("assignments").delete().eq("tournament_id", auth.tournamentId);

  // 4e. Lineups + member_roster (per-tournament/per-member)
  const memberIds = (membersRaw ?? []).map((m: any) => m.id as string);
  if (memberIds.length > 0) {
    await supabase.from("lineups").delete().in("member_id", memberIds);
  }
  await supabase.from("member_roster").delete().eq("tournament_id", auth.tournamentId);

  // ── 5. Reset member fields so everyone re-spins on a clean slate ───────────
  // The personal budget is wiped: it has just been snapshotted onto the team
  // (step 4c). On the next spin the member inherits whatever the team they
  // pick was left with, or falls back to the OVR formula for unowned teams.
  if (memberIds.length > 0) {
    await supabase
      .from("members")
      .update({
        rerolls_used: 0,
        market_purchases: 0,
        icon_slot_used: false,
        budget_reserved: 0,
        budget: null,
      })
      .in("id", memberIds);
  }

  // ── 6. Advance the tournament to the next season ──────────────────────────
  const newSeason = currentSeason + 1;
  await supabase
    .from("tournaments")
    .update({ current_season: newSeason, status: "lobby" })
    .eq("id", auth.tournamentId);

  return NextResponse.json({
    ok: true,
    archivedSeason: currentSeason,
    newSeason,
    archiveId,
    champion: champion
      ? { displayName: champion.displayName, teamName: champion.teamName }
      : null,
  });
}
