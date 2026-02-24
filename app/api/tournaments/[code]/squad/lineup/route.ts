import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

const VALID_FORMATIONS = ["4-3-3", "4-4-2", "4-2-3-1", "3-5-2"];

// GET — load saved lineup
export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data } = await supabase
    .from("lineups")
    .select("formation, slots")
    .eq("member_id", auth.memberId)
    .maybeSingle();

  if (!data) {
    return NextResponse.json({ formation: null, slots: null });
  }

  return NextResponse.json({
    formation: (data as any).formation,
    slots: (data as any).slots,
  });
}

// PUT — save lineup
export async function PUT(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  const { formation, slots } = body as { formation: string; slots: Record<string, string | null> };

  if (!formation || !VALID_FORMATIONS.includes(formation)) {
    return NextResponse.json({ error: "Formación inválida." }, { status: 400 });
  }

  if (!slots || typeof slots !== "object") {
    return NextResponse.json({ error: "Slots inválidos." }, { status: 400 });
  }

  const supabase = createServerClient();

  const { error } = await supabase
    .from("lineups")
    .upsert(
      {
        member_id: auth.memberId,
        formation,
        slots,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "member_id" }
    );

  if (error) {
    console.error("[lineup] upsert", error);
    return NextResponse.json({ error: "Error al guardar la alineación." }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
