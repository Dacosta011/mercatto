import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { salaryPerMatch } from "@/lib/expenses";

const WIN_CHANCE = 0.20;
const NEAR_WIN_CHANCE = 0.25;

// Fixed range weights — probability per OVR range stays CONSTANT
// regardless of how many players are available in each range.
// This means claiming a 84-86 player doesn't increase other 84-86 players' prob.
// Range weights — probability per OVR range stays constant.
// Intentionally hard for 80+ players:
// ~70-79: 87% combined, 80+: ~11%, icons: ~2%
const RANGE_WEIGHTS = [
  { min: 0,  max: 74,  weight: 58, isIcon: false },  // most common
  { min: 75, max: 79,  weight: 29, isIcon: false },
  { min: 80, max: 83,  weight: 7,  isIcon: false },   // harder
  { min: 84, max: 86,  weight: 2.5, isIcon: false },  // rare
  { min: 87, max: 89,  weight: 1.5, isIcon: false },  // very rare
  { min: 90, max: 999, weight: 0.5, isIcon: false },  // extremely rare
  { min: 0,  max: 999, weight: 1.5, isIcon: true  },  // legends: rare but possible
] as const;

function pickByRange(available: any[]): any {
  // Build range → available players mapping
  const rangeGroups = RANGE_WEIGHTS.map(r => ({
    ...r,
    players: available.filter(p =>
      r.isIcon
        ? (p.players?.is_icon ?? false)
        : !(p.players?.is_icon ?? false) && p.ovr >= r.min && p.ovr <= r.max
    ),
  }));

  // Weight only ranges that have available players
  const activeRanges = rangeGroups.filter(r => r.players.length > 0);
  if (activeRanges.length === 0) return available[Math.floor(Math.random() * available.length)];

  const totalWeight = activeRanges.reduce((s, r) => s + r.weight, 0);
  let rand = Math.random() * totalWeight;
  for (const r of activeRanges) {
    rand -= r.weight;
    if (rand <= 0) {
      // Pick a random player within this range
      return r.players[Math.floor(Math.random() * r.players.length)];
    }
  }
  return activeRanges[activeRanges.length - 1].players[0];
}

// Keep individual weight for backward compat (used in non-range fallback)
function getWeight(ovr: number, isIcon: boolean): number {
  if (isIcon) return 2;
  if (ovr >= 90) return 3; if (ovr >= 87) return 5;
  if (ovr >= 84) return 10; if (ovr >= 80) return 20;
  if (ovr >= 75) return 30; return 60;
}

function todayUTC() { return new Date().toISOString().slice(0, 10); }

