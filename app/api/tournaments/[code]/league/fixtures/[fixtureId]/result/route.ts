import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import {
  getMemberSquad,
  recordExpenses,
  runAutoRelease,
  salaryPerMatch,
  YELLOW_CARD_FINE,
  RED_CARD_FINE,
  type ExpenseRow,
  type AutoReleaseEvent,
} from "@/lib/expenses";
import { createNotification } from "@/lib/notifications";

type Params = { params: Promise<{ code: string; fixtureId: string }> };

interface PlayerCard { playerId: string; playerName: string; cardType: "yellow" | "red"; memberId: string }

// Helper: process player-level discipline after match finalization
function sanitizeCards(cards: PlayerCard[]): PlayerCard[] {
  const seen: Record<string, { yellows: number; hasRed: boolean }> = {};
  const result: PlayerCard[] = [];
  for (const c of cards) {
    if (!seen[c.playerId]) seen[c.playerId] = { yellows: 0, hasRed: false };
    const s = seen[c.playerId];
    if (s.hasRed) continue;
    if (c.cardType === "red") { s.hasRed = true; result.push(c); continue; }
    s.yellows++;
    if (s.yellows >= 2) {
      // Double yellow → convert to a single red, remove previous yellow
      const filtered = result.filter(r => !(r.playerId === c.playerId && r.cardType === "yellow"));
      result.length = 0;
      result.push(...filtered, { ...c, cardType: "red" });
      s.hasRed = true;
    } else {
      result.push(c);
    }
  }
  return result;
}

async function processDiscipline(
  supabase: any,
  sessionId: string,
  fixture: any,
  currentMatchday: number,
  playerCards: PlayerCard[]
) {
  const sanitized = sanitizeCards(playerCards);
  if (sanitized.length === 0) return;

  const rows = sanitized.map((c) => ({
    session_id: sessionId,
    member_id: c.memberId,
    player_id: c.playerId,
    player_name: c.playerName,
    fixture_id: fixture.id,
    card_type: c.cardType,
    matchday: currentMatchday,
  }));
  await supabase.from("discipline").insert(rows);

  // Check suspensions per player
  const playerIds = [...new Set(sanitized.map((c) => c.playerId))];

  for (const playerId of playerIds) {
    const card = sanitized.find((c) => c.playerId === playerId)!;
    const memberId = card.memberId;

    const { data: allCards } = await supabase
      .from("discipline")
      .select("card_type")
      .eq("session_id", sessionId)
      .eq("player_id", playerId);

    const yellows = (allCards ?? []).filter((c: any) => c.card_type === "yellow").length;
    const reds    = (allCards ?? []).filter((c: any) => c.card_type === "red").length;

    const { data: existingSuspensions } = await supabase
      .from("suspensions")
      .select("reason")
      .eq("session_id", sessionId)
      .eq("player_id", playerId);

    const prevYellow = (existingSuspensions ?? []).filter((s: any) => s.reason === "yellow_accumulation").length;
    const prevRed    = (existingSuspensions ?? []).filter((s: any) => s.reason === "red_card").length;

    // Every 3 yellows → 1-match suspension
    if (Math.floor(yellows / 3) > prevYellow) {
      await supabase.from("suspensions").insert({
        session_id: sessionId,
        member_id: memberId,
        player_id: playerId,
        player_name: card.playerName,
        reason: "yellow_accumulation",
        from_matchday: currentMatchday + 1,
        matches_remaining: 1,
      });
    }

    // Each red → 2-match suspension
    if (reds > prevRed) {
      await supabase.from("suspensions").insert({
        session_id: sessionId,
        member_id: memberId,
        player_id: playerId,
        player_name: card.playerName,
        reason: "red_card",
        from_matchday: currentMatchday + 1,
        matches_remaining: 2,
      });
    }
  }
}

async function getMatchday(supabase: any, sessionId: string) {
  const { data } = await supabase.from("league_sessions").select("current_matchday").eq("id", sessionId).single();
  return (data as any)?.current_matchday ?? 1;
}

