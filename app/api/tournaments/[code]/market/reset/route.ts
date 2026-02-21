import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/market/reset ────────────────────────────────
// Admin only. Reverts all budget changes from the market and deletes the session
// so the market can be restarted. team_players is NEVER modified by the market,
// so no player movement needs to be reversed.

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session) {
    return NextResponse.json({ error: "No hay mercado para reiniciar." }, { status: 404 });
  }

  const sessionId = (session as any).id;

  // ── 1. Fetch all transfers to reverse budget changes ──────────────────────
  const { data: transfers } = await supabase
    .from("market_transfers")
    .select("buyer_id, seller_id, amount")
    .eq("session_id", sessionId)
    .in("transfer_type", ["clause", "offer"]);

  // Accumulate net budget delta per member
  const budgetDelta: Record<string, number> = {};
  for (const t of transfers ?? []) {
    budgetDelta[t.buyer_id]  = (budgetDelta[t.buyer_id]  ?? 0) - t.amount; // buyer spent
    if (t.seller_id) {
      budgetDelta[t.seller_id] = (budgetDelta[t.seller_id] ?? 0) + t.amount; // seller received
    }
  }

  // ── 2. Restore each member's budget to pre-market value ──────────────────
  for (const [memberId, delta] of Object.entries(budgetDelta)) {
    if (delta === 0) continue;
    const { data: m } = await supabase
      .from("members")
      .select("budget")
      .eq("id", memberId)
      .single();
    if (m) {
      await supabase
        .from("members")
        .update({ budget: (m as any).budget - delta }) // subtract what was gained/lost
        .eq("id", memberId);
    }
  }

  // ── 3. Reset market_purchases for all members in this tournament ──────────
  const { data: allMembers } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  const memberIds = (allMembers ?? []).map((m: any) => m.id);
  if (memberIds.length > 0) {
    await supabase
      .from("members")
      .update({ market_purchases: 0 })
      .in("id", memberIds);
  }

  // ── 4. Delete the session (cascades: turns, transfers, offers) ────────────
  await supabase.from("market_sessions").delete().eq("id", sessionId);

  // ── 5. Return tournament to lobby status ──────────────────────────────────
  await supabase
    .from("tournaments")
    .update({ status: "lobby" })
    .eq("id", auth.tournamentId);

  return NextResponse.json({ ok: true });
}
