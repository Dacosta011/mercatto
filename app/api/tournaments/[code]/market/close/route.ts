import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";
import { createBulkNotifications } from "@/lib/notifications";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/market/close ────────────────────────────────
// Admin only. Closes the market early. Expires all pending offers.

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json(
      { error: "El mercado no está activo." },
      { status: 409 }
    );
  }

  const sessionId = (session as any).id;

  await supabase
    .from("market_offers")
    .update({ status: "expired", responded_at: new Date().toISOString() })
    .eq("session_id", sessionId)
    .eq("status", "pending");

  await supabase
    .from("icon_auctions")
    .update({ phase: "finished", ends_at: new Date().toISOString() })
    .eq("session_id", sessionId)
    .eq("phase", "active");

  await supabase
    .from("market_sessions")
    .update({
      status: "finished",
      finished_at: new Date().toISOString(),
    })
    .eq("id", sessionId);

  await supabase
    .from("tournaments")
    .update({ status: "lobby" })
    .eq("id", auth.tournamentId);

  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  await createBulkNotifications(
    supabase,
    auth.tournamentId,
    (members ?? []).map((m: any) => m.id),
    "market_closed",
    "Mercado cerrado",
    "El admin ha cerrado el mercado. Los fichajes se han finalizado."
  );

  return NextResponse.json({ ok: true });
}
