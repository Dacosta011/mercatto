import { SupabaseClient } from "@supabase/supabase-js";

// ─── Tunable game constants ───────────────────────────────────────────────────
// All amounts are stored as bigint cents-equivalent (game uses millions, but
// the math is the same since we only divide / multiply by integers).

/** Fraction of a player's price that becomes their per-season salary. */
export const SEASON_SALARY_PCT = 0.10;

/** Yellow-card fine in raw budget units. */
export const YELLOW_CARD_FINE = 500_000;

/** Red-card fine in raw budget units. */
export const RED_CARD_FINE = 2_000_000;

/** Fraction of the original signing price refunded when the system force-sells
 *  a signing to cover a negative budget. */
export const AUTO_RELEASE_REFUND_PCT = 0.5;

// ─── Salary math ──────────────────────────────────────────────────────────────

/**
 * Per-match salary for a single player.
 *
 * `totalMatchdays` is the number of matchdays each team plays in the league
 * (i.e. `league_sessions.total_matchdays`). When the value is 0 we return 0
 * to avoid a division-by-zero — this should never happen in practice because
 * the league must be started before `finalizeFixture` runs.
 */
export function salaryPerMatch(price: number, totalMatchdays: number): number {
  if (!totalMatchdays || totalMatchdays <= 0) return 0;
  return Math.floor((price * SEASON_SALARY_PCT) / totalMatchdays);
}

/** Per-season salary for a single player (all matchdays of the league). */
export function salaryPerSeason(price: number): number {
  return Math.floor(price * SEASON_SALARY_PCT);
}

// ─── Ledger writers ───────────────────────────────────────────────────────────

export type ExpenseType =
  | "salary"
  | "yellow_card"
  | "red_card"
  | "auto_release";

export interface ExpenseRow {
  tournament_id: string;
  member_id: string;
  fixture_id: string | null;
  matchday: number | null;
  expense_type: ExpenseType;
  player_id: string | null;
  player_name: string | null;
  amount: number;
  is_credit: boolean;
}

/**
 * Resolve the effective owner (member_id) of every player belonging to the
 * given member, considering both the materialized roster (`team_players`) and
 * the most recent transfer for each player. Returns players the member owns
 * RIGHT NOW for the purpose of paying salaries, plus their `price` and `name`.
 *
 * NOTE: this mirrors the ownership rules used elsewhere in the codebase. A
 * player whose latest transfer is `auto_release` is considered free and is
 * excluded.
 */
