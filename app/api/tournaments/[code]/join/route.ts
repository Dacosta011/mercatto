import { NextRequest, NextResponse } from "next/server";
import { createServerClient, hashToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/join ────────────────────────────────────────

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const supabase = createServerClient();

  // Parsear body
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { error: "El cuerpo de la petición no es JSON válido." },
      { status: 400 }
    );
  }

  const { displayName } = body as { displayName?: string };

  if (!displayName || typeof displayName !== "string" || displayName.trim().length === 0) {
    return NextResponse.json(
      { error: "El campo 'displayName' es obligatorio." },
      { status: 422 }
    );
  }

  if (displayName.trim().length > 40) {
    return NextResponse.json(
      { error: "El nombre no puede superar los 40 caracteres." },
      { status: 422 }
    );
  }

  // Verificar que el torneo existe y está en lobby
  const { data: tournament, error: tournamentError } = await supabase
    .from("tournaments")
    .select("id, name, status")
    .eq("code", code.toUpperCase())
    .single();

  if (tournamentError || !tournament) {
    return NextResponse.json(
      { error: "Código de torneo inválido o no encontrado." },
      { status: 404 }
    );
  }

  if (tournament.status !== "lobby") {
    return NextResponse.json(
      { error: "Este torneo ya no acepta nuevos participantes." },
      { status: 409 }
    );
  }

  // Verificar que el nombre no esté ya en uso en este torneo
  const { data: existing } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", tournament.id)
    .ilike("display_name", displayName.trim())
    .maybeSingle();

  if (existing) {
    return NextResponse.json(
      { error: "Ese nombre de jugador ya está en uso en este torneo." },
      { status: 409 }
    );
  }

  // Crear el miembro
  const memberToken = crypto.randomUUID();
  const memberTokenHash = hashToken(memberToken);

  const { data: member, error: memberError } = await supabase
    .from("members")
    .insert({
      tournament_id: tournament.id,
      display_name: displayName.trim(),
      member_token_hash: memberTokenHash,
    })
    .select("id, display_name")
    .single();

  if (memberError || !member) {
    console.error("[POST /api/tournaments/[code]/join]", memberError);
    return NextResponse.json(
      { error: "Error al registrar el participante." },
      { status: 500 }
    );
  }

  return NextResponse.json(
    {
      memberId: member.id,
      displayName: member.display_name,
      memberToken,
      tournamentName: tournament.name,
      code: code.toUpperCase(),
    },
    { status: 201 }
  );
}
