import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/squad ───────────────────────────────────────
// Devuelve el equipo asignado al miembro y su plantilla de jugadores.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const supabase = createServerClient();

  // 1. Buscar asignación del miembro
  const { data: assignment, error: assignErr } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("member_id", auth.memberId)
    .maybeSingle();

  if (assignErr) {
    console.error("[squad] assignment", assignErr);
    return NextResponse.json({ error: "Error al obtener la asignación." }, { status: 500 });
  }

  if (!assignment) {
    return NextResponse.json({ error: "Aún no tienes equipo asignado." }, { status: 404 });
  }

  // 2. Obtener datos del equipo y presupuesto del miembro
  const [{ data: team, error: teamErr }, { data: memberData }] = await Promise.all([
    supabase.from("teams").select("id, name").eq("id", assignment.team_id).single(),
    supabase.from("members").select("budget").eq("id", auth.memberId).single(),
  ]);

  if (teamErr || !team) {
    return NextResponse.json({ error: "Equipo no encontrado." }, { status: 404 });
  }

  // 3. Obtener IDs de jugadores del equipo (team_players)
  const { data: teamPlayers, error: tpErr } = await supabase
    .from("team_players")
    .select("player_id")
    .eq("team_id", (team as any).id);

  if (tpErr) {
    console.error("[squad] team_players", tpErr);
    return NextResponse.json({ error: "Error al cargar jugadores." }, { status: 500 });
  }

  const playerIds = (teamPlayers ?? []).map((r: any) => r.player_id as string);

  // 4. Obtener datos de los jugadores
  let players: any[] = [];
  if (playerIds.length > 0) {
    const { data: playersData, error: playersErr } = await supabase
      .from("players")
      .select("id, name, ovr, position, country_name, price, clause")
      .in("id", playerIds)
      .order("ovr", { ascending: false });

    if (playersErr) {
      console.error("[squad] players", playersErr);
    } else {
      players = (playersData ?? []).map((p: any) => ({
        id: p.id,
        name: p.name,
        ovr: p.ovr,
        position: p.position ?? "—",
        countryName: p.country_name ?? "—",
        price: p.price ?? 0,
        clause: p.clause ?? 0,
      }));
    }
  }

  // 5. Calcular métricas
  const squadValue = players.reduce((s, p) => s + (p.price ?? 0), 0);
  const avgOvr =
    players.length > 0
      ? Math.round((players.reduce((s, p) => s + p.ovr, 0) / players.length) * 10) / 10
      : 0;

  return NextResponse.json({
    team: {
      id: (team as any).id,
      name: (team as any).name,
      squadValue,
      budget: (memberData as any)?.budget ?? 0,
    },
    players,
    avgOvr,
  });
}
