import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ─── POST /api/tournaments/[code]/market/next-round ───────────────────────────
// Admin starts the next round after all turns are complete.

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions")
    .select("*")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json({ error: "El mercado no está activo." }, { status: 409 });
  }

  const newRound = (session as any).current_round + 1;
  if (newRound > (session as any).total_rounds) {
    return NextResponse.json({ error: "Ya se jugaron todas las rondas." }, { status: 422 });
  }

  // Get all members of the tournament
  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  const memberIds = (members ?? []).map((m: any) => m.id);
  const shuffled = shuffle(memberIds);

  const turnRows = shuffled.map((memberId, idx) => ({
    session_id: (session as any).id,
    round_num: newRound,
    position: idx + 1,
    member_id: memberId,
    status: idx === 0 ? "active" : "pending",
  }));

  const { error: turnsErr } = await supabase.from("market_turns").insert(turnRows);
  if (turnsErr) return NextResponse.json({ error: "Error al generar turnos." }, { status: 500 });

  await supabase
    .from("market_sessions")
    .update({ current_round: newRound })
    .eq("id", (session as any).id);

  return NextResponse.json({ ok: true, round: newRound });
}
