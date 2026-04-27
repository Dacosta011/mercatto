import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

function todayUTC() { return new Date().toISOString().slice(0, 10); }

// POST /api/tournaments/[code]/slot-machine/accept
export async function POST(req: NextRequest, { params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = createServerClient();

  const auth = await verifyMemberToken(req, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { memberId, tournamentId } = auth;
  const { spinId } = await req.json();

  if (!spinId) return NextResponse.json({ error: "spinId requerido." }, { status: 400 });

  // Get the spin
  const { data: spin } = await supabase
    .from("slot_machine_spins")
    .select("id, pool_slot_id, win_player_id, is_win, status, expires_at, members(display_name)")
    .eq("id", spinId)
    .eq("member_id", memberId)
    .single();

  if (!spin) return NextResponse.json({ error: "Giro no encontrado." }, { status: 404 });
  if (spin.status !== "pending") return NextResponse.json({ error: "Este giro ya fue procesado." }, { status: 409 });
  if (!spin.is_win) return NextResponse.json({ error: "No hay premio que aceptar." }, { status: 400 });
  if (new Date(spin.expires_at) < new Date()) return NextResponse.json({ error: "El tiempo para aceptar expiró." }, { status: 410 });

  const memberName = (spin.members as any)?.display_name ?? "Alguien";
  const today = todayUTC();

  // ── Daily limits check ─────────────────────────────────────────────────────
  // Get the winning player's OVR to determine which limit applies
  const { data: winningPlayer } = await supabase
    .from("players")
    .select("ovr")
    .eq("id", spin.win_player_id)
    .single();
  const winOvr = (winningPlayer as any)?.ovr ?? 0;
  const isPremium = winOvr > 80;

  // Count today's claims by this member
  const { data: todayClaims } = await supabase
    .from("slot_machine_pool")
    .select("ovr, player_id")
    .eq("claimed_by_member_id", memberId)
    .gte("claimed_at", today + "T00:00:00Z");

  const premiumClaimed = (todayClaims ?? []).filter((c: any) => c.ovr > 80).length;
  const regularClaimed = (todayClaims ?? []).filter((c: any) => c.ovr <= 80).length;

  const MAX_PREMIUM_PER_DAY = 3;
  const MAX_REGULAR_PER_DAY = 2;

  if (isPremium && premiumClaimed >= MAX_PREMIUM_PER_DAY) {
    return NextResponse.json({
      error: `Límite alcanzado: máximo ${MAX_PREMIUM_PER_DAY} jugadores de más de 80 OVR por día.`
    }, { status: 429 });
  }
  if (!isPremium && regularClaimed >= MAX_REGULAR_PER_DAY) {
    return NextResponse.json({
      error: `Límite alcanzado: máximo ${MAX_REGULAR_PER_DAY} jugadores de menos de 80 OVR por día.`
    }, { status: 429 });
  }

  // Get the pool slot (include status to check for race conditions)
  const { data: slot } = await supabase
    .from("slot_machine_pool")
    .select("id, ovr, is_premium, status")
    .eq("id", spin.pool_slot_id)
    .single();

  // If no pool slot (non-pool win), skip pool update
  if (slot) {
    if ((slot as any).status === "claimed") return NextResponse.json({ error: "Ese jugador ya fue reclamado por otro." }, { status: 409 });
  }

  // Mark slot as claimed (if applicable)
  if (slot) await supabase.from("slot_machine_pool").update({
    status: "claimed",
    claimed_by_member_id: memberId,
    claimed_by_name: memberName,
    claimed_at: new Date().toISOString(),
  }).eq("id", slot.id);

  // Mark spin as accepted
  await supabase.from("slot_machine_spins").update({ status: "accepted" }).eq("id", spinId);

  // Always add a replacement to maintain pool at 100 (for all player types)
  if (slot) {
    await addReplacement(supabase, tournamentId, today, (slot as any).ovr);
  }

  // Add player to member's team (via team_players if they have an assigned team)
  const { data: assignment } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("tournament_id", tournamentId)
    .eq("member_id", memberId)
    .single();

  if (assignment) {
    // Add player to team using upsert to handle duplicates
    const { error: insertErr } = await supabase
      .from("team_players")
      .upsert(
        { team_id: assignment.team_id, player_id: spin.win_player_id },
        { onConflict: "team_id,player_id", ignoreDuplicates: true }
      );
    if (insertErr) console.warn("[accept] team_players insert:", insertErr.message);
  }

  return NextResponse.json({ ok: true });
}

async function addReplacement(supabase: any, tournamentId: string, date: string, targetOvr: number) {
  // Get players already in today's pool (to avoid duplicates)
  const { data: poolPlayers } = await supabase
    .from("slot_machine_pool")
    .select("player_id")
    .eq("tournament_id", tournamentId)
    .eq("pool_date", date);
  const inPool = new Set((poolPlayers ?? []).map((p: any) => p.player_id));

  // Get players already assigned to tournament teams (must exclude these)
  const { data: assignments } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("tournament_id", tournamentId);
  const assignedTeamIds = (assignments ?? []).map((a: any) => a.team_id);
  const { data: teamPlayers } = await supabase
    .from("team_players")
    .select("player_id")
    .in("team_id", assignedTeamIds.length ? assignedTeamIds : ["none"]);
  const inTeamIds = new Set((teamPlayers ?? []).map((tp: any) => tp.player_id));

  const getRangeFor = (ovr: number) => {
    if (ovr <= 74) return { min: 70, max: 74, premium: false };
    if (ovr <= 79) return { min: 75, max: 79, premium: false };
    if (ovr <= 83) return { min: 80, max: 83, premium: false };
    if (ovr <= 86) return { min: 84, max: 86, premium: true };
    if (ovr <= 89) return { min: 87, max: 89, premium: true };
    return { min: 90, max: 99, premium: true };
  };

  const excludeIds = [...new Set([...inPool, ...inTeamIds])];
  const excludeClause = excludeIds.length ? `(${excludeIds.join(",")})` : "(00000000-0000-0000-0000-000000000000)";

  const range = getRangeFor(targetOvr);

  // Try same OVR range first
  const { data: candidates } = await supabase
    .from("players")
    .select("id, ovr")
    .eq("is_icon", false)
    .gte("ovr", range.min)
    .lte("ovr", range.max)
    .not("id", "in", excludeClause);

  if (candidates && candidates.length > 0) {
    const pick = candidates[Math.floor(Math.random() * candidates.length)];
    await supabase.from("slot_machine_pool").insert({
      tournament_id: tournamentId, pool_date: date,
      player_id: pick.id, ovr: pick.ovr, is_premium: range.premium, status: "available",
    });
    return;
  }

  // Fallback: any available player not in pool or assigned teams (OVR 70+)
  const { data: fallback } = await supabase
    .from("players")
    .select("id, ovr")
    .eq("is_icon", false)
    .gte("ovr", 70)
    .not("id", "in", excludeClause)
    .limit(50);

  if (fallback && fallback.length > 0) {
    const pick = fallback[Math.floor(Math.random() * fallback.length)];
    await supabase.from("slot_machine_pool").insert({
      tournament_id: tournamentId, pool_date: date,
      player_id: pick.id, ovr: pick.ovr, is_premium: pick.ovr > 83, status: "available",
    });
  }
}