// POST /api/tournaments/[code]/slot-machine/spin
export async function POST(req: NextRequest, { params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = createServerClient();

  const auth = await verifyMemberToken(req, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { memberId, tournamentId } = auth;
  const today = todayUTC();

  // Check pool availability BEFORE deducting budget
  // Get tournament's slot config
  const { data: tConf } = await supabase.from("tournaments").select("slot_machine_price, slots_enabled").eq("id", tournamentId).single();

  // Check if slots are enabled for this tournament
  if ((tConf as any)?.slots_enabled === false) {
    return NextResponse.json({ error: "Los slots están desactivados para este torneo." }, { status: 403 });
  }

  // Check all members have teams assigned
  const { data: allMembers } = await supabase.from("members").select("id").eq("tournament_id", tournamentId);
  const { data: allAssign } = await supabase.from("assignments").select("member_id").eq("tournament_id", tournamentId);
  const assignedSet = new Set((allAssign ?? []).map((a: any) => a.member_id as string));
  const allAssigned = (allMembers ?? []).every((m: any) => assignedSet.has(m.id));
  if (!allAssigned) {
    return NextResponse.json({ error: "Los slots solo funcionan cuando todos los participantes tienen equipo asignado." }, { status: 403 });
  }
  const spinPrice = (tConf as any)?.slot_machine_price ?? 100_000;

  const freeSpinsHeader = req.headers.get("X-Free-Spins");
  const hasFreeSpins = freeSpinsHeader && parseInt(freeSpinsHeader) > 0;

  const { data: pool } = await supabase
    .from("slot_machine_pool")
    .select("id, player_id, ovr, is_premium, players(id, name, ovr, position, headshot_url, price, clause, is_icon)")
    .eq("tournament_id", tournamentId)
    .eq("pool_date", today)
    .eq("status", "available");

  const available = (pool ?? []).filter((s: any) => s.players);

  if (available.length < 3) {
    return NextResponse.json({ error: "No hay suficientes jugadores en la pool." }, { status: 400 });
  }

  if (!hasFreeSpins) {
    // Deduct spin cost from budget (after pool check)
    const { data: memberData } = await supabase
      .from("members")
      .select("budget")
      .eq("id", memberId)
      .single();
    const currentBudget = (memberData as any)?.budget ?? 0;
    if (currentBudget < spinPrice) {
      return NextResponse.json({ error: "Presupuesto insuficiente para girar." }, { status: 402 });
    }
    await supabase
      .from("members")
      .update({ budget: currentBudget - spinPrice })
      .eq("id", memberId);
  }

  // Server-side decision
  const rand = Math.random();
  let result: { slots: any[]; isWin: boolean; isNearWin: boolean };

  if (rand < WIN_CHANCE) {
    // WIN: range-based pick — range probability stays constant even if slots are claimed
    const winSlot = pickByRange(available);
    result = { slots: [winSlot, winSlot, winSlot], isWin: true, isNearWin: false };
  } else if (rand < WIN_CHANCE + NEAR_WIN_CHANCE) {
    // NEAR WIN: first 2 same, 3rd different — both use range-based pick
    const matchSlot = pickByRange(available);
    let thirdSlot = pickByRange(available);
    let attempts = 0;
    while (thirdSlot.player_id === matchSlot.player_id && attempts++ < 50) thirdSlot = pickByRange(available);
    result = { slots: [matchSlot, matchSlot, thirdSlot], isWin: false, isNearWin: true };
  } else {
    // LOSS: all different, range-based
    const s1 = pickByRange(available);
    let s2 = pickByRange(available); let s3 = pickByRange(available); let t = 0;
    while ((s2.player_id === s1.player_id ||
            s3.player_id === s1.player_id ||
            s3.player_id === s2.player_id) && t++ < 50) {
      s2 = pickByRange(available); s3 = pickByRange(available);
    }
    result = { slots: [s1, s2, s3], isWin: false, isNearWin: false };
  }

  // Store spin in DB
  const winSlot = result.isWin ? result.slots[0] : null;
  const { data: spin, error: spinErr } = await supabase
    .from("slot_machine_spins")
    .insert({
      tournament_id: tournamentId,
      member_id: memberId,
      pool_slot_id: winSlot?.id ?? null,
      reel1_player_id: result.slots[0].player_id,
      reel2_player_id: result.slots[1].player_id,
      reel3_player_id: result.slots[2].player_id,
      is_win: result.isWin,
      win_player_id: winSlot?.player_id ?? null,
      status: "pending",
      expires_at: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
    })
    .select("id")
    .single();

  if (spinErr || !spin) return NextResponse.json({ error: "Error al registrar el giro." }, { status: 500 });

  // Get totalMatchdays for salary calculation
  let totalMatchdays = 0;
  const { data: leagueSession } = await supabase
    .from("league_sessions")
    .select("total_matchdays")
    .eq("tournament_id", tournamentId)
    .order("created_at", { ascending: false })
    .limit(1)
    .single();
  if (leagueSession) totalMatchdays = (leagueSession as any).total_matchdays ?? 0;

  // Return result to client (client animates to these players)
  return NextResponse.json({
    spinId: spin.id,
    spinPrice,
    reels: result.slots.map((s: any) => ({
      id: s.players.id,
      name: s.players.name,
      ovr: s.players.ovr,
      position: s.players.position,
      headshotUrl: s.players.headshot_url ?? null,
      salary: salaryPerMatch(s.players.price ?? s.players.clause ?? 0, totalMatchdays),
      type: s.players.is_icon ? "icon" : "player",
    })),
    isWin: result.isWin,
    isNearWin: result.isNearWin,
    winPlayer: result.isWin ? {
      id: winSlot.players.id,
      name: winSlot.players.name,
      ovr: winSlot.players.ovr,
      position: winSlot.players.position,
      headshotUrl: winSlot.players.headshot_url ?? null,
      salary: salaryPerMatch(winSlot.players.price ?? winSlot.players.clause ?? 0, totalMatchdays),
      type: winSlot.players.is_icon ? "icon" : "player",
    } : null,
  });
}
