import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/seasons ──────────────────────────────────────
// Returns the historical archive of past seasons (champion, standings,
// discipline, fixtures and per-member assignments) for the lobby's current
// tournament. Newest season first.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: archives } = await supabase
    .from("season_archives")
    .select(
      "id, season_number, started_at, finished_at, total_matchdays, " +
      "champion_member_id, champion_display_name, champion_team_id, champion_team_name, " +
      "standings, discipline"
    )
    .eq("tournament_id", auth.tournamentId)
    .order("season_number", { ascending: false });

  const archiveList = (archives ?? []) as any[];
  const ids = archiveList.map((a) => a.id as string);

  const [{ data: fixturesRaw }, { data: assignmentsRaw }] = ids.length > 0
    ? await Promise.all([
        supabase
          .from("season_archive_fixtures")
          .select("archive_id, matchday, home_member_id, away_member_id, home_display_name, away_display_name, home_team_name, away_team_name, home_goals, away_goals, status, finished_at")
          .in("archive_id", ids)
          .order("matchday", { ascending: true }),
        supabase
          .from("season_archive_assignments")
          .select("archive_id, member_id, display_name, team_id, team_name")
          .in("archive_id", ids),
      ])
    : [{ data: [] }, { data: [] }];

  const fixturesByArchive: Record<string, any[]> = {};
  for (const f of fixturesRaw ?? []) {
    const aid = (f as any).archive_id as string;
    (fixturesByArchive[aid] ??= []).push({
      matchday: (f as any).matchday,
      homeDisplayName: (f as any).home_display_name,
      awayDisplayName: (f as any).away_display_name,
      homeTeamName: (f as any).home_team_name,
      awayTeamName: (f as any).away_team_name,
      homeGoals: (f as any).home_goals,
      awayGoals: (f as any).away_goals,
      status: (f as any).status,
      finishedAt: (f as any).finished_at,
    });
  }

  const assignmentsByArchive: Record<string, any[]> = {};
  for (const a of assignmentsRaw ?? []) {
    const aid = (a as any).archive_id as string;
    (assignmentsByArchive[aid] ??= []).push({
      memberId: (a as any).member_id,
      displayName: (a as any).display_name,
      teamId: (a as any).team_id,
      teamName: (a as any).team_name,
    });
  }

  const seasons = archiveList.map((a) => ({
    id: a.id,
    seasonNumber: a.season_number,
    startedAt: a.started_at,
    finishedAt: a.finished_at,
    totalMatchdays: a.total_matchdays,
    champion: a.champion_member_id
      ? {
          memberId: a.champion_member_id,
          displayName: a.champion_display_name,
          teamId: a.champion_team_id,
          teamName: a.champion_team_name,
        }
      : null,
    standings: a.standings ?? [],
    discipline: a.discipline ?? [],
    fixtures: fixturesByArchive[a.id] ?? [],
    assignments: assignmentsByArchive[a.id] ?? [],
  }));

  return NextResponse.json({ seasons });
}
