import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string; offerId: string }> };

// ─── PATCH /api/tournaments/[code]/market/offer/[offerId] ─────────────────────
// Seller accepts or rejects an offer.
// Either way the BUYER'S turn (stored in offer.turn_id) is completed and the
// market advances to the next turn.
// Body: { action: "accept" | "reject" }

export async function PATCH(request: NextRequest, { params }: Params) {
  const { code, offerId } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { action: "accept" | "reject" };
  try { body = await request.json(); } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  // Fetch the offer (only the seller can respond)
  const { data: offer } = await supabase
    .from("market_offers")
    .select("*")
    .eq("id", offerId)
    .eq("seller_id", auth.memberId)
    .eq("status", "pending")
    .maybeSingle();

  if (!offer) return NextResponse.json({ error: "Oferta no encontrada." }, { status: 404 });

  // Fetch the session (needed for turn advancement)
  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status, current_round, total_rounds")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json({ error: "El mercado no está activo." }, { status: 409 });
  }

  // ── Reject ────────────────────────────────────────────────────────────────
  // Turn stays active — buyer can try another action
  if (body.action === "reject") {
    await supabase
      .from("market_offers")
      .update({ status: "rejected", responded_at: new Date().toISOString() })
      .eq("id", offerId);

    return NextResponse.json({ ok: true, action: "rejected" });
  }

  // ── Accept ────────────────────────────────────────────────────────────────

  // Re-validate buyer limits (could have changed since offer was created)
  const { data: buyer } = await supabase
    .from("members")
    .select("budget, market_purchases")
    .eq("id", (offer as any).buyer_id)
    .single();

  if ((buyer as any)?.market_purchases >= 3) {
    return NextResponse.json({ error: "El comprador ya alcanzó el límite de compras." }, { status: 422 });
  }
  if ((buyer as any)?.budget < (offer as any).amount) {
    return NextResponse.json({ error: "El comprador ya no tiene suficiente presupuesto." }, { status: 422 });
  }

  // Find effective seller team — check if player was transferred before
  const { data: tp } = await supabase
    .from("team_players")
    .select("team_id")
    .eq("player_id", (offer as any).player_id)
    .maybeSingle();

  // If player was transferred previously, seller_team is the buyer's assigned team
  const { data: sellerAssignment } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("member_id", auth.memberId)
    .maybeSingle();

  const sellerTeamId = (sellerAssignment as any)?.team_id ?? (tp as any)?.team_id ?? null;

  // Deduct buyer budget + increment purchases
  await supabase
    .from("members")
    .update({
      budget: (buyer as any).budget - (offer as any).amount,
      market_purchases: (buyer as any).market_purchases + 1,
    })
    .eq("id", (offer as any).buyer_id);

  // Add offer amount to seller's budget
  const { data: sellerMember } = await supabase
    .from("members")
    .select("budget")
    .eq("id", auth.memberId)
    .single();

  await supabase
    .from("members")
    .update({ budget: ((sellerMember as any)?.budget ?? 0) + (offer as any).amount })
    .eq("id", auth.memberId);

  // Record transfer in history
  await supabase.from("market_transfers").insert({
    session_id: (session as any).id,
    turn_id: (offer as any).turn_id,
    buyer_id: (offer as any).buyer_id,
    seller_id: auth.memberId,
    seller_team_id: sellerTeamId,
    player_id: (offer as any).player_id,
    transfer_type: "offer",
    amount: (offer as any).amount,
  });

  // Mark offer accepted
  await supabase
    .from("market_offers")
    .update({ status: "accepted", responded_at: new Date().toISOString() })
    .eq("id", offerId);

  // Complete the buyer's turn and advance
  await completeTurnAndAdvance(supabase, session, (offer as any).turn_id);

  return NextResponse.json({ ok: true, action: "accepted" });
}

// ─── Helper: mark a turn as completed and activate the next one ───────────────
async function completeTurnAndAdvance(supabase: any, session: any, turnId: string) {
  await supabase
    .from("market_turns")
    .update({ status: "completed", completed_at: new Date().toISOString() })
    .eq("id", turnId);

  // Reuse shared advanceTurn logic (auto-skips 3/3 members)
  const { advanceTurn } = await import("../../action/route");
  await advanceTurn(supabase, session);
}
