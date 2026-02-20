import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string; memberId: string }> };

// ─── DELETE /api/tournaments/[code]/members/[memberId] ────────────────────────

export async function DELETE(request: NextRequest, { params }: Params) {
  const { code, memberId } = await params;

  // Verificar que quien pide es el admin
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const supabase = createServerClient();

  // Confirmar que el miembro pertenece a este torneo
  const { data: member, error: findError } = await supabase
    .from("members")
    .select("id, display_name")
    .eq("id", memberId)
    .eq("tournament_id", auth.tournamentId)
    .single();

  if (findError || !member) {
    return NextResponse.json(
      { error: "Participante no encontrado en este torneo." },
      { status: 404 }
    );
  }

  // Eliminar la asignación de equipo (libera el equipo para que vuelva a estar disponible)
  await supabase
    .from("assignments")
    .delete()
    .eq("member_id", memberId);

  // Eliminar el miembro
  const { error: deleteError } = await supabase
    .from("members")
    .delete()
    .eq("id", memberId);

  if (deleteError) {
    console.error("[DELETE members]", deleteError);
    return NextResponse.json(
      { error: "Error al eliminar el participante." },
      { status: 500 }
    );
  }

  return NextResponse.json({ deleted: memberId });
}
