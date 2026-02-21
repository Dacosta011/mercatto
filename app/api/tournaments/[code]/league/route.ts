import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// GET /api/tournaments/[code]/league
export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Tournament + admin check
  const { data: tournament } = await supabase
    .from("tournaments")
    .select("id, name, status, admin_token_hash")
    .eq("id", auth.tournamentId)
    .single();

  if (!tournament) return NextResponse.json({ error: "Torneo no encontrado." }, { status: 404 });

  // Check admin via header
  const authHeader = request.headers.get("Authorization") ?? "";
  const rawToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
  const { createHash } = await import("crypto");
  const tokenHash = createHash("sha256").update(rawToken).digest("hex");
  const isAdmin = tokenHash === (tournament as any).admin_token_hash;

  // League session
  const { data: session } = await supabase
    .from("league_sessions")
    .select("id, status, current_matchday, total_matchdays, started_at, finished_at")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session) {
    return NextResponse.json({
      status: "pending",
      session: null,
      isAdmin,
      myMemberId: auth.memberId,
      tournamentName: (tournament as any).name,
    });
  }

  const sessionId = (session as any).id;
  const currentMatchday = (session as any).current_matchday;

  // All members with display names and team names
  const { data: membersRaw } = await supabase
    .from("members")
    .select("id, display_name")
    .eq("tournament_id", auth.tournamentId);

  const { data: assignmentsRaw } = await supabase
    .from("assignments")
    .select("member_id, team_id")
    .eq("tournament_id", auth.tournamentId);

  const { data: teamsRaw } = await supabase.from("teams").select("id, name");

  const teamNameById: Record<string, string> = {};
  for (const t of teamsRaw ?? []) teamNameById[(t as any).id] = (t as any).name;

  const teamByMember: Record<string, string> = {};
  for (const a of assignmentsRaw ?? []) teamByMember[(a as any).member_id] = (a as any).team_id;

  const memberById: Record<string, { displayName: string; teamName: string }> = {};
  for (const m of membersRaw ?? []) {
    const tid = teamByMember[(m as any).id];
    memberById[(m as any).id] = {
      displayName: (m as any).display_name,
      teamName: tid ? (teamNameById[tid] ?? "—") : "—",
    };
  }

  // All fixtures
  const { data: allFixturesRaw } = await supabase
    .from("fixtures")
    .select("*")
    .eq("session_id", sessionId)
    .order("matchday", { ascending: true });

  const enrichFixture = (f: any) => ({
    id: f.id,
    matchday: f.matchday,
    status: f.status,
    homeMember: { id: f.home_member_id, ...memberById[f.home_member_id] },
    awayMember: { id: f.away_member_id, ...memberById[f.away_member_id] },
    homeConfirmed: f.home_confirmed,
    awayConfirmed: f.away_confirmed,
    homeGoals: f.home_goals,
    awayGoals: f.away_goals,
    homeYellow: f.home_yellow,
    awayYellow: f.away_yellow,
    homeRed: f.home_red,
    awayRed: f.away_red,
    resultSubmitterId: f.result_submitter_id,
    pendingHomeGoals: f.pending_home_goals,
    pendingAwayGoals: f.pending_away_goals,
    pendingCards: f.pending_cards ?? [],
    startedAt: f.started_at,
    finishedAt: f.finished_at,
  });

  const allFixtures = (allFixturesRaw ?? []).map(enrichFixture);
  const currentFixtures = allFixtures.filter((f) => f.matchday === currentMatchday);

  // Rests for current matchday
  const { data: restRaw } = await supabase
    .from("matchday_rests")
    .select("member_id")
    .eq("session_id", sessionId)
    .eq("matchday", currentMatchday)
    .maybeSingle();

  const restMember = restRaw
    ? { memberId: (restRaw as any).member_id, ...memberById[(restRaw as any).member_id] }
    : null;

  // ── League table (computed from finished fixtures) ────────────────────────
  interface TableRow {
    memberId: string; displayName: string; teamName: string;
    played: number; wins: number; draws: number; losses: number;
    gf: number; ga: number; gd: number; points: number;
  }

  const tableMap: Record<string, TableRow> = {};
  for (const m of membersRaw ?? []) {
    const mid = (m as any).id;
    tableMap[mid] = {
      memberId: mid,
      displayName: memberById[mid]?.displayName ?? "—",
      teamName: memberById[mid]?.teamName ?? "—",
      played: 0, wins: 0, draws: 0, losses: 0,
      gf: 0, ga: 0, gd: 0, points: 0,
    };
  }

  for (const f of allFixtures.filter((f) => f.status === "finished")) {
    const hg = f.homeGoals ?? 0;
    const ag = f.awayGoals ?? 0;
    const hRow = tableMap[f.homeMember.id];
    const aRow = tableMap[f.awayMember.id];
    if (!hRow || !aRow) continue;

    hRow.played++; aRow.played++;
    hRow.gf += hg; hRow.ga += ag;
    aRow.gf += ag; aRow.ga += hg;

    if (hg > ag) {
      hRow.wins++; hRow.points += 3; aRow.losses++;
    } else if (hg < ag) {
      aRow.wins++; aRow.points += 3; hRow.losses++;
    } else {
      hRow.draws++; hRow.points += 1;
      aRow.draws++; aRow.points += 1;
    }
  }

  for (const row of Object.values(tableMap)) row.gd = row.gf - row.ga;

  const table = Object.values(tableMap).sort((a, b) =>
    b.points - a.points || b.gd - a.gd || b.gf - a.gf
  );

  // ── Discipline per player ─────────────────────────────────────────────────
  const { data: disciplineRaw } = await supabase
    .from("discipline")
    .select("member_id, player_id, player_name, card_type, matchday")
    .eq("session_id", sessionId);

  const { data: suspensionsRaw } = await supabase
    .from("suspensions")
    .select("member_id, player_id, player_name, reason, from_matchday, matches_remaining")
    .eq("session_id", sessionId);

  // Per-player accumulation
  const disciplineByPlayer: Record<string, { playerName: string; memberId: string; yellows: number; reds: number }> = {};
  for (const d of disciplineRaw ?? []) {
    const pid = (d as any).player_id;
    if (!pid) continue;
    if (!disciplineByPlayer[pid]) {
      disciplineByPlayer[pid] = { playerName: (d as any).player_name ?? pid, memberId: (d as any).member_id, yellows: 0, reds: 0 };
    }
    if ((d as any).card_type === "yellow") disciplineByPlayer[pid].yellows++;
    else disciplineByPlayer[pid].reds++;
  }

  // Currently suspended players (for current matchday)
  const suspendedPlayerIds = new Set(
    (suspensionsRaw ?? [])
      .filter((s: any) => s.from_matchday <= currentMatchday &&
        s.from_matchday + s.matches_remaining > currentMatchday)
      .map((s: any) => s.player_id)
      .filter(Boolean)
  );

  const discipline = Object.entries(disciplineByPlayer).map(([pid, stats]) => ({
    playerId: pid,
    playerName: stats.playerName,
    memberId: stats.memberId,
    displayName: memberById[stats.memberId]?.displayName ?? "—",
    teamName: memberById[stats.memberId]?.teamName ?? "—",
    yellows: stats.yellows,
    reds: stats.reds,
    suspended: suspendedPlayerIds.has(pid),
    yellowsToSuspension: 3 - (stats.yellows % 3),
  }));

  // My discipline summary (any of my players suspended?)
  const myPlayersSuspended = discipline.filter(d => d.memberId === auth.memberId && d.suspended);
  const myDiscipline = {
    yellows: discipline.filter(d => d.memberId === auth.memberId).reduce((s, d) => s + d.yellows, 0),
    reds: discipline.filter(d => d.memberId === auth.memberId).reduce((s, d) => s + d.reds, 0),
    suspended: myPlayersSuspended.length > 0,
    suspendedPlayers: myPlayersSuspended.map(d => d.playerName),
    yellowsToSuspension: 0,
  };

  // All matchday done?
  const currentMatchdayFinished = currentFixtures.every((f) => f.status === "finished");

  return NextResponse.json({
    status: (session as any).status,
    session: {
      id: sessionId,
      currentMatchday,
      totalMatchdays: (session as any).total_matchdays,
    },
    tournamentName: (tournament as any).name,
    isAdmin,
    myMemberId: auth.memberId,
    currentFixtures,
    allFixtures,
    restMember,
    table,
    discipline,
    myDiscipline,
    currentMatchdayFinished,
    allMembers: Object.entries(memberById).map(([id, m]) => ({ id, ...m })),
  });
}
