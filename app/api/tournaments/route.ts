import { NextRequest, NextResponse } from "next/server";
import { createServerClient, hashToken } from "@/lib/supabase";

// ─── Helpers ──────────────────────────────────────────────────────────────────

function randomChars(length: number, chars: string): string {
  return Array.from(
    { length },
    () => chars[Math.floor(Math.random() * chars.length)]
  ).join("");
}

function generateCode(): string {
  const A = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
  const N = "0123456789";
  return `${randomChars(3, A)}-${randomChars(4, N)}-${randomChars(3, A)}`;
}

// ─── GET /api/tournaments ─────────────────────────────────────────────────────

export async function GET() {
  const supabase = createServerClient();

  const { data, error } = await supabase
    .from("tournaments")
    .select("id, name, code, status, created_at")
    .order("created_at", { ascending: false });

  if (error) {
    console.error("[GET /api/tournaments]", error);
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json(data);
}

// ─── POST /api/tournaments ────────────────────────────────────────────────────

export async function POST(request: NextRequest) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { error: "El cuerpo de la petición no es JSON válido." },
      { status: 400 }
    );
  }

  const { name, displayName, rerolls } = body as {
    name?: string;
    displayName?: string;
    rerolls?: number;
  };

  // Validación
  if (!name || typeof name !== "string" || name.trim().length === 0) {
    return NextResponse.json(
      { error: "El campo 'name' es obligatorio." },
      { status: 422 }
    );
  }
  if (name.trim().length > 80) {
    return NextResponse.json(
      { error: "El nombre del torneo no puede superar los 80 caracteres." },
      { status: 422 }
    );
  }
  if (!displayName || typeof displayName !== "string" || displayName.trim().length === 0) {
    return NextResponse.json(
      { error: "El campo 'displayName' es obligatorio." },
      { status: 422 }
    );
  }
  if (displayName.trim().length > 40) {
    return NextResponse.json(
      { error: "El nombre de jugador no puede superar los 40 caracteres." },
      { status: 422 }
    );
  }

  const supabase = createServerClient();

  // Generar código único
  let code = generateCode();
  let attempts = 0;
  while (attempts < 5) {
    const { data: existing } = await supabase
      .from("tournaments")
      .select("id")
      .eq("code", code)
      .maybeSingle();
    if (!existing) break;
    code = generateCode();
    attempts++;
  }

  // Tokens
  const adminToken = crypto.randomUUID();
  const adminTokenHash = hashToken(adminToken);
  const memberToken = crypto.randomUUID();
  const memberTokenHash = hashToken(memberToken);

  const rerollsAllowed = typeof rerolls === "number"
    ? Math.min(5, Math.max(0, Math.floor(rerolls)))
    : 1;

  // 1. Crear torneo
  const { data: tournament, error: tournamentError } = await supabase
    .from("tournaments")
    .insert({
      name: name.trim(),
      code,
      admin_token_hash: adminTokenHash,
      status: "lobby",
      rerolls_allowed: rerollsAllowed,
    })
    .select("id, name, code, status, created_at")
    .single();

  if (tournamentError || !tournament) {
    console.error("[POST /api/tournaments] tournament:", tournamentError);
    return NextResponse.json(
      { error: "Error al crear el torneo." },
      { status: 500 }
    );
  }

  // 2. Registrar al admin como participante
  const { data: member, error: memberError } = await supabase
    .from("members")
    .insert({
      tournament_id: tournament.id,
      display_name: displayName.trim(),
      member_token_hash: memberTokenHash,
    })
    .select("id")
    .single();

  if (memberError || !member) {
    console.error("[POST /api/tournaments] member:", memberError);
    // El torneo ya se creó — lo devolvemos igual pero sin memberId
    return NextResponse.json(
      {
        id: tournament.id,
        name: tournament.name,
        code: tournament.code,
        status: tournament.status,
        createdAt: tournament.created_at,
        adminToken,
        memberToken: null,
        memberId: null,
        rerolls: rerollsAllowed,
      },
      { status: 201 }
    );
  }

  return NextResponse.json(
    {
      id: tournament.id,
      name: tournament.name,
      code: tournament.code,
      status: tournament.status,
      createdAt: tournament.created_at,
      adminToken,
      memberToken,
      memberId: member.id,
      rerolls: rerollsAllowed,
    },
    { status: 201 }
  );
}
