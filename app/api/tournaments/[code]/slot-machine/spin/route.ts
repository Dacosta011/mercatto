import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { salaryPerMatch } from "@/lib/expenses";

const WIN_CHANCE = 0.40;
const NEAR_WIN_CHANCE = 0.30;

function getWeight(ovr: number, isIcon: boolean): number {
  if (isIcon) return 2;
  if (ovr >= 90) return 3; if (ovr >= 87) return 5;
  if (ovr >= 84) return 10; if (ovr >= 80) return 20;
  if (ovr >= 75) return 30; return 60;
}

function weightedPickIdx(items: any[]): number {
  const weights = items.map(p => getWeight(p.ovr, p.is_premium && p.ovr >= 87));
  const total = weights.reduce((a, b) => a + b, 0);
  let r = Math.random() * total;
  for (let i = 0; i < items.length; i++) { r -= weights[i]; if (r <= 0) return i; }
  return items.length - 1;
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
    if (currentBudget < 1000) {
      return NextResponse.json({ error: "Presupuesto insuficiente para girar." }, { status: 402 });
    }
    await supabase
      .from("members")
      .update({ budget: currentBudget - 1000 })
      .eq("id", memberId);
  }

  // Server-side decision
  const rand = Math.random();
  let result: { slots: any[]; isWin: boolean; isNearWin: boolean };

  if (rand < WIN_CHANCE) {
    // WIN: pick one slot, use for all 3 reels
    const idx = weightedPickIdx(available);
    const winSlot = available[idx];
    result = { slots: [winSlot, winSlot, winSlot], isWin: true, isNearWin: false };
  } else if (rand < WIN_CHANCE + NEAR_WIN_CHANCE) {
    // NEAR WIN: first 2 same, 3rd different
    const idx1 = weightedPickIdx(available);
    const matchSlot = available[idx1];
    let idx3 = weightedPickIdx(available);
    let attempts = 0;
    while (available[idx3].player_id === matchSlot.player_id && attempts++ < 50) idx3 = weightedPickIdx(available);
    result = { slots: [matchSlot, matchSlot, available[idx3]], isWin: false, isNearWin: true };
  } else {
    // LOSS: all different
    const idx1 = weightedPickIdx(available);
    let idx2 = weightedPickIdx(available); let idx3 = weightedPickIdx(available); let t = 0;
    while ((available[idx2].player_id === available[idx1].player_id ||
            available[idx3].player_id === available[idx1].player_id ||
            available[idx3].player_id === available[idx2].player_id) && t++ < 50) {
      idx2 = weightedPickIdx(available); idx3 = weightedPickIdx(available);
    }
    result = { slots: [available[idx1], available[idx2], available[idx3]], isWin: false, isNearWin: false };
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
