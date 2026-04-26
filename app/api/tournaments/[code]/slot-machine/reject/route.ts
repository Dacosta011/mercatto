import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

// POST /api/tournaments/[code]/slot-machine/reject
export async function POST(req: NextRequest, { params }: { params: Promise<{ code: string }> }) {
  const { code } = await params;
  const supabase = createServerClient();

  const auth = await verifyMemberToken(req, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const { memberId } = auth;
  const { spinId } = await req.json();

  if (!spinId) return NextResponse.json({ error: "spinId requerido." }, { status: 400 });

  const { data: spin } = await supabase
    .from("slot_machine_spins")
    .select("id, status")
    .eq("id", spinId)
    .eq("member_id", memberId)
    .single();

  if (!spin) return NextResponse.json({ error: "Giro no encontrado." }, { status: 404 });
  if (spin.status !== "pending") return NextResponse.json({ error: "Este giro ya fue procesado." }, { status: 409 });

  await supabase.from("slot_machine_spins").update({ status: "rejected" }).eq("id", spinId);

  return NextResponse.json({ ok: true });
}
