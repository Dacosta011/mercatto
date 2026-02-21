import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/squad ───────────────────────────────────────
// Devuelve el equipo asignado al miembro con transferencias del mercado aplicadas.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const supabase = createServerClient();

  // 1. Asignación del miembro
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

  const myTeamId = (assignment as any).team_id as string;

  // 2. Equipo + presupuesto + torneo en paralelo
  const [{ data: team, error: teamErr }, { data: memberData }, { data: tournamentData }] = await Promise.all([
    supabase.from("teams").select("id, name").eq("id", myTeamId).single(),
    supabase.from("members").select("budget").eq("id", auth.memberId).single(),
    supabase.from("tournaments").select("id").eq("code", code).maybeSingle(),
  ]);

  if (teamErr || !team) {
    return NextResponse.json({ error: "Equipo no encontrado." }, { status: 404 });
  }

  // 3. Plantilla base desde team_players
  const { data: teamPlayers, error: tpErr } = await supabase
    .from("team_players")
    .select("player_id")
    .eq("team_id", myTeamId);

  if (tpErr) {
    console.error("[squad] team_players", tpErr);
    return NextResponse.json({ error: "Error al cargar jugadores." }, { status: 500 });
  }

  const basePlayerIds = new Set((teamPlayers ?? []).map((r: any) => r.player_id as string));

  // 4. Transferencias del mercado activo (si existe)
  const soldPlayerIds   = new Set<string>(); // jugadores que salieron de mi equipo
  const boughtPlayerIds = new Set<string>(); // jugadores que compré en el mercado

  if (tournamentData) {
    const { data: session } = await supabase
      .from("market_sessions")
      .select("id")
      .eq("tournament_id", (tournamentData as any).id)
      .maybeSingle();

    if (session) {
      const { data: transfers } = await supabase
        .from("market_transfers")
        .select("buyer_id, seller_team_id, player_id, transfer_type")
        .eq("session_id", (session as any).id)
        .in("transfer_type", ["clause", "offer"]);

      for (const t of transfers ?? []) {
        if ((t as any).seller_team_id === myTeamId) {
          soldPlayerIds.add((t as any).player_id);
        }
        if ((t as any).buyer_id === auth.memberId) {
          boughtPlayerIds.add((t as any).player_id);
        }
      }
    }
  }

  // 5. Construir lista final de player ids
  // Base - vendidos + comprados
  const finalPlayerIds = [
    ...[...basePlayerIds].filter((id) => !soldPlayerIds.has(id)),
    ...boughtPlayerIds,
  ];

  // 6. Fetch de datos de jugadores
  let players: any[] = [];
  if (finalPlayerIds.length > 0) {
    const { data: playersData, error: playersErr } = await supabase
      .from("players")
      .select("id, name, ovr, position, country_name, price, clause, headshot_url")
      .in("id", finalPlayerIds)
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
        headshotUrl: p.headshot_url ?? null,
        newSigning: boughtPlayerIds.has(p.id), // diferenciador de fichaje de mercado
      }));
    }
  }

  // 7. Métricas
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