async function finalizeFixture(supabase: any, fixtureId: string, fixture: any, homeGoals: number, awayGoals: number, cards: PlayerCard[], currentMatchday: number) {
  const homeCards = cards.filter(c => c.memberId === (fixture as any).home_member_id);
  const awayCards = cards.filter(c => c.memberId === (fixture as any).away_member_id);

  await supabase.from("fixtures").update({
    status: "finished",
    home_goals: homeGoals,
    away_goals: awayGoals,
    home_yellow: homeCards.filter(c => c.cardType === "yellow").length,
    away_yellow: awayCards.filter(c => c.cardType === "yellow").length,
    home_red: homeCards.filter(c => c.cardType === "red").length,
    away_red: awayCards.filter(c => c.cardType === "red").length,
    finished_at: new Date().toISOString(),
    pending_home_goals: null, pending_away_goals: null,
    pending_cards: null, result_submitter_id: null,
  }).eq("id", fixtureId);

  await processDiscipline(supabase, (fixture as any).session_id, fixture, currentMatchday, cards);

  // ── Finance: pay salaries + card fines, then auto-release if budget < 0 ──
  await processFinances(supabase, fixture, fixtureId, currentMatchday, [
    { memberId: (fixture as any).home_member_id, cards: homeCards },
    { memberId: (fixture as any).away_member_id, cards: awayCards },
  ]);
}

/**
 * Charge per-match salaries to every player in each member's squad and apply
 * fines for yellow/red cards. If a member's budget drops below zero, force-sell
 * their most expensive signing(s) until the deficit is covered.
 *
 * Failures here are logged but do NOT roll back the match result — finance
 * processing is a derived effect of the match.
 */
