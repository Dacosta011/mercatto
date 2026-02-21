import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string; fixtureId: string }> };

// POST /api/tournaments/[code]/league/fixtures/[fixtureId]/confirm-start
export async function POST(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: fixture } = await supabase
    .from("fixtures")
    .select("id, home_member_id, away_member_id, status, home_confirmed, away_confirmed")
    .eq("id", fixtureId)
    .single();

  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });
  if ((fixture as any).status !== "pending")
    return NextResponse.json({ error: "El partido ya no está pendiente." }, { status: 409 });

  const isHome = (fixture as any).home_member_id === auth.memberId;
  const isAway = (fixture as any).away_member_id === auth.memberId;
  if (!isHome && !isAway)
    return NextResponse.json({ error: "No eres participante de este partido." }, { status: 403 });

  const update: Record<string, any> = isHome
    ? { home_confirmed: true }
    : { away_confirmed: true };

  const newHomeConfirmed = isHome ? true : (fixture as any).home_confirmed;
  const newAwayConfirmed = isAway ? true : (fixture as any).away_confirmed;

  // If both confirmed → start match
  if (newHomeConfirmed && newAwayConfirmed) {
    update.status = "in_progress";
    update.started_at = new Date().toISOString();
  }

  await supabase.from("fixtures").update(update).eq("id", fixtureId);

  return NextResponse.json({ ok: true, started: newHomeConfirmed && newAwayConfirmed });
}
