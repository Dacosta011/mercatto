import { NextRequest, NextResponse } from "next/server";
import { createServerClient, hashToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// POST /api/tournaments/[code]/guest
// Creates a guest member who can view the feed, standings and calendar,
// and interact with the social feed (likes, comments).
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const supabase = createServerClient();

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

  // Verify tournament exists and is in league or complete phase
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

  const status = (tournament as any).status;
  if (status !== "league" && status !== "complete") {
    return NextResponse.json(
      { error: "Solo se puede ingresar como invitado cuando la liga está activa." },
      { status: 409 }
    );
  }

  // Check display name is not taken
  const { data: existing } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", (tournament as any).id)
    .ilike("display_name", displayName.trim())
    .maybeSingle();

  if (existing) {
    return NextResponse.json(
      { error: "Ese nombre ya está en uso en este torneo." },
      { status: 409 }
    );
  }

  // Create guest member (no team assignment — that's what makes them a guest)
  const memberToken = crypto.randomUUID();
  const memberTokenHash = hashToken(memberToken);

  const { data: member, error: memberError } = await supabase
    .from("members")
    .insert({
      tournament_id: (tournament as any).id,
      display_name: displayName.trim(),
      member_token_hash: memberTokenHash,
    })
    .select("id, display_name")
    .single();

  if (memberError || !member) {
    console.error("[POST /api/tournaments/[code]/guest]", memberError);
    return NextResponse.json(
      { error: "Error al registrar el invitado." },
      { status: 500 }
    );
  }

  // Auto-create social profile so the guest can post & comment immediately
  await supabase.from("social_profiles").insert({
    member_id: (member as any).id,
    tournament_id: (tournament as any).id,
    username: displayName.trim(),
  });

  return NextResponse.json(
    {
      memberId: (member as any).id,
      displayName: (member as any).display_name,
      memberToken,
      tournamentName: (tournament as any).name,
      code: code.toUpperCase(),
    },
    { status: 201 }
  );
}