export async function getMemberSquad(
  supabase: SupabaseClient,
  tournamentId: string,
  memberId: string
): Promise<Array<{ playerId: string; price: number; name: string; ovr: number; position: string; headshotUrl: string | null }>> {
  // 1. Member's team
  const { data: assignment } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("member_id", memberId)
    .maybeSingle();

  const teamId = (assignment as any)?.team_id as string | undefined;
  if (!teamId) return [];

  // 2. Active market session id (for transfers scoped to "this season")
  const { data: session } = await supabase
    .from("market_sessions")
    .select("id")
    .eq("tournament_id", tournamentId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const sessionId = (session as any)?.id as string | undefined;

  // 3. Base roster from team_players
  const { data: basePlayers } = await supabase
    .from("team_players")
    .select("player_id")
    .eq("team_id", teamId);

  const baseIds = new Set(
    (basePlayers ?? []).map((r: any) => r.player_id as string)
  );

  // 4. All transfers in the most recent (or last finished) market session that
  //    affect this member, to derive net ownership at this exact moment.
  let inboundIds = new Set<string>();
  let outboundIds = new Set<string>();
  let releasedIds = new Set<string>();

  if (sessionId) {
    const { data: transfers } = await supabase
      .from("market_transfers")
      .select("player_id, buyer_id, seller_id, transfer_type, created_at")
      .eq("session_id", sessionId)
      .in("transfer_type", ["clause", "offer", "icon_auction", "auto_release"])
      .order("created_at", { ascending: true });

    // Build the effective current owner for each transferred player.
    // Iterating ASC means the last write wins — exactly what we want.
    // This handles multi-hop chains (M0→M1→M2→M3) correctly: even if the
    // original seller (M0) is not buyer/seller in the *latest* transfer, their
    // player will still be removed from their squad because baseIds contains it
    // and the current owner is someone else.
    const effectiveOwner: Record<string, string | null> = {};
    for (const t of transfers ?? []) {
      const pid = (t as any).player_id as string;
      const buyer = (t as any).buyer_id as string | null;
      const tt = (t as any).transfer_type as string;
      effectiveOwner[pid] = tt === "auto_release" ? null : buyer;
    }
    for (const [pid, currentOwner] of Object.entries(effectiveOwner)) {
      if (currentOwner === null) {
        // Player was auto-released — remove from anyone's squad
        releasedIds.add(pid);
      } else if (currentOwner === memberId) {
        // This member is the current owner (bought mid-market)
        inboundIds.add(pid);
      } else if (baseIds.has(pid)) {
        // Player was in this team's base roster but has since been sold
        outboundIds.add(pid);
      }
      // else: transfer between other members — doesn't affect this member
    }
  }

  const ownedIds = new Set<string>();
  for (const pid of baseIds) {
    if (!outboundIds.has(pid) && !releasedIds.has(pid)) ownedIds.add(pid);
  }
  for (const pid of inboundIds) {
    if (!releasedIds.has(pid)) ownedIds.add(pid);
  }

  if (ownedIds.size === 0) return [];

  const { data: players } = await supabase
    .from("players")
    .select("id, name, price, ovr, position, headshot_url")
    .in("id", Array.from(ownedIds));

  return (players ?? []).map((p: any) => ({
    playerId: p.id as string,
    price: (p.price ?? 0) as number,
    name: (p.name ?? "—") as string,
    ovr: (p.ovr ?? 0) as number,
    position: (p.position ?? "—") as string,
    headshotUrl: (p.headshot_url ?? null) as string | null,
  }));
}

/**
 * Insert a batch of ledger rows in one statement.
 * Caller is responsible for already having mutated `members.budget`.
 */
export async function recordExpenses(
  supabase: SupabaseClient,
  rows: ExpenseRow[]
): Promise<void> {
  if (rows.length === 0) return;
  const { error } = await supabase.from("club_expenses").insert(rows);
  if (error) {
    console.error("[expenses.recordExpenses]", error);
  }
}

// ─── Auto-release ─────────────────────────────────────────────────────────────

export interface AutoReleaseEvent {
  playerId: string;
  playerName: string;
  refund: number;
  originalPrice: number;
}

/**
 * Force-sell signings (most expensive first) until the member's budget is back
 * to >= 0. Updates `members.budget` and inserts compensating
 * `market_transfers` + `club_expenses` rows.
 *
 * Returns the list of released players for downstream notifications/UI.
 */
export async function runAutoRelease(
  supabase: SupabaseClient,
  params: {
    tournamentId: string;
    memberId: string;
    fixtureId: string | null;
    matchday: number | null;
    sessionId: string | null;
  }
): Promise<AutoReleaseEvent[]> {
  const { tournamentId, memberId, fixtureId, matchday, sessionId } = params;
  const released: AutoReleaseEvent[] = [];

  // Refresh budget
  const { data: member } = await supabase
    .from("members")
    .select("budget")
    .eq("id", memberId)
    .single();

  let budget: number = ((member as any)?.budget ?? 0) as number;
  if (budget >= 0) return released;

  // Need member's team for stamping seller_team_id on the auto_release row
  const { data: assignment } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("member_id", memberId)
    .maybeSingle();
  const teamId = (assignment as any)?.team_id as string | undefined;

  // Loop: pick the most expensive owned player and release them, until the
  // budget is back in the green or there are no more candidates.
  for (let safety = 0; safety < 30; safety++) {
    if (budget >= 0) break;

    const squad = await getMemberSquad(supabase, tournamentId, memberId);
    if (squad.length === 0) break;

    squad.sort((a, b) => b.price - a.price);
    const target = squad[0];
    if (!target || target.price <= 0) break;

    const refund = Math.floor(target.price * AUTO_RELEASE_REFUND_PCT);

    // 1) Compensating transfer so ownership lookups elsewhere see the player
    //    as "released" (last transfer wins). Only valid when there's a session.
    if (sessionId && teamId) {
      await supabase.from("market_transfers").insert({
        session_id: sessionId,
        turn_id: null,
        buyer_id: null,
        seller_id: memberId,
        seller_team_id: teamId,
        player_id: target.playerId,
        transfer_type: "auto_release",
        amount: refund,
      });
    }

    // 2) Drop the row from team_players (if any) so the player stops being
    //    rendered as part of this team's base roster.
    if (teamId) {
      await supabase
        .from("team_players")
        .delete()
        .eq("team_id", teamId)
        .eq("player_id", target.playerId);
    }

    // 3) Credit the budget
    budget += refund;
    await supabase
      .from("members")
      .update({ budget })
      .eq("id", memberId);

    // 4) Ledger row (refund is a CREDIT)
    await recordExpenses(supabase, [
      {
        tournament_id: tournamentId,
        member_id: memberId,
        fixture_id: fixtureId,
        matchday: matchday,
        expense_type: "auto_release",
        player_id: target.playerId,
        player_name: target.name,
        amount: refund,
        is_credit: true,
      },
    ]);

    released.push({
      playerId: target.playerId,
      playerName: target.name,
      refund,
      originalPrice: target.price,
    });
  }

  return released;
}
