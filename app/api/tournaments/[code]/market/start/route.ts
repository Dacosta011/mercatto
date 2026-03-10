import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";
import {
  createBulkNotifications,
} from "@/lib/notifications";

type Params = { params: Promise<{ code: string }> };

const MIN_BUDGET = 100_000_000;
const MAX_BUDGET = 400_000_000;
const ROUND_TO = 5_000_000;

async function recalcAllBudgets(
  supabase: ReturnType<typeof createServerClient>,
  assignments: { member_id: string; team_id: string }[]
) {
  const teamValues: { memberId: string; squadValue: number }[] = [];

  for (const a of assignments) {
    const { data: rows } = await supabase
      .from("team_players")
      .select("players(price)")
      .eq("team_id", a.team_id);

    const total = (rows ?? []).reduce((sum: number, r: any) => {
      const p = r.players;
      const price = Array.isArray(p) ? p[0]?.price : p?.price;
      return sum + (typeof price === "number" ? price : 0);
    }, 0);

    teamValues.push({ memberId: a.member_id, squadValue: total });
  }

  const values = teamValues.map((t) => t.squadValue);
  const minVal = Math.min(...values);
  const maxVal = Math.max(...values);

  for (const tv of teamValues) {
    let budget: number;
    if (maxVal === minVal) {
      budget = Math.round((MIN_BUDGET + MAX_BUDGET) / 2);
    } else {
      const ratio = (tv.squadValue - minVal) / (maxVal - minVal);
      budget = MAX_BUDGET - ratio * (MAX_BUDGET - MIN_BUDGET);
    }
    budget = Math.round(budget / ROUND_TO) * ROUND_TO;
    budget = Math.max(MIN_BUDGET, Math.min(MAX_BUDGET, budget));

    await supabase.from("members").update({ budget }).eq("id", tv.memberId);
  }
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
    const mapped = (assignments ?? []).map((a: any) => ({
      member_id: a.member_id as string,
      team_id: a.team_id as string,
    }));
    await recalcAllBudgets(supabase, mapped);
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
