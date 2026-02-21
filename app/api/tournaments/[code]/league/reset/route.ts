import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// POST /api/tournaments/[code]/league/reset
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Delete league session (cascades to fixtures, discipline, suspensions, matchday_rests)
  await supabase
    .from("league_sessions")
    .delete()
    .eq("tournament_id", auth.tournamentId);

  // Reset tournament status to lobby
  await supabase
    .from("tournaments")
    .update({ status: "lobby" })
    .eq("id", auth.tournamentId);

  return NextResponse.json({ ok: true });
}