async function processFinances(
  supabase: any,
  fixture: any,
  fixtureId: string,
  matchday: number,
  parties: Array<{ memberId: string | null; cards: PlayerCard[] }>
) {
  try {
    const sessionId = (fixture as any).session_id as string;

    const { data: leagueSession } = await supabase
      .from("league_sessions")
      .select("id, tournament_id, total_matchdays")
      .eq("id", sessionId)
      .single();

    const tournamentId = (leagueSession as any)?.tournament_id as string | undefined;
    const totalMatchdays = ((leagueSession as any)?.total_matchdays ?? 0) as number;
    if (!tournamentId) return;

    // Pull the active market session id (may be null after the market closed)
    const { data: marketSession } = await supabase
      .from("market_sessions")
      .select("id")
      .eq("tournament_id", tournamentId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    const marketSessionId = (marketSession as any)?.id ?? null;

    for (const party of parties) {
      if (!party.memberId) continue;

      // 1) Squad and salaries
      const squad = await getMemberSquad(supabase, tournamentId, party.memberId);
      const ledgerRows: ExpenseRow[] = [];
      let totalCharge = 0;

      for (const p of squad) {
        const salary = salaryPerMatch(p.price, totalMatchdays);
        if (salary <= 0) continue;
        totalCharge += salary;
        ledgerRows.push({
          tournament_id: tournamentId,
          member_id: party.memberId,
          fixture_id: fixtureId,
          matchday,
          expense_type: "salary",
          player_id: p.playerId,
          player_name: p.name,
          amount: salary,
          is_credit: false,
        });
      }

      // 2) Card fines
      for (const c of party.cards) {
        const fine = c.cardType === "yellow" ? YELLOW_CARD_FINE : RED_CARD_FINE;
        totalCharge += fine;
        ledgerRows.push({
          tournament_id: tournamentId,
          member_id: party.memberId,
          fixture_id: fixtureId,
          matchday,
          expense_type: c.cardType === "yellow" ? "yellow_card" : "red_card",
          player_id: c.playerId,
          player_name: c.playerName,
          amount: fine,
          is_credit: false,
        });
      }

      if (totalCharge <= 0 && ledgerRows.length === 0) continue;

      // 3) Apply charge to the member's budget
      const { data: m } = await supabase
        .from("members")
        .select("budget")
        .eq("id", party.memberId)
        .single();
      const currentBudget = ((m as any)?.budget ?? 0) as number;
      const newBudget = currentBudget - totalCharge;
      await supabase
        .from("members")
        .update({ budget: newBudget })
        .eq("id", party.memberId);

      await recordExpenses(supabase, ledgerRows);

      // Surface a notification with the breakdown
      const salaryTotal = ledgerRows
        .filter((r) => r.expense_type === "salary")
        .reduce((s, r) => s + r.amount, 0);
      const yellowTotal = ledgerRows
        .filter((r) => r.expense_type === "yellow_card")
        .reduce((s, r) => s + r.amount, 0);
      const redTotal = ledgerRows
        .filter((r) => r.expense_type === "red_card")
        .reduce((s, r) => s + r.amount, 0);

      const fineSegments: string[] = [];
      if (yellowTotal > 0) fineSegments.push(`amarillas $${(yellowTotal / 1_000_000).toFixed(1)}M`);
      if (redTotal > 0) fineSegments.push(`rojas $${(redTotal / 1_000_000).toFixed(1)}M`);
      const fineSummary = fineSegments.length > 0 ? ` + ${fineSegments.join(" + ")}` : "";

      await createNotification({
        supabase,
        memberId: party.memberId,
        tournamentId,
        type: "salary_paid",
        title: "Gastos del partido",
        body: `Salarios $${(salaryTotal / 1_000_000).toFixed(1)}M${fineSummary}. Total $${(totalCharge / 1_000_000).toFixed(1)}M.`,
        metadata: { fixtureId, matchday, salaryTotal, yellowTotal, redTotal, totalCharge },
      });

      // 4) Auto-release if we ended in the red
      if (newBudget < 0) {
        const released: AutoReleaseEvent[] = await runAutoRelease(supabase, {
          tournamentId,
          memberId: party.memberId,
          fixtureId,
          matchday,
          sessionId: marketSessionId,
        });

        if (released.length > 0) {
          const lines = released
            .map((r) => `${r.playerName} (recuperaste $${(r.refund / 1_000_000).toFixed(1)}M)`)
            .join(", ");
          await createNotification({
            supabase,
            memberId: party.memberId,
            tournamentId,
            type: "auto_release",
            title: released.length === 1 ? "Jugador liberado" : "Jugadores liberados",
            body: `Sin presupuesto: ${lines}.`,
            metadata: { fixtureId, matchday, released },
          });
        }
      }
    }
  } catch (e) {
    console.error("[finalizeFixture/processFinances]", e);
  }
}

// POST — first player submits; second player confirms or disputes
export async function POST(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  const { homeGoals, awayGoals, cards = [], confirm } = body;

  // Validate goals are non-negative integers
  const hg = parseInt(homeGoals) || 0;
  const ag = parseInt(awayGoals) || 0;
  if (hg < 0 || ag < 0) {
    return NextResponse.json({ error: "Los goles no pueden ser negativos." }, { status: 400 });
  }

  const supabase = createServerClient();
  const { data: fixture } = await supabase.from("fixtures").select("*").eq("id", fixtureId).single();

  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });
  if ((fixture as any).status === "finished") return NextResponse.json({ error: "Ya finalizado." }, { status: 409 });
  if ((fixture as any).status !== "in_progress") return NextResponse.json({ error: "No ha comenzado." }, { status: 409 });

  const isHome = (fixture as any).home_member_id === auth.memberId;
  const isAway = (fixture as any).away_member_id === auth.memberId;
  if (!isHome && !isAway) return NextResponse.json({ error: "No eres participante." }, { status: 403 });

  const currentMatchday = await getMatchday(supabase, (fixture as any).session_id);
  const hasSubmitter = !!(fixture as any).result_submitter_id;
  const submitterIsMe = (fixture as any).result_submitter_id === auth.memberId;

  if (hasSubmitter && !submitterIsMe) {
    if (confirm === true) {
      // Merge first player's pending cards with second player's additional cards
      const pendingCards: PlayerCard[] = (fixture as any).pending_cards ?? [];
      const confirmerCards: PlayerCard[] = cards ?? [];
      const mergedCards = [...pendingCards, ...confirmerCards];
      await finalizeFixture(supabase, fixtureId, fixture,
        (fixture as any).pending_home_goals ?? 0,
        (fixture as any).pending_away_goals ?? 0,
        mergedCards, currentMatchday);
      return NextResponse.json({ ok: true, finalized: true });
    } else {
      // Dispute: clear pending
      await supabase.from("fixtures").update({
        pending_home_goals: null, pending_away_goals: null,
        pending_cards: null, result_submitter_id: null,
      }).eq("id", fixtureId);
      return NextResponse.json({ ok: true, disputed: true });
    }
  }

  // First submit (or re-submit)
  await supabase.from("fixtures").update({
    pending_home_goals: hg,
    pending_away_goals: ag,
    pending_cards: cards,
    result_submitter_id: auth.memberId,
  }).eq("id", fixtureId);

  return NextResponse.json({ ok: true, pending: true });
}

// PATCH — admin force-finalize
export async function PATCH(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;
  const supabase = createServerClient();

  const { verifyAdminToken } = await import("@/lib/supabase");
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  const { homeGoals = 0, awayGoals = 0, cards = [] } = body;

  const hg = Math.max(0, parseInt(homeGoals) || 0);
  const ag = Math.max(0, parseInt(awayGoals) || 0);

  const { data: fixture } = await supabase.from("fixtures").select("*").eq("id", fixtureId).single();
  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });

  const currentMatchday = await getMatchday(supabase, (fixture as any).session_id);
  await finalizeFixture(supabase, fixtureId, fixture, hg, ag, cards, currentMatchday);

  return NextResponse.json({ ok: true });
}
