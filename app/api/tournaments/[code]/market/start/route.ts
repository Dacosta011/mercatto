import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";
import {
  createBulkNotifications,
} from "@/lib/notifications";

type Params = { params: Promise<{ code: string }> };

const OVR_REF = 88;
const STEP = 20_000_000;
const MIN_B = 100_000_000;
const MAX_B = 400_000_000;
const ROUND_TO = 5_000_000;

async function recalcBudget(supabase: ReturnType<typeof createServerClient>, teamId: string, memberId: string) {
  const { data: rows } = await supabase
    .from("team_players")
    .select("players(ovr)")
    .eq("team_id", teamId);

  const ovrs: number[] = (rows ?? [])
    .map((r: any) => {
      const p = r.players;
      return Array.isArray(p) ? p[0]?.ovr : p?.ovr;
    })
    .filter((v: any) => typeof v === "number");

  const budget = (() => {
    if (ovrs.length === 0) return MIN_B;
    const avgOvr = ovrs.reduce((s, v) => s + v, 0) / ovrs.length;
    const raw = MIN_B + (OVR_REF - avgOvr) * STEP;
    const rounded = Math.round(raw / ROUND_TO) * ROUND_TO;
    return Math.max(MIN_B, Math.min(MAX_B, rounded));
  })();

  await supabase.from("members").update({ budget }).eq("id", memberId);
}

// ─── POST /api/tournaments/[code]/market/start ────────────────────────────────
// Admin only. Opens an async market window (default 24h).
// Body (optional): { resetBudgets: true, durationHours: 24 }

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  let body: any = {};
  try {
    body = await request.json();
  } catch {
    /* no body is fine */
  }
  const resetBudgets = body?.resetBudgets === true;
  const durationHours = body?.durationHours ?? 24;

  const supabase = createServerClient();

  const { data: existing } = await supabase
    .from("market_sessions")
    .select("id, status")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (existing && (existing as any).status === "active") {
    return NextResponse.json(
      { error: "El mercado ya está activo." },
      { status: 409 }
    );
  }

  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  const memberIds = (members ?? []).map((m: any) => m.id);
  if (memberIds.length === 0) {
    return NextResponse.json(
      { error: "No hay participantes." },
      { status: 422 }
    );
  }

  const { data: assignments } = await supabase
    .from("assignments")
    .select("member_id, team_id")
    .in("member_id", memberIds);

  if ((assignments ?? []).length < memberIds.length) {
    return NextResponse.json(
      { error: "No todos los participantes tienen equipo asignado." },
      { status: 422 }
    );
  }

  await supabase
    .from("members")
    .update({ market_purchases: 0, icon_slot_used: false, budget_reserved: 0 })
    .in("id", memberIds);

  if (resetBudgets) {
    for (const a of assignments ?? []) {
      await recalcBudget(
        supabase,
        (a as any).team_id,
        (a as any).member_id
      );
    }
  }

  const now = new Date();
  const opensAt = now.toISOString();
  const closesAt = new Date(
    now.getTime() + durationHours * 60 * 60 * 1000
  ).toISOString();

  let sessionId: string;

  if (existing) {
    sessionId = (existing as any).id;

    await supabase
      .from("icon_auctions")
      .delete()
      .eq("session_id", sessionId);
    await supabase
      .from("market_offers")
      .delete()
      .eq("session_id", sessionId);
    await supabase
      .from("market_transfers")
      .update({ turn_id: null })
      .eq("session_id", sessionId);
    await supabase
      .from("market_turns")
      .delete()
      .eq("session_id", sessionId);

    await supabase
      .from("market_sessions")
      .update({
        status: "active",
        opens_at: opensAt,
        closes_at: closesAt,
        duration_hours: durationHours,
        started_at: opensAt,
        finished_at: null,
        current_round: 1,
        total_rounds: 1,
      })
      .eq("id", sessionId);
  } else {
    const { data: session, error: sessionErr } = await supabase
      .from("market_sessions")
      .insert({
        tournament_id: auth.tournamentId,
        status: "active",
        current_round: 1,
        total_rounds: 1,
        opens_at: opensAt,
        closes_at: closesAt,
        duration_hours: durationHours,
        started_at: opensAt,
      })
      .select("id")
      .single();

    if (sessionErr || !session) {
      return NextResponse.json(
        { error: "Error al crear la sesión de mercado." },
        { status: 500 }
      );
    }
    sessionId = (session as any).id;
  }

  await supabase
    .from("tournaments")
    .update({ status: "market" })
    .eq("id", auth.tournamentId);

  await createBulkNotifications(
    supabase,
    auth.tournamentId,
    memberIds,
    "market_closing",
    "Mercado abierto",
    `El mercado está abierto por ${durationHours}h. ¡A fichar!`
  );

  return NextResponse.json(
    { ok: true, sessionId, opensAt, closesAt },
    { status: 201 }
  );
}
