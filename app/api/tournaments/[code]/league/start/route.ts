import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// Round-robin fixture generator (home & away double round-robin)
function generateRoundRobin(memberIds: string[]): {
  fixtures: Array<{ matchday: number; homeId: string; awayId: string }>;
  rests: Array<{ matchday: number; memberId: string }>;
  totalMatchdays: number;
} {
  const hasBye = memberIds.length % 2 !== 0;
  const teams: (string | null)[] = hasBye ? [...memberIds, null] : [...memberIds];
  const m = teams.length; // always even
  const rounds = m - 1;

  const fixtures: Array<{ matchday: number; homeId: string; awayId: string }> = [];
  const rests: Array<{ matchday: number; memberId: string }> = [];

  let arr = [...teams];

  for (let round = 0; round < rounds; round++) {
    const matchday = round + 1;
    for (let i = 0; i < m / 2; i++) {
      const home = arr[i];
      const away = arr[m - 1 - i];
      if (home === null) {
        rests.push({ matchday, memberId: away as string });
      } else if (away === null) {
        rests.push({ matchday, memberId: home as string });
      } else {
        fixtures.push({ matchday, homeId: home, awayId: away });
      }
    }
    // Rotate: keep arr[0] fixed, rotate the rest
    const last = arr[arr.length - 1];
    for (let i = arr.length - 1; i > 1; i--) arr[i] = arr[i - 1];
    arr[1] = last;
  }

  // Return leg: swap home/away
  const returnFixtures = fixtures.map((f) => ({
    matchday: f.matchday + rounds,
    homeId: f.awayId,
    awayId: f.homeId,
  }));
  const returnRests = rests.map((r) => ({
    matchday: r.matchday + rounds,
    memberId: r.memberId,
  }));

  return {
    fixtures: [...fixtures, ...returnFixtures],
    rests: [...rests, ...returnRests],
    totalMatchdays: rounds * 2,
  };
}

// POST /api/tournaments/[code]/league/start
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Check no session already exists
  const { data: existing } = await supabase
    .from("league_sessions")
    .select("id")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (existing) {
    return NextResponse.json({ error: "La liga ya fue iniciada." }, { status: 409 });
  }

  // Get all members with assigned teams
  const { data: assignments } = await supabase
    .from("assignments")
    .select("member_id")
    .eq("tournament_id", auth.tournamentId);

  const memberIds = (assignments ?? []).map((a: any) => a.member_id as string);

  if (memberIds.length < 2) {
    return NextResponse.json({ error: "Se necesitan al menos 2 participantes con equipo." }, { status: 400 });
  }

  // Shuffle for random initial order
  for (let i = memberIds.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [memberIds[i], memberIds[j]] = [memberIds[j], memberIds[i]];
  }

  const { fixtures, rests, totalMatchdays } = generateRoundRobin(memberIds);

  // Create league session
  const { data: session, error: sessionErr } = await supabase
    .from("league_sessions")
    .insert({
      tournament_id: auth.tournamentId,
      status: "active",
      current_matchday: 1,
      total_matchdays: totalMatchdays,
      started_at: new Date().toISOString(),
    })
    .select("id")
    .single();

  if (sessionErr || !session) {
    return NextResponse.json({ error: "Error al crear la sesión de liga." }, { status: 500 });
  }

  const sessionId = (session as any).id;

  // Insert all fixtures
  const fixtureRows = fixtures.map((f) => ({
    session_id: sessionId,
    matchday: f.matchday,
    home_member_id: f.homeId,
    away_member_id: f.awayId,
  }));

  const { error: fixtureErr } = await supabase.from("fixtures").insert(fixtureRows);
  if (fixtureErr) {
    console.error("[league/start] fixtures", fixtureErr);
    return NextResponse.json({ error: "Error al insertar partidos." }, { status: 500 });
  }

  // Insert rest slots
  if (rests.length > 0) {
    const restRows = rests.map((r) => ({
      session_id: sessionId,
      matchday: r.matchday,
      member_id: r.memberId,
    }));
    await supabase.from("matchday_rests").insert(restRows);
  }

  // Update tournament status
  await supabase
    .from("tournaments")
    .update({ status: "league" })
    .eq("id", auth.tournamentId);

  return NextResponse.json({ ok: true, totalMatchdays });
}
