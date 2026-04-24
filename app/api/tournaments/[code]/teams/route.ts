import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/teams ────────────────────────────────────────

export async function GET(_request: NextRequest, { params }: Params) {
  const { code } = await params;

  const supabase = createServerClient();

  // 1) Obtener el torneo
  const { data: tournament, error: tErr } = await supabase
    .from("tournaments")
    .select("id")
    .eq("code", code.toUpperCase())
    .single();

  if (tErr || !tournament) {
    return NextResponse.json({ error: "Torneo no encontrado." }, { status: 404 });
  }

  // 2) Obtener los member_ids del torneo
  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", tournament.id);

  const memberIds = (members ?? []).map((m: any) => m.id as string);

  // 3) Equipos ya asignados a esos miembros
  let takenIds: string[] = [];
  if (memberIds.length > 0) {
    const { data: taken } = await supabase
      .from("assignments")
      .select("team_id")
      .in("member_id", memberIds);
    takenIds = (taken ?? []).map((r: any) => r.team_id as string);
  }

  // 4) Equipos disponibles
  let query = supabase
    .from("teams")
    .select("id, name, crest_url")
    .eq("active", true)
    .order("name");

  if (takenIds.length > 0) {
    query = query.not("id", "in", `(${takenIds.join(",")})`);
  }

  const { data: teams, error: teamsErr } = await query;

  if (teamsErr) {
    console.error("[teams]", teamsErr);
    return NextResponse.json({ error: "Error al obtener equipos." }, { status: 500 });
  }

  return NextResponse.json(
    (teams ?? []).map((t: any) => ({
      id: t.id,
      name: t.name,
      crestUrl: t.crest_url ?? null,
      squadValue: t.squad_value ?? t.squadValue ?? 0,
      budget: t.budget ?? 0,
    }))
  );
}
