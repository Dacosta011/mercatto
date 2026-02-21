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

// ─── POST /api/tournaments/[code]/market/start ────────────────────────────────
// Admin only. Creates market session + round 1 turn order.

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Check market doesn't already exist
  const { data: existing } = await supabase
    .from("market_sessions")
    .select("id")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (existing) {
    return NextResponse.json({ error: "El mercado ya fue iniciado." }, { status: 409 });
  }

  // Verify all members have teams
  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  const memberIds = (members ?? []).map((m: any) => m.id);
  if (memberIds.length === 0) {
    return NextResponse.json({ error: "No hay participantes." }, { status: 422 });
  }

  const { data: assignments } = await supabase
    .from("assignments")
    .select("member_id")
    .in("member_id", memberIds);

  if ((assignments ?? []).length < memberIds.length) {
    return NextResponse.json(
      { error: "No todos los participantes tienen equipo asignado." },
      { status: 422 }
    );
  }

  // Create session
  const { data: session, error: sessionErr } = await supabase
    .from("market_sessions")
    .insert({
      tournament_id: auth.tournamentId,
      status: "active",
      current_round: 1,
      total_rounds: 3,
      started_at: new Date().toISOString(),
    })
    .select("id")
    .single();

  if (sessionErr || !session) {
    return NextResponse.json({ error: "Error al crear la sesión de mercado." }, { status: 500 });
  }

  // Generate round 1 random turn order
  const shuffled = shuffle(memberIds);
  const turnRows = shuffled.map((memberId, idx) => ({
    session_id: (session as any).id,
    round_num: 1,
    position: idx + 1,
    member_id: memberId,
    status: idx === 0 ? "active" : "pending",
  }));

  const { error: turnsErr } = await supabase.from("market_turns").insert(turnRows);
  if (turnsErr) {
    return NextResponse.json({ error: "Error al generar el orden de turnos." }, { status: 500 });
  }

  // Update tournament status
  await supabase
    .from("tournaments")
    .update({ status: "market" })
    .eq("id", auth.tournamentId);

  return NextResponse.json({ ok: true, sessionId: (session as any).id }, { status: 201 });
}
