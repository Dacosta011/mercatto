import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// POST /api/tournaments/[code]/league/close-matchday
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("league_sessions")
    .select("id, current_matchday, total_matchdays, status")
    .eq("tournament_id", auth.tournamentId)
    .single();

  if (!session) return NextResponse.json({ error: "Liga no iniciada." }, { status: 404 });
  if ((session as any).status === "finished")
    return NextResponse.json({ error: "La liga ya ha finalizado." }, { status: 409 });

  const sessionId = (session as any).id;
  const currentMatchday = (session as any).current_matchday;

  // Verify all fixtures in current matchday are finished
  const { data: currentFixtures } = await supabase
    .from("fixtures")
    .select("id, status")
    .eq("session_id", sessionId)
    .eq("matchday", currentMatchday);

  const allFinished = (currentFixtures ?? []).every((f: any) => f.status === "finished");
  if (!allFinished)
    return NextResponse.json({ error: "Hay partidos pendientes en esta fecha." }, { status: 400 });

  const nextMatchday = currentMatchday + 1;
  const isLastMatchday = currentMatchday >= (session as any).total_matchdays;

  if (isLastMatchday) {
    // League finished
    await supabase.from("league_sessions").update({
      status: "finished",
      finished_at: new Date().toISOString(),
    }).eq("id", sessionId);

    await supabase.from("tournaments").update({ status: "league" }).eq("id", auth.tournamentId);

    return NextResponse.json({ ok: true, finished: true });
  }

  await supabase.from("league_sessions").update({
    current_matchday: nextMatchday,
  }).eq("id", sessionId);

  return NextResponse.json({ ok: true, nextMatchday });
}
