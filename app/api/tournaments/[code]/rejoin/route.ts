import { NextRequest, NextResponse } from "next/server";
import { createServerClient, hashToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;

  let body: any;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { error: "Body inválido." },
      { status: 400 }
    );
  }

  const { token } = body as { token?: string };
  if (!token || typeof token !== "string") {
    return NextResponse.json(
      { error: "Token requerido." },
      { status: 422 }
    );
  }

  const supabase = createServerClient();
  const tokenHash = hashToken(token);

  const { data: member, error: memberErr } = await supabase
    .from("members")
    .select("id, display_name, tournament_id")
    .eq("member_token_hash", tokenHash)
    .single();

  if (memberErr || !member) {
    return NextResponse.json(
      { error: "Enlace inválido o expirado." },
      { status: 403 }
    );
  }

  const { data: tournament, error: tErr } = await supabase
    .from("tournaments")
    .select("id, code, name, status")
    .eq("id", member.tournament_id)
    .single();

  if (tErr || !tournament) {
    return NextResponse.json(
      { error: "Torneo no encontrado." },
      { status: 404 }
    );
  }

  if ((tournament.code as string).toUpperCase() !== code.toUpperCase()) {
    return NextResponse.json(
      { error: "El token no pertenece a este torneo." },
      { status: 403 }
    );
  }

  const { data: assignment } = await supabase
    .from("assignments")
    .select("team_id, teams(name, crest_url)")
    .eq("member_id", member.id)
    .maybeSingle();

  const team = assignment
    ? {
        name: (assignment as any).teams?.name ?? null,
        crestUrl: (assignment as any).teams?.crest_url ?? null,
      }
    : null;

  return NextResponse.json({
    memberId: member.id,
    displayName: member.display_name,
    tournamentName: tournament.name,
    tournamentStatus: tournament.status,
    code: (tournament.code as string).toUpperCase(),
    team,
  });
}
