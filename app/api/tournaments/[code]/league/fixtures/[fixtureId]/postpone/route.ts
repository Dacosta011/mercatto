import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string; fixtureId: string }> };

// POST — Request / accept / force postpone
export async function POST(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;
  const supabase = createServerClient();

  // Try admin first
  const adminAuth = await verifyAdminToken(request, code);

  if (adminAuth.ok) {
    // Admin forces postpone
    const { data: fixture } = await supabase
      .from("fixtures")
      .select("id, status")
      .eq("id", fixtureId)
      .single();

    if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });
    if ((fixture as any).status === "finished")
      return NextResponse.json({ error: "El partido ya finalizó." }, { status: 409 });
    if ((fixture as any).status === "postponed")
      return NextResponse.json({ error: "El partido ya está aplazado." }, { status: 409 });

    await supabase.from("fixtures").update({
      status: "postponed",
      home_confirmed: false,
      away_confirmed: false,
      result_submitter_id: null,
      pending_home_goals: null,
      pending_away_goals: null,
      pending_cards: null,
      postpone_requested_by: null,
      reactivate_requested_by: null,
    }).eq("id", fixtureId);

    return NextResponse.json({ ok: true, forced: true });
  }

  // Player flow
  const memberAuth = await verifyMemberToken(request, code);
  if (!memberAuth.ok) return NextResponse.json({ error: memberAuth.error }, { status: memberAuth.status });

  const { data: fixture } = await supabase
    .from("fixtures")
    .select("id, status, home_member_id, away_member_id, postpone_requested_by")
    .eq("id", fixtureId)
    .single();

  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });

  const f = fixture as any;
  const isHome = f.home_member_id === memberAuth.memberId;
  const isAway = f.away_member_id === memberAuth.memberId;
  if (!isHome && !isAway)
    return NextResponse.json({ error: "No eres participante de este partido." }, { status: 403 });

  if (f.status === "finished")
    return NextResponse.json({ error: "El partido ya finalizó." }, { status: 409 });
  if (f.status === "postponed")
    return NextResponse.json({ error: "El partido ya está aplazado." }, { status: 409 });

  if (!f.postpone_requested_by) {
    // First player requests
    await supabase.from("fixtures").update({
      postpone_requested_by: memberAuth.memberId,
    }).eq("id", fixtureId);
    return NextResponse.json({ ok: true, requested: true });
  }

  if (f.postpone_requested_by === memberAuth.memberId) {
    return NextResponse.json({ error: "Ya solicitaste aplazar este partido." }, { status: 409 });
  }

  // Rival accepts → postpone
  await supabase.from("fixtures").update({
    status: "postponed",
    home_confirmed: false,
    away_confirmed: false,
    result_submitter_id: null,
    pending_home_goals: null,
    pending_away_goals: null,
    pending_cards: null,
    postpone_requested_by: null,
    reactivate_requested_by: null,
  }).eq("id", fixtureId);

  return NextResponse.json({ ok: true, postponed: true });
}

// DELETE — Cancel a pending postpone request
export async function DELETE(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: fixture } = await supabase
    .from("fixtures")
    .select("id, postpone_requested_by")
    .eq("id", fixtureId)
    .single();

  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });

  if ((fixture as any).postpone_requested_by !== auth.memberId)
    return NextResponse.json({ error: "No tienes una solicitud pendiente." }, { status: 409 });

  await supabase.from("fixtures").update({ postpone_requested_by: null }).eq("id", fixtureId);

  return NextResponse.json({ ok: true });
}
