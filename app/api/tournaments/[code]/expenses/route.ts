import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import {
  getMemberSquad,
  salaryPerMatch,
  salaryPerSeason,
  YELLOW_CARD_FINE,
  RED_CARD_FINE,
} from "@/lib/expenses";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/expenses ─────────────────────────────────────
// Returns:
//   - summary: salary commitments (per match / per season) for the current squad
//   - totals : sum of paid expenses by type, season-to-date
//   - ledger : last N expense rows, ordered desc, joined with player names
//   - budget : current balance (and reserved) for context

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const [{ data: member }, { data: leagueSession }] = await Promise.all([
    supabase
      .from("members")
      .select("budget, budget_reserved")
      .eq("id", auth.memberId)
      .single(),
    supabase
      .from("league_sessions")
      .select("total_matchdays, current_matchday, status")
      .eq("tournament_id", auth.tournamentId)
      .maybeSingle(),
  ]);

  const totalMatchdays: number = ((leagueSession as any)?.total_matchdays ?? 0) as number;

  // Squad with salaries
  const squad = await getMemberSquad(supabase, auth.tournamentId, auth.memberId);
  const squadWithSalaries = squad
    .map((p) => ({
      playerId: p.playerId,
      playerName: p.name,
      price: p.price,
      ovr: p.ovr,
      position: p.position,
      headshotUrl: p.headshotUrl,
      salaryPerMatch: salaryPerMatch(p.price, totalMatchdays),
      salaryPerSeason: salaryPerSeason(p.price),
    }))
    .sort((a, b) => b.salaryPerSeason - a.salaryPerSeason);

  const totalSalaryPerMatch = squadWithSalaries.reduce((s, p) => s + p.salaryPerMatch, 0);
  const totalSalaryPerSeason = squadWithSalaries.reduce((s, p) => s + p.salaryPerSeason, 0);

  // Ledger (latest 100 rows for this member)
  const { data: ledgerRaw } = await supabase
    .from("club_expenses")
    .select("id, fixture_id, matchday, expense_type, player_id, player_name, amount, is_credit, created_at")
    .eq("member_id", auth.memberId)
    .order("created_at", { ascending: false })
    .limit(100);

  const ledger = (ledgerRaw ?? []).map((r: any) => ({
    id: r.id,
    fixtureId: r.fixture_id,
    matchday: r.matchday,
    expenseType: r.expense_type,
    playerId: r.player_id,
    playerName: r.player_name,
    amount: r.amount,
    isCredit: r.is_credit,
    createdAt: r.created_at,
  }));

  // Aggregate totals by type (season-to-date for this member)
  const { data: aggregateRaw } = await supabase
    .from("club_expenses")
    .select("expense_type, amount, is_credit")
    .eq("member_id", auth.memberId)
    .eq("tournament_id", auth.tournamentId);

  const totals = {
    salaryPaid: 0,
    yellowFines: 0,
    redFines: 0,
    autoReleaseRecovered: 0,
    netSpent: 0,
  };
  for (const r of aggregateRaw ?? []) {
    const amount = (r as any).amount as number;
    const isCredit = (r as any).is_credit as boolean;
    const type = (r as any).expense_type as string;
    if (type === "salary") totals.salaryPaid += amount;
    else if (type === "yellow_card") totals.yellowFines += amount;
    else if (type === "red_card") totals.redFines += amount;
    else if (type === "auto_release") totals.autoReleaseRecovered += amount;
    totals.netSpent += isCredit ? -amount : amount;
  }

  return NextResponse.json({
    budget: ((member as any)?.budget ?? 0) as number,
    budgetReserved: ((member as any)?.budget_reserved ?? 0) as number,
    league: {
      totalMatchdays,
      currentMatchday: ((leagueSession as any)?.current_matchday ?? 0) as number,
      status: ((leagueSession as any)?.status ?? null) as string | null,
    },
    salaries: {
      perMatchTotal: totalSalaryPerMatch,
      perSeasonTotal: totalSalaryPerSeason,
      players: squadWithSalaries,
    },
    fines: {
      yellowFee: YELLOW_CARD_FINE,
      redFee: RED_CARD_FINE,
    },
    totals,
    ledger,
  });
}
