import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken, verifyAdminToken } from "@/lib/supabase";

// ── Seeded RNG (same seed = same pool) ──────────────────────────────────────
function makeRng(seed: string) {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = Math.imul(31, h) + seed.charCodeAt(i) | 0;
  let s = (h >>> 0);
  return () => { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return (s >>> 0) / 0xFFFFFFFF; };
}
function seededShuffle(arr: any[], rng: () => number): any[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

const POOL_RANGES = [
  { min: 70, max: 74, count: 25, premium: false },
  { min: 75, max: 79, count: 22, premium: false },
  { min: 80, max: 83, count: 20, premium: false },
  { min: 84, max: 86, count: 16, premium: true },
  { min: 87, max: 89, count: 10, premium: true },
  { min: 90, max: 99, count: 5,  premium: true },
  { min: 87, max: 99, count: 2,  premium: true, iconsOnly: true },
] as const;

function todayUTC() { return new Date().toISOString().slice(0, 10); }

// GET /api/tournaments/[code]/slot-machine/pool
export async function GET(req: NextRequest, { params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = createServerClient();

  // Verify member
  const auth = await verifyMemberToken(req, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { tournamentId } = auth;
  const today = todayUTC();

  // Check if pool exists for today
  const { data: existingPool } = await supabase
    .from("slot_machine_pool")
    .select("id")
    .eq("tournament_id", tournamentId)
    .eq("pool_date", today)
    .limit(1);

  // Check that all members have team assignments before allowing pool generation
  const { data: allMembers } = await supabase.from("members").select("id").eq("tournament_id", tournamentId);
  const { data: allAssignments } = await supabase.from("assignments").select("member_id").eq("tournament_id", tournamentId);
  const assignedMemberIds = new Set((allAssignments ?? []).map((a: any) => a.member_id as string));
  const allAssigned = (allMembers ?? []).every((m: any) => assignedMemberIds.has(m.id));

  if (!allAssigned) {
    return NextResponse.json({
      error: "Los slots solo están disponibles cuando todos los participantes tienen equipo asignado.",
      pool: [], poolDate: today, spinPrice: 100_000, slotsEnabled: true
    });
  }

  if (!existingPool || existingPool.length === 0) {
    // Generate today's pool — all teams are assigned at this point
    await generatePool(supabase, tournamentId, today);
  }

  // Return pool with status
  const { data: pool } = await supabase
    .from("slot_machine_pool")
    .select("id, player_id, ovr, is_premium, status, claimed_by_name, claimed_at, players(id, name, ovr, price, clause, position, headshot_url, is_icon)")
    .eq("tournament_id", tournamentId)
    .eq("pool_date", today)
    .order("ovr", { ascending: false });

  // Return spin price for frontend display
  const { data: tData } = await supabase.from("tournaments").select("slot_machine_price, slots_enabled").eq("id", tournamentId).single();
  const spinPrice = (tData as any)?.slot_machine_price ?? 100_000;
  const slotsEnabled = (tData as any)?.slots_enabled !== false;  // default true

  return NextResponse.json({ pool: pool ?? [], poolDate: today, spinPrice, slotsEnabled });
}

// DELETE /api/tournaments/[code]/slot-machine/pool — admin: purge today's pool and regenerate
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = createServerClient();

  const auth = await verifyAdminToken(req, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { tournamentId } = auth;
  const today = todayUTC();

  await supabase
    .from("slot_machine_pool")
    .delete()
    .eq("tournament_id", tournamentId)
    .eq("pool_date", today);

  // Use a timestamp-based seed so forced regeneration produces a different pool
  await generatePool(supabase, tournamentId, today, `${tournamentId}-${Date.now()}`);

  const { data: pool } = await supabase
    .from("slot_machine_pool")
    .select("id, player_id, ovr, is_premium, status, claimed_by_name, claimed_at, players(id, name, ovr, price, clause, position, headshot_url, is_icon)")
    .eq("tournament_id", tournamentId)
    .eq("pool_date", today)
    .order("ovr", { ascending: false });

  return NextResponse.json({ ok: true, pool: pool ?? [], poolDate: today });
}

async function getUnassignedTeamPlayers(supabase: any, tournamentId: string) {
  // Teams assigned to a member in this tournament
  const { data: assignments, error: aErr } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("tournament_id", tournamentId);
  if (aErr) { console.error("[pool] assignments query error:", aErr.message); return []; }
  const assignedTeamIds = new Set((assignments ?? []).map((a: any) => a.team_id as string));

  // All active teams
  const { data: allTeams, error: tErr } = await supabase.from("teams").select("id").eq("active", true);
  if (tErr) { console.error("[pool] teams query error:", tErr.message); return []; }
  const unassignedTeamIds = (allTeams ?? [])
    .map((t: any) => t.id as string)
    .filter((id: string) => !assignedTeamIds.has(id));

  console.log(`[pool] assignedTeams=${assignedTeamIds.size} activeteams=${(allTeams ?? []).length} unassigned=${unassignedTeamIds.length}`);
  if (unassignedTeamIds.length === 0) return [];

  // Get player_ids from those unassigned teams (separate query, no PostgREST join)
  const { data: teamPlayerRows, error: tpErr } = await supabase
    .from("team_players")
    .select("player_id")
    .in("team_id", unassignedTeamIds)
    .limit(5000);
  if (tpErr) { console.error("[pool] team_players query error:", tpErr.message); return []; }

  const playerIds = [...new Set((teamPlayerRows ?? []).map((r: any) => r.player_id as string))];
  console.log(`[pool] unique playerIds from unassigned teams: ${playerIds.length}`);
  if (playerIds.length === 0) return [];

  // Fetch player data in chunks to avoid URL length limits
  const CHUNK = 80;
  const allPlayers: any[] = [];
  for (let i = 0; i < playerIds.length; i += CHUNK) {
    const chunk = playerIds.slice(i, i + CHUNK);
    const { data: chunk_rows, error: pErr } = await supabase
      .from("players")
      .select("id, ovr, is_icon")
      .in("id", chunk);
    if (pErr) { console.error("[pool] players chunk query error:", pErr.message); continue; }
    allPlayers.push(...(chunk_rows ?? []));
  }

  console.log(`[pool] players fetched: ${allPlayers.length}`);
  return allPlayers;
}

async function generatePool(supabase: any, tournamentId: string, date: string, seed?: string) {
  const rng = makeRng(seed ?? `${tournamentId}-${date}`);

  // Source: players from teams NOT assigned to any member in this tournament
  const eligible = await getUnassignedTeamPlayers(supabase, tournamentId);
  if (eligible.length === 0) return;

  const rows: any[] = [];

  for (const range of POOL_RANGES) {
    let candidates: any[];
    if ((range as any).iconsOnly) {
      candidates = eligible.filter((p: any) => p.is_icon);
    } else {
      candidates = eligible.filter((p: any) => !p.is_icon && p.ovr >= range.min && p.ovr <= range.max);
    }
    const shuffled = seededShuffle(candidates, rng);
    for (const p of shuffled.slice(0, range.count)) {
      rows.push({ tournament_id: tournamentId, pool_date: date, player_id: p.id, ovr: p.ovr, is_premium: range.premium, status: "available" });
    }
  }

  console.log(`[pool] generated ${rows.length} pool rows, inserting...`);
  if (rows.length > 0) {
    const { error: insertErr } = await supabase
      .from("slot_machine_pool")
      .upsert(rows, { onConflict: "tournament_id,pool_date,player_id", ignoreDuplicates: true });
    if (insertErr) console.error("[pool] insert error:", insertErr.message);
    else console.log("[pool] insert success");
  }
}
