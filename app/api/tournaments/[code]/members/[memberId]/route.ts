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

  // Delete the member first — this is the authoritative event that the client's
  // PhaseRedirectGuard watches. Deleting assignment first caused a visual glitch
  // where the lobby briefly showed the member without a team before they disappeared.
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

  // Delete the assignment after the member is gone (frees the team slot)
  await supabase
    .from("assignments")
    .delete()
    .eq("member_id", memberId);

  return NextResponse.json({ deleted: memberId });
}
