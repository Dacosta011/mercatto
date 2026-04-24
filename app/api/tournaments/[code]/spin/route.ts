import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/spin ─────────────────────────────────────────
// Returns current assignment + reroll config. Used by the frontend to decide
// how many local spins are still allowed.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const [{ data: tournament }, { data: member }, { data: existing }] = await Promise.all([
    supabase.from("tournaments").select("rerolls_allowed").eq("id", auth.tournamentId).single(),
    supabase.from("members").select("rerolls_used, budget").eq("id", auth.memberId).single(),
    supabase.from("assignments").select("team_id").eq("member_id", auth.memberId).maybeSingle(),
  ]);

  const rerollsAllowed: number  = (tournament as any)?.rerolls_allowed ?? 1;
  const rerollsUsed:    number  = (member as any)?.rerolls_used        ?? 0;
  const rerollsRemaining        = Math.max(0, rerollsAllowed - rerollsUsed);

  if (!existing) {
    return NextResponse.json({ assigned: false, team: null, rerollsAllowed, rerollsUsed, rerollsRemaining });
  }

  const { data: teamRow } = await supabase
    .from("teams").select("id, name, crest_url").eq("id", existing.team_id).single();

  const t = teamRow as any;
  return NextResponse.json({
    assigned: true,
    team: { id: t?.id, name: t?.name, crestUrl: t?.crest_url ?? null, squadValue: 0, budget: (member as any)?.budget ?? 0 },
    rerollsAllowed,
    rerollsUsed,
    rerollsRemaining,
  });
}

// ─── POST /api/tournaments/[code]/spin ────────────────────────────────────────
// Called ONCE when the user confirms their chosen team (after all local spins).
// Body: { teamId: string, rerollsUsed: number }
//   rerollsUsed = total rerolls consumed (0 = only the initial spin, no rerolls).

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  let body: { teamId?: string; rerollsUsed?: number } = {};
  try { body = await request.json(); } catch { /* empty body */ }

  const requestedTeamId = body?.teamId;
  const rerollsUsed     = Math.max(0, body?.rerollsUsed ?? 0);

  if (!requestedTeamId) {
    return NextResponse.json({ error: "Se requiere teamId." }, { status: 400 });
  }

  const supabase = createServerClient();

  const { data: tournament } = await supabase
    .from("tournaments").select("rerolls_allowed").eq("id", auth.tournamentId).single();

  const rerollsAllowed: number = (tournament as any)?.rerolls_allowed ?? 1;

  if (rerollsUsed > rerollsAllowed) {
    return NextResponse.json({ error: "Se excedió el límite de rerolls permitidos." }, { status: 403 });
  }

  // Validate team exists
  const { data: teamRow } = await supabase
    .from("teams").select("id, name, crest_url").eq("id", requestedTeamId).maybeSingle();

  if (!teamRow) {
    return NextResponse.json({ error: "Equipo no encontrado." }, { status: 404 });
  }

  // Ensure no OTHER member in this tournament has the team
  const { data: members } = await supabase
    .from("members").select("id").eq("tournament_id", auth.tournamentId);

  const otherIds = (members ?? [])
    .map((m: any) => m.id as string)
    .filter((id) => id !== auth.memberId);

  if (otherIds.length > 0) {
    const { data: taken } = await supabase
      .from("assignments").select("team_id").in("member_id", otherIds).eq("team_id", requestedTeamId);
    if ((taken ?? []).length > 0) {
      return NextResponse.json(
        { error: "Ese equipo ya fue tomado por otro jugador. Intenta de nuevo." },
        { status: 409 },
      );
    }
  }

  const team = teamRow as any;

  // Upsert assignment (also handles re-assignments from rerolls)
  const { error: assignErr } = await supabase
    .from("assignments")
    .upsert(
      { tournament_id: auth.tournamentId, member_id: auth.memberId, team_id: team.id },
      { onConflict: "tournament_id,member_id", ignoreDuplicates: false },
    );

  if (assignErr) {
    console.error("[spin] assign", assignErr);
    return NextResponse.json({ error: "Error al guardar la asignación." }, { status: 500 });
  }

  await supabase.from("members").update({ rerolls_used: rerollsUsed }).eq("id", auth.memberId);

  // Budget is owned by the TEAM, not the member. If the team has a saved
  // budget for this tournament (snapshotted from the previous season's owner),
  // the member inherits that balance. Otherwise (season 1, or a team that
  // nobody had last season) it is calculated from the squad's average OVR.
  const { data: teamBudgetRow } = await supabase
    .from("team_budgets")
    .select("budget")
    .eq("tournament_id", auth.tournamentId)
    .eq("team_id", team.id)
    .maybeSingle();

  let budget: number;
  if (teamBudgetRow != null) {
    budget = Number((teamBudgetRow as any).budget);
    await supabase.from("members").update({ budget }).eq("id", auth.memberId);
  } else {
    budget = await calcAndSaveBudget(supabase, team.id, auth.memberId);
  }

  return NextResponse.json({
    team: { id: team.id, name: team.name, crestUrl: team.crest_url ?? null, squadValue: 0, budget },
    rerollsAllowed,
    rerollsUsed,
    rerollsRemaining: Math.max(0, rerollsAllowed - rerollsUsed),
  });
}

// ─── Budget calculation ───────────────────────────────────────────────────────

async function calcAndSaveBudget(supabase: any, teamId: string, memberId: string): Promise<number> {
  const OVR_REF  = 88;
  const STEP     = 20_000_000;
  const MIN_B    = 100_000_000;
  const MAX_B    = 400_000_000;
  const ROUND_TO = 5_000_000;

  const { data: rows } = await supabase
    .from("team_players").select("players(ovr)").eq("team_id", teamId);

  const ovrs: number[] = (rows ?? [])
    .map((r: any) => { const p = r.players; return Array.isArray(p) ? p[0]?.ovr : p?.ovr; })
    .filter((v: any) => typeof v === "number");

  const budget = (() => {
    if (ovrs.length === 0) return MIN_B;
    const avgOvr  = ovrs.reduce((s: number, v: number) => s + v, 0) / ovrs.length;
    const raw     = MIN_B + (OVR_REF - avgOvr) * STEP;
    const rounded = Math.round(raw / ROUND_TO) * ROUND_TO;
    return Math.max(MIN_B, Math.min(MAX_B, rounded));
  })();

  await supabase.from("members").update({ budget }).eq("id", memberId);
  return budget;
}
