import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string; fixtureId: string }> };

interface PlayerCard { playerId: string; playerName: string; cardType: "yellow" | "red"; memberId: string }

// Helper: process player-level discipline after match finalization
async function processDiscipline(
  supabase: any,
  sessionId: string,
  fixture: any,
  currentMatchday: number,
  playerCards: PlayerCard[]
) {
  if (playerCards.length === 0) return;

  // Insert discipline rows (one per card event)
  const rows = playerCards.map((c) => ({
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
  const playerIds = [...new Set(playerCards.map((c) => c.playerId))];

  for (const playerId of playerIds) {
    const card = playerCards.find((c) => c.playerId === playerId)!;
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
}

// POST — first player submits; second player confirms or disputes
export async function POST(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  // cards: Array<{ playerId, playerName, cardType, memberId }>
  const { homeGoals, awayGoals, cards = [], confirm } = body;

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
    pending_home_goals: homeGoals ?? 0,
    pending_away_goals: awayGoals ?? 0,
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

  const { data: fixture } = await supabase.from("fixtures").select("*").eq("id", fixtureId).single();
  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });

  const currentMatchday = await getMatchday(supabase, (fixture as any).session_id);
  await finalizeFixture(supabase, fixtureId, fixture, homeGoals, awayGoals, cards, currentMatchday);

  return NextResponse.json({ ok: true });
}
