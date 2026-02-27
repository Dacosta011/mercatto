import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";
import { advanceTurn } from "../action/route";

type Params = { params: Promise<{ code: string }> };

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

const OVR_REF  = 88;
const STEP     = 20_000_000;
const MIN_B    = 100_000_000;
const MAX_B    = 400_000_000;
const ROUND_TO = 5_000_000;

async function recalcBudget(supabase: any, teamId: string, memberId: string) {
  const { data: rows } = await supabase
    .from("team_players").select("players(ovr)").eq("team_id", teamId);

  const ovrs: number[] = (rows ?? [])
    .map((r: any) => { const p = r.players; return Array.isArray(p) ? p[0]?.ovr : p?.ovr; })
    .filter((v: any) => typeof v === "number");

  const budget = (() => {
    if (ovrs.length === 0) return MIN_B;
    const avgOvr  = ovrs.reduce((s, v) => s + v, 0) / ovrs.length;
    const raw     = MIN_B + (OVR_REF - avgOvr) * STEP;
    const rounded = Math.round(raw / ROUND_TO) * ROUND_TO;
    return Math.max(MIN_B, Math.min(MAX_B, rounded));
  })();

  await supabase.from("members").update({ budget }).eq("id", memberId);
}

// ─── POST /api/tournaments/[code]/market/start ────────────────────────────────
// Admin only. Creates or restarts market session + round 1 turn order.
// If a finished session exists, it is restarted (transfers preserved as history).
// Body (optional): { resetBudgets: true } to recalculate budgets from scratch.

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  let body: any = {};
  try { body = await request.json(); } catch { /* no body is fine */ }
  const resetBudgets = body?.resetBudgets === true;

  const supabase = createServerClient();

  // Check for existing session
  const { data: existing } = await supabase
    .from("market_sessions")
    .select("id, status")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  // If active, check if it has actual pending turns (truly running vs. failed previous start)
  if (existing && (existing as any).status === "active") {
    const { count } = await supabase
      .from("market_turns")
      .select("id", { count: "exact", head: true })
      .eq("session_id", (existing as any).id);
    if ((count ?? 0) > 0) {
      return NextResponse.json({ error: "El mercado ya está activo." }, { status: 409 });
    }
    // No turns = failed previous start → allow re-init
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
    .select("member_id, team_id")
    .in("member_id", memberIds);

  if ((assignments ?? []).length < memberIds.length) {
    return NextResponse.json(
      { error: "No todos los participantes tienen equipo asignado." },
      { status: 422 }
    );
  }

  // Reset market_purchases for all members
  await supabase
    .from("members")
    .update({ market_purchases: 0 })
    .in("id", memberIds);

  // Optionally recalculate budgets from scratch
  if (resetBudgets) {
    for (const a of assignments ?? []) {
      await recalcBudget(supabase, (a as any).team_id, (a as any).member_id);
    }
  }

  let sessionId: string;
  const now = new Date().toISOString();

  if (existing) {
    // ── Restart the existing session ──────────────────────────────────────
    // Transfers are kept as ownership history. Turns and offers are cleared.
    sessionId = (existing as any).id;

    // Clean up old data first (before changing status)
    // icon_auctions cascade deletes icon_activation_votes, icon_selection_votes, icon_bids
    await supabase.from("icon_auctions").delete().eq("session_id", sessionId);
    await supabase.from("market_offers").delete().eq("session_id", sessionId);
    // Nullify turn_id FK in transfers (kept as ownership history) so turns can be deleted
    await supabase.from("market_transfers").update({ turn_id: null }).eq("session_id", sessionId);
    await supabase.from("market_turns").delete().eq("session_id", sessionId);
  } else {
    // ── Create brand-new session (initially "pending" until fully set up) ─
    const { data: session, error: sessionErr } = await supabase
      .from("market_sessions")
      .insert({
        tournament_id: auth.tournamentId,
        status: "pending",
        current_round: 1,
        total_rounds: 3,
        started_at: now,
      })
      .select("id")
      .single();

    if (sessionErr || !session) {
      return NextResponse.json({ error: "Error al crear la sesión de mercado." }, { status: 500 });
    }
    sessionId = (session as any).id;
  }

  // Generate round 1 random turn order
  const shuffled = shuffle(memberIds);
  const turnRows = shuffled.map((memberId, idx) => ({
    session_id: sessionId,
    round_num: 1,
    position: idx + 1,
    member_id: memberId,
    status: "pending",
  }));

  const { error: turnsErr } = await supabase.from("market_turns").insert(turnRows);
  if (turnsErr) {
    return NextResponse.json({ error: "Error al generar el orden de turnos." }, { status: 500 });
  }

  // Everything succeeded — now activate the session
  await supabase
    .from("market_sessions")
    .update({
      status: "active",
      current_round: 1,
      total_rounds: 3,
      started_at: now,
      finished_at: null,
    })
    .eq("id", sessionId);

  // Update tournament status
  await supabase
    .from("tournaments")
    .update({ status: "market" })
    .eq("id", auth.tournamentId);

  // Activate the first eligible turn
  await advanceTurn(supabase, { id: sessionId, current_round: 1 });

  return NextResponse.json({ ok: true, sessionId }, { status: 201 });
}
