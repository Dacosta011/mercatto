import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// POST /api/tournaments/[code]/league/finish
// Admin only. Finalizes the tournament and returns to lobby.
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("league_sessions")
    .select("id, status")
    .eq("tournament_id", auth.tournamentId)
    .single();

  if (!session || (session as any).status !== "finished") {
    return NextResponse.json({ error: "La liga aún no ha finalizado." }, { status: 400 });
  }

  const { error } = await supabase
    .from("tournaments")
    .update({ status: "lobby" })
    .eq("id", auth.tournamentId);

  if (error) {
    return NextResponse.json({ error: "Error al finalizar el torneo." }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
