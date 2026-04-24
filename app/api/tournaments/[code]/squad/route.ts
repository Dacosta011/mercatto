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
    supabase.from("teams").select("id, name, crest_url").eq("id", myTeamId).single(),
    supabase.from("members").select("budget, budget_reserved").eq("id", auth.memberId).single(),
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

  // 4. Transferencias del mercado activo — calcular pertenencia final
  // Procesamos transfers en orden cronológico para obtener el dueño actual de
  // cada jugador. Solo así se resuelve la cadena A→B→C correctamente.
  const boughtPlayerIds = new Set<string>();
  const soldPlayerIds   = new Set<string>();

  if (tournamentData) {
    const { data: session } = await supabase
      .from("market_sessions")
      .select("id")
      .eq("tournament_id", (tournamentData as any).id)
      .maybeSingle();

    if (session) {
      // Fetch all members + assignments for the tournament so we can map buyer→team
      const { data: allMembers } = await supabase
        .from("members")
        .select("id")
        .eq("tournament_id", (tournamentData as any).id);
      const allMemberIds = (allMembers ?? []).map((m: any) => m.id);

      const { data: allAssignments } = allMemberIds.length > 0
        ? await supabase.from("assignments").select("member_id, team_id").in("member_id", allMemberIds)
        : { data: [] };

      const teamByMember: Record<string, string> = {};
      for (const a of allAssignments ?? []) {
        teamByMember[(a as any).member_id] = (a as any).team_id;
      }

      const { data: transfers } = await supabase
        .from("market_transfers")
        .select("buyer_id, player_id, transfer_type")
        .eq("session_id", (session as any).id)
        .in("transfer_type", ["clause", "offer", "icon_auction", "auto_release"])
        .order("created_at", { ascending: true });

      // Track the effective team for each transferred player.
      // null = player is currently a free agent (after auto_release).
      const currentTeamOfPlayer: Record<string, string | null> = {};
      for (const t of transfers ?? []) {
        if ((t as any).transfer_type === "auto_release") {
          currentTeamOfPlayer[(t as any).player_id] = null;
          continue;
        }
        const buyerTeam = teamByMember[(t as any).buyer_id];
        if (buyerTeam) currentTeamOfPlayer[(t as any).player_id] = buyerTeam;
      }

      for (const [playerId, effectiveTeam] of Object.entries(currentTeamOfPlayer)) {
        if (effectiveTeam === myTeamId && !basePlayerIds.has(playerId)) {
          boughtPlayerIds.add(playerId);
        } else if (effectiveTeam !== myTeamId && basePlayerIds.has(playerId)) {
          // either sold to another team OR auto-released
          soldPlayerIds.add(playerId);
        }
      }
    }
  }

  // 5. Construir lista final de player ids
  const finalPlayerIds = [
    ...[...basePlayerIds].filter((id) => !soldPlayerIds.has(id)),
    ...boughtPlayerIds,
  ];

  // 6. Fetch de datos de jugadores + disciplina en paralelo
  let players: any[] = [];
  if (finalPlayerIds.length > 0) {
    const { data: leagueSession } = await supabase
      .from("league_sessions")
      .select("id, current_matchday")
      .eq("tournament_id", tournamentData ? (tournamentData as any).id : "")
      .maybeSingle();

    const sessionId = leagueSession ? (leagueSession as any).id : null;
    const currentMatchday = leagueSession ? (leagueSession as any).current_matchday : 0;

    const [{ data: playersData, error: playersErr }, { data: disciplineRaw }, { data: suspensionsRaw }] = await Promise.all([
      supabase
        .from("players")
        .select("id, name, ovr, position, country_name, price, clause, headshot_url")
        .in("id", finalPlayerIds)
        .order("ovr", { ascending: false }),
      sessionId
        ? supabase.from("discipline").select("player_id, card_type").eq("session_id", sessionId).eq("member_id", auth.memberId)
        : Promise.resolve({ data: [] }),
      sessionId
        ? supabase.from("suspensions").select("player_id, from_matchday, matches_remaining").eq("session_id", sessionId).eq("member_id", auth.memberId)
        : Promise.resolve({ data: [] }),
    ]);

    const yellowsByPlayer: Record<string, number> = {};
    for (const d of disciplineRaw ?? []) {
      const pid = (d as any).player_id;
      if (!pid) continue;
      if ((d as any).card_type === "yellow") yellowsByPlayer[pid] = (yellowsByPlayer[pid] ?? 0) + 1;
    }

    const suspendedPlayerIds = new Set(
      (suspensionsRaw ?? [])
        .filter((s: any) => s.player_id && s.from_matchday <= currentMatchday && s.from_matchday + s.matches_remaining > currentMatchday)
        .map((s: any) => s.player_id)
    );

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
        newSigning: boughtPlayerIds.has(p.id),
        suspended: suspendedPlayerIds.has(p.id) ? 1 : 0,
        yellowCards: yellowsByPlayer[p.id] ?? 0,
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
      crestUrl: (team as any).crest_url ?? null,
      squadValue,
      budget: (memberData as any)?.budget ?? 0,
      budgetReserved: (memberData as any)?.budget_reserved ?? 0,
    },
    players,
    avgOvr,
  });
}
