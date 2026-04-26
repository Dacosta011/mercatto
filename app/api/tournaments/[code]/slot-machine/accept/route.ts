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

  // Get the pool slot
  const { data: slot } = await supabase
    .from("slot_machine_pool")
    .select("id, ovr, is_premium")
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

  // If OVR <= 80 (non-premium): add a replacement from unselected players
  if (slot && !(slot as any).is_premium) {
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
  // Find the OVR range bucket
  const minOvr = targetOvr <= 74 ? 70 : targetOvr <= 79 ? 75 : 80;
  const maxOvr = targetOvr <= 74 ? 74 : targetOvr <= 79 ? 79 : 83;

  // Get players already in today's pool
  const { data: poolPlayers } = await supabase
    .from("slot_machine_pool")
    .select("player_id")
    .eq("tournament_id", tournamentId)
    .eq("pool_date", date);
  const inPool = new Set((poolPlayers ?? []).map((p: any) => p.player_id));

  // Find a replacement not already in pool
  const { data: candidates } = await supabase
    .from("players")
    .select("id, ovr")
    .eq("is_icon", false)
    .gte("ovr", minOvr)
    .lte("ovr", maxOvr)
    .not("id", "in", `(${[...inPool].join(",")})`);

  if (candidates && candidates.length > 0) {
    const pick = candidates[Math.floor(Math.random() * candidates.length)];
    await supabase.from("slot_machine_pool").insert({
      tournament_id: tournamentId,
      pool_date: date,
      player_id: pick.id,
      ovr: pick.ovr,
      is_premium: false,
      status: "available",
    });
  }
}
