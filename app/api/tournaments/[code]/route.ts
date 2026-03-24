import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyAdminToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code] ──────────────────────────────────────────────

export async function GET(_req: NextRequest, { params }: Params) {
  const { code } = await params;
  const supabase = createServerClient();

  // 1. Buscar el torneo
  const { data: tournament, error: tournamentError } = await supabase
    .from("tournaments")
    .select("id, name, code, status, created_at, max_transfers, clause_protection_limit")
    .eq("code", code.toUpperCase())
    .single();

  if (tournamentError || !tournament) {
    console.error("[GET /api/tournaments/[code]] tournament:", tournamentError);
    return NextResponse.json(
      { error: "Torneo no encontrado." },
      { status: 404 }
    );
  }

  // 2. Buscar los miembros del torneo (con budget, ya que les pertenece a ellos)
  const { data: members, error: membersError } = await supabase
    .from("members")
    .select("id, display_name, budget")
    .eq("tournament_id", tournament.id);

  if (membersError) {
    console.error("[GET /api/tournaments/[code]] members:", membersError);
    return NextResponse.json(
      { error: "Error al cargar participantes." },
      { status: 500 }
    );
  }

  // 3. Buscar asignaciones + equipo para cada miembro
  const memberIds = (members ?? []).map((m: any) => m.id);
  let assignmentsMap: Record<string, { name: string; crestUrl: string | null }> = {};

  if (memberIds.length > 0) {
    const { data: assignments, error: assignmentsError } = await supabase
      .from("assignments")
      .select("member_id, team_id")
      .in("member_id", memberIds)
      .eq("tournament_id", tournament.id);

    if (assignmentsError) {
      console.error("[GET /api/tournaments/[code]] assignments:", assignmentsError);
    }

    if (assignments && assignments.length > 0) {
      // Buscar los equipos por sus IDs
      const teamIds = assignments.map((a: any) => a.team_id).filter(Boolean);
      const { data: teamsData } = await supabase
        .from("teams")
        .select("id, name, crest_url")
        .in("id", teamIds);

      const teamsById: Record<string, any> = {};
      for (const t of teamsData ?? []) {
        teamsById[(t as any).id] = t;
      }

      for (const a of assignments as any[]) {
        const team = teamsById[a.team_id];
        if (team) {
          assignmentsMap[a.member_id] = { name: team.name, crestUrl: team.crest_url ?? null };
        }
      }
    }
  }

  // 4. Combinar
  const membersWithTeams = (members ?? []).map((m: any) => {
    const t = assignmentsMap[m.id] ?? null;
    return {
      id: m.id,
      displayName: m.display_name,
      budget: m.budget ?? null,
      team: t ? { name: t.name, crestUrl: t.crestUrl ?? null } : null,
    };
  });

  return NextResponse.json({
    id: tournament.id,
    name: tournament.name,
    code: tournament.code,
    status: tournament.status,
    createdAt: tournament.created_at,
    maxTransfers: (tournament as any).max_transfers ?? 3,
    clauseProtection: (tournament as any).clause_protection_limit ?? 1,
    members: membersWithTeams,
  });
}

// ─── PATCH /api/tournaments/[code] — cambiar status (admin only) ──────────────

const VALID_STATUSES = ["lobby", "draft", "market", "complete"] as const;

export async function PATCH(request: NextRequest, { params }: Params) {
  const { code } = await params;

  const auth = await verifyAdminToken(request, code);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  let body: unknown;
  try { body = await request.json(); } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  const { status } = body as { status?: string };
  if (!status || !VALID_STATUSES.includes(status as any)) {
    return NextResponse.json(
      { error: `Status debe ser uno de: ${VALID_STATUSES.join(", ")}.` },
      { status: 422 }
    );
  }

  const supabase = createServerClient();
  const { data, error } = await supabase
    .from("tournaments")
    .update({ status })
    .eq("id", auth.tournamentId)
    .select("id, name, code, status")
    .single();

  if (error || !data) {
    console.error("[PATCH tournaments]", error);
    return NextResponse.json({ error: "Error al actualizar el torneo." }, { status: 500 });
  }

  return NextResponse.json(data);
}
