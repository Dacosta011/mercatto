import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// POST /api/tournaments/[code]/league/reset
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Delete league session (cascades to fixtures, discipline, suspensions, matchday_rests)
  await supabase
    .from("league_sessions")
    .delete()
    .eq("tournament_id", auth.tournamentId);

  // Delete previous market session so a new market can be started
  const { data: prevSession } = await supabase
    .from("market_sessions")
    .select("id")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (prevSession) {
    const sid = (prevSession as any).id;
    await supabase.from("icon_bids").delete().in(
      "auction_id",
      (await supabase.from("icon_auctions").select("id").eq("session_id", sid)).data?.map((a: any) => a.id) ?? [],
    );
    await supabase.from("icon_selection_votes").delete().in(
      "auction_id",
      (await supabase.from("icon_auctions").select("id").eq("session_id", sid)).data?.map((a: any) => a.id) ?? [],
    );
    await supabase.from("icon_activation_votes").delete().in(
      "auction_id",
      (await supabase.from("icon_auctions").select("id").eq("session_id", sid)).data?.map((a: any) => a.id) ?? [],
    );
    await supabase.from("icon_auctions").delete().eq("session_id", sid);
    await supabase.from("market_offers").delete().eq("session_id", sid);
    await supabase.from("market_transfers").delete().eq("session_id", sid);
    await supabase.from("market_turns").delete().eq("session_id", sid);
    await supabase.from("market_sessions").delete().eq("id", sid);
  }

  // Reset member market-related fields for a fresh cycle
  await supabase
    .from("members")
    .update({ budget: 200_000_000, market_purchases: 0 })
    .eq("tournament_id", auth.tournamentId);

  // Reset tournament status to lobby
  await supabase
    .from("tournaments")
    .update({ status: "lobby" })
    .eq("id", auth.tournamentId);

  return NextResponse.json({ ok: true });
}
