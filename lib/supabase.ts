import { createClient } from "@supabase/supabase-js";

// ─── Tipos que reflejan el esquema de Supabase ────────────────────────────────

export interface DbTournament {
  id: string;
  name: string;
  code: string;
  admin_token_hash: string;
  status: "lobby" | "draft" | "market" | "complete";
  created_at: string;
}

export interface DbMember {
  id: string;
  tournament_id: string;
  display_name: string;
  member_token_hash: string;
  joined_at: string;
}

export interface DbTeam {
  id: string;
  name: string;
  squad_value: number;
  budget: number;
}

export interface DbAssignment {
  id: string;
  tournament_id: string;
  member_id: string;
  team_id: string;
  assigned_at: string;
}

export interface DbPlayer {
  id: string;
  name: string;
  position: string;
  club: string;
  ovr: number;
  price: number;
  clause: number;
  nationality: string;
}

export interface DbListing {
  id: string;
  tournament_id: string;
  seller_member_id: string;
  player_id: string;
  asking_price: number;
  status: "open" | "sold" | "cancelled";
  created_at: string;
}

// ─── Cliente Supabase ─────────────────────────────────────────────────────────
// Usa la anon key. Los tipos de respuesta se castean en cada route handler
// para evitar conflictos con el generador de tipos interno de Supabase.

export function createServerClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) {
    throw new Error(
      "Faltan NEXT_PUBLIC_SUPABASE_URL o NEXT_PUBLIC_SUPABASE_ANON_KEY en .env.local"
    );
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return createClient<any>(url, key);
}

// ─── Verificar member token contra la DB ─────────────────────────────────────

export async function verifyMemberToken(
  request: Request,
  tournamentCode: string
): Promise<
  | { ok: true; memberId: string; tournamentId: string }
  | { ok: false; status: number; error: string }
> {
  const authHeader = request.headers.get("Authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;

  if (!token) {
    return { ok: false, status: 401, error: "Se requiere el token de miembro." };
  }

  const supabase = createServerClient();
  const tokenHash = hashToken(token);

  // 1) Buscar el miembro por hash
  const { data: member, error: memberErr } = await supabase
    .from("members")
    .select("id, tournament_id")
    .eq("member_token_hash", tokenHash)
    .single();

  if (memberErr || !member) {
    return { ok: false, status: 403, error: "Token de miembro incorrecto." };
  }

  // 2) Verificar que el torneo corresponde al code del URL
  const { data: tournament, error: tErr } = await supabase
    .from("tournaments")
    .select("code")
    .eq("id", member.tournament_id)
    .single();

  if (tErr || !tournament) {
    return { ok: false, status: 403, error: "Torneo no encontrado." };
  }

  if ((tournament.code as string).toUpperCase() !== tournamentCode.toUpperCase()) {
    return { ok: false, status: 403, error: "Token no pertenece a este torneo." };
  }

  return { ok: true, memberId: member.id as string, tournamentId: member.tournament_id as string };
}

// ─── Verificar admin token contra la DB ──────────────────────────────────────
// Extrae el Bearer token del header Authorization y compara el hash con la DB.

export async function verifyAdminToken(
  request: Request,
  tournamentCode: string
): Promise<{ ok: true; tournamentId: string } | { ok: false; status: number; error: string }> {
  const authHeader = request.headers.get("Authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : null;

  if (!token) {
    return { ok: false, status: 401, error: "Se requiere el token de administrador." };
  }

  const supabase = createServerClient();
  const { data, error } = await supabase
    .from("tournaments")
    .select("id, admin_token_hash")
    .eq("code", tournamentCode.toUpperCase())
    .single();

  if (error || !data) {
    return { ok: false, status: 404, error: "Torneo no encontrado." };
  }

  const tokenHash = hashToken(token);
  if (tokenHash !== data.admin_token_hash) {
    return { ok: false, status: 403, error: "Token de administrador incorrecto." };
  }

  return { ok: true, tournamentId: data.id };
}

// ─── Helper para hashear tokens ───────────────────────────────────────────────
// El token RAW se entrega al usuario y nunca se guarda.
// En la DB solo vive el hash SHA-256.

import { createHash } from "crypto";

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}
