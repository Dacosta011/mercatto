import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/spin ─────────────────────────────────────────
// Consulta el estado actual del miembro: equipo asignado + intentos restantes.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const supabase = createServerClient();

  // Rerolls del torneo
  const { data: tournament } = await supabase
    .from("tournaments")
    .select("rerolls_allowed")
    .eq("id", auth.tournamentId)
    .single();

  const rerollsAllowed: number = (tournament as any)?.rerolls_allowed ?? 1;

  // Estado del miembro
  const { data: member } = await supabase
    .from("members")
    .select("rerolls_used, budget")
    .eq("id", auth.memberId)
    .single();

  const rerollsUsed: number = (member as any)?.rerolls_used ?? 0;
  const rerollsRemaining = Math.max(0, rerollsAllowed - rerollsUsed);

  // Asignación actual
  const { data: existing } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("member_id", auth.memberId)
    .maybeSingle();

  if (!existing) {
    return NextResponse.json({ assigned: false, team: null, rerollsAllowed, rerollsUsed, rerollsRemaining });
  }

  const { data: teamRow } = await supabase
    .from("teams")
    .select("id, name, budget")
    .eq("id", existing.team_id)
    .single();

  const t = teamRow as any;
  return NextResponse.json({
    assigned: true,
    team: { id: t?.id, name: t?.name, squadValue: 0, budget: (member as any)?.budget ?? 0 },
    rerollsAllowed,
    rerollsUsed,
    rerollsRemaining,
  });
}

// ─── POST /api/tournaments/[code]/spin ────────────────────────────────────────
// Body: { teamId: string, reroll?: boolean }
// El cliente elige el equipo (lo que cayó en la ruleta) y lo envía aquí para validar y guardar.

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  let body: { teamId?: string; reroll?: boolean } = {};
  try { body = await request.json(); } catch { /* body vacío es válido */ }

  const isReroll = body?.reroll === true;
  const requestedTeamId = body?.teamId;

  if (!requestedTeamId) {
    return NextResponse.json({ error: "Se requiere teamId." }, { status: 400 });
  }

  const supabase = createServerClient();

  // ── Configuración del torneo ───────────────────────────────────────────────
  const { data: tournament } = await supabase
    .from("tournaments")
    .select("rerolls_allowed")
    .eq("id", auth.tournamentId)
    .single();

  const rerollsAllowed: number = (tournament as any)?.rerolls_allowed ?? 1;

  // ── Estado actual del miembro ──────────────────────────────────────────────
  const { data: memberRow } = await supabase
    .from("members")
    .select("rerolls_used, budget")
    .eq("id", auth.memberId)
    .single();

  const rerollsUsed: number = (memberRow as any)?.rerolls_used ?? 0;

  // ── Asignación existente ───────────────────────────────────────────────────
  const { data: existing } = await supabase
    .from("assignments")
    .select("id, team_id")
    .eq("member_id", auth.memberId)
    .maybeSingle();

  if (existing && !isReroll) {
    // Ya tiene equipo y no pidió reroll → devolver equipo actual
    const { data: teamRow } = await supabase
      .from("teams")
      .select("id, name, budget")
      .eq("id", existing.team_id)
      .single();

    const t = teamRow as any;
    return NextResponse.json({
      alreadyAssigned: true,
      team: { id: t?.id, name: t?.name, squadValue: 0, budget: (memberRow as any)?.budget ?? 0 },
      rerollsAllowed,
      rerollsUsed,
      rerollsRemaining: Math.max(0, rerollsAllowed - rerollsUsed),
    });
  }

  if (isReroll) {
    // Verificar que le quedan intentos
    if (rerollsUsed >= rerollsAllowed) {
      return NextResponse.json(
        { error: `No te quedan intentos de reroll. Tienes ${rerollsAllowed} en total.` },
        { status: 403 }
      );
    }
    // Liberar equipo actual
    if (existing) {
      await supabase.from("assignments").delete().eq("id", existing.id);
    }
  }

  // ── Validar que el equipo solicitado existe ───────────────────────────────
  const { data: teamRow, error: teamFetchErr } = await supabase
    .from("teams")
    .select("id, name")
    .eq("id", requestedTeamId)
    .maybeSingle();

  if (teamFetchErr || !teamRow) {
    return NextResponse.json({ error: "Equipo no encontrado." }, { status: 404 });
  }

  // ── Verificar que el equipo no está ya tomado por otro miembro ────────────
  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  const memberIds = (members ?? [])
    .map((m: any) => m.id as string)
    .filter((id) => id !== auth.memberId); // excluir al propio miembro

  let takenByOthers = false;
  if (memberIds.length > 0) {
    const { data: takenRows } = await supabase
      .from("assignments")
      .select("team_id")
      .in("member_id", memberIds)
      .eq("team_id", requestedTeamId);
    takenByOthers = (takenRows ?? []).length > 0;
  }

  if (takenByOthers) {
    return NextResponse.json(
      { error: "Ese equipo ya fue tomado por otro jugador. Intenta de nuevo." },
      { status: 409 }
    );
  }

  const team = teamRow as any;

  const { error: assignErr } = await supabase
    .from("assignments")
    .upsert(
      { tournament_id: auth.tournamentId, member_id: auth.memberId, team_id: team.id },
      { onConflict: "tournament_id,member_id", ignoreDuplicates: false }
    );

  if (assignErr) {
    console.error("[spin] insert", assignErr);
    return NextResponse.json({ error: "Error al guardar la asignación." }, { status: 500 });
  }

  // ── Incrementar rerolls_used si fue un reroll ──────────────────────────────
  const newRerollsUsed = isReroll ? rerollsUsed + 1 : rerollsUsed;
  if (isReroll) {
    await supabase
      .from("members")
      .update({ rerolls_used: newRerollsUsed })
      .eq("id", auth.memberId);
  }

  // ── Calcular y guardar presupuesto en el member ────────────────────────────
  const budget = await calcAndSaveBudget(supabase, team.id, auth.memberId);

  return NextResponse.json({
    alreadyAssigned: false,
    team: { id: team.id, name: team.name, squadValue: 0, budget },
    rerollsAllowed,
    rerollsUsed: newRerollsUsed,
    rerollsRemaining: Math.max(0, rerollsAllowed - newRerollsUsed),
  });
}

// ─── Calcular presupuesto inversamente proporcional al OVR medio ──────────────
// El presupuesto se guarda en members.budget (pertenece al participante).

async function calcAndSaveBudget(supabase: any, teamId: string, memberId: string): Promise<number> {
  const OVR_REF  = 88;
  const STEP     = 20_000_000;
  const MIN_B    = 100_000_000;
  const MAX_B    = 400_000_000;
  const ROUND_TO = 5_000_000;

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
    const avgOvr  = ovrs.reduce((s, v) => s + v, 0) / ovrs.length;
    const raw     = MIN_B + (OVR_REF - avgOvr) * STEP;
    const rounded = Math.round(raw / ROUND_TO) * ROUND_TO;
    return Math.max(MIN_B, Math.min(MAX_B, rounded));
  })();

  // Guardar en el participante, no en el equipo
  await supabase.from("members").update({ budget }).eq("id", memberId);
  return budget;
}
