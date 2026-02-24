import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { shuffle } from "@/lib/iconAuction";

type Params = { params: Promise<{ code: string }> };

// POST /api/tournaments/[code]/market/icon-auction/vote-activation
// Body: { vote: boolean }
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  if (typeof body.vote !== "boolean") {
    return NextResponse.json({ error: "Voto inválido." }, { status: 400 });
  }

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions").select("id, current_round")
    .eq("tournament_id", auth.tournamentId).maybeSingle();
  if (!session) return NextResponse.json({ error: "Mercado no activo." }, { status: 409 });

  const { data: auction } = await supabase
    .from("icon_auctions").select("id, phase, presented_icon_ids")
    .eq("session_id", (session as any).id)
    .eq("round_num", (session as any).current_round).maybeSingle();

  if (!auction || (auction as any).phase !== "vote_activation") {
    return NextResponse.json({ error: "No hay votación activa." }, { status: 409 });
  }

  const auctionId = (auction as any).id;

  // Check if already voted
  const { data: existing } = await supabase
    .from("icon_activation_votes").select("id")
    .eq("auction_id", auctionId).eq("member_id", auth.memberId).maybeSingle();
  if (existing) return NextResponse.json({ error: "Ya votaste." }, { status: 409 });

  // Insert vote
  await supabase.from("icon_activation_votes").insert({
    auction_id: auctionId, member_id: auth.memberId, vote: body.vote,
  });

  // Count total members
  const { data: members } = await supabase
    .from("members").select("id").eq("tournament_id", auth.tournamentId);
  const total = (members ?? []).length;
  const memberIds = (members ?? []).map((m: any) => m.id);

  // Count all votes now
  const { data: allVotes } = await supabase
    .from("icon_activation_votes").select("vote").eq("auction_id", auctionId);

  const votes = allVotes ?? [];
  const yesCount = votes.filter((v: any) => v.vote === true).length;
  const noCount = votes.filter((v: any) => v.vote === false).length;
  const majority = Math.floor(total / 2) + 1;

  let newPhase: string | null = null;

  if (yesCount >= majority) newPhase = "vote_icon";
  else if (noCount >= majority) newPhase = "skipped";
  else if (votes.length >= total) {
    newPhase = yesCount >= noCount ? "vote_icon" : "skipped";
  }

  if (newPhase) {
    const updateData: any = { phase: newPhase };
    // If starting bidding phase: also set bidder_order
    if (newPhase === "vote_icon") {
      // Just update phase — bidder order set when icon is selected
    }
    await supabase.from("icon_auctions").update(updateData).eq("id", auctionId);

    if (newPhase === "skipped") {
      // No auction: mark as finished-skipped
      await supabase.from("icon_auctions").update({ phase: "skipped" }).eq("id", auctionId);
    }
  }

  return NextResponse.json({ ok: true, phase: newPhase ?? "vote_activation" });
}
