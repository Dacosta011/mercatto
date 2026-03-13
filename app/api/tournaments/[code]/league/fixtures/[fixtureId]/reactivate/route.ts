import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string; fixtureId: string }> };

// POST — Request / accept / force reactivate
export async function POST(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;
  const supabase = createServerClient();

  // Try admin first
  const adminAuth = await verifyAdminToken(request, code);

  if (adminAuth.ok) {
    const { data: fixture } = await supabase
      .from("fixtures")
      .select("id, status")
      .eq("id", fixtureId)
      .single();

    if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });
    if ((fixture as any).status !== "postponed")
      return NextResponse.json({ error: "El partido no está aplazado." }, { status: 409 });

    await supabase.from("fixtures").update({
      status: "pending",
      home_confirmed: false,
      away_confirmed: false,
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
    .select("id, status, home_member_id, away_member_id, reactivate_requested_by")
    .eq("id", fixtureId)
    .single();

  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });

  const f = fixture as any;
  const isHome = f.home_member_id === memberAuth.memberId;
  const isAway = f.away_member_id === memberAuth.memberId;
  if (!isHome && !isAway)
    return NextResponse.json({ error: "No eres participante de este partido." }, { status: 403 });

  if (f.status !== "postponed")
    return NextResponse.json({ error: "El partido no está aplazado." }, { status: 409 });

  if (!f.reactivate_requested_by) {
    await supabase.from("fixtures").update({
      reactivate_requested_by: memberAuth.memberId,
    }).eq("id", fixtureId);
    return NextResponse.json({ ok: true, requested: true });
  }

  if (f.reactivate_requested_by === memberAuth.memberId) {
    return NextResponse.json({ error: "Ya solicitaste reactivar este partido." }, { status: 409 });
  }

  // Rival accepts → reactivate
  await supabase.from("fixtures").update({
    status: "pending",
    home_confirmed: false,
    away_confirmed: false,
    postpone_requested_by: null,
    reactivate_requested_by: null,
  }).eq("id", fixtureId);

  return NextResponse.json({ ok: true, reactivated: true });
}

// DELETE — Cancel a pending reactivate request
export async function DELETE(request: NextRequest, { params }: Params) {
  const { code, fixtureId } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: fixture } = await supabase
    .from("fixtures")
    .select("id, reactivate_requested_by")
    .eq("id", fixtureId)
    .single();

  if (!fixture) return NextResponse.json({ error: "Partido no encontrado." }, { status: 404 });

  if ((fixture as any).reactivate_requested_by !== auth.memberId)
    return NextResponse.json({ error: "No tienes una solicitud pendiente." }, { status: 409 });

  await supabase.from("fixtures").update({ reactivate_requested_by: null }).eq("id", fixtureId);

  return NextResponse.json({ ok: true });
}
