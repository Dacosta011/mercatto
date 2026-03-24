import { NextRequest, NextResponse } from "next/server";
import { verifyMemberToken, createServerClient } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/social/profile ───────────────────────────────
// Returns ALL social profiles for this member in this tournament.
// Response: { profiles: SocialProfile[], profile: SocialProfile | null }
export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();
  const { data, error } = await supabase
    .from("social_profiles")
    .select("id, username, photo_url, verified")
    .eq("member_id", auth.memberId)
    .eq("tournament_id", auth.tournamentId)
    .order("created_at", { ascending: true });

  if (error) {
    return NextResponse.json({ error: "Error fetching profiles" }, { status: 500 });
  }

  const profiles = data ?? [];

  // Keep backwards-compat: also return `profile` (first one) for old callers
  return NextResponse.json({
    profiles,
    profile: profiles[0] ?? null,
  });
}

// ─── POST /api/tournaments/[code]/social/profile ──────────────────────────────
// Creates a NEW profile for this member (multi-account support).
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  const { username, photo_url } = body as { username?: string; photo_url?: string | null };

  if (!username || username.trim().length < 2) {
    return NextResponse.json(
      { error: "El nombre de usuario debe tener al menos 2 caracteres" },
      { status: 400 }
    );
  }

  const supabase = createServerClient();

  // Max 5 profiles per member per tournament
  const { count } = await supabase
    .from("social_profiles")
    .select("id", { count: "exact", head: true })
    .eq("member_id", auth.memberId)
    .eq("tournament_id", auth.tournamentId);

  if ((count ?? 0) >= 5) {
    return NextResponse.json(
      { error: "Máximo 5 perfiles por torneo" },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from("social_profiles")
    .insert({
      member_id: auth.memberId,
      tournament_id: auth.tournamentId,
      username: username.trim(),
      photo_url: photo_url ?? null,
    })
    .select("id, username, photo_url, verified")
    .single();

  if (error) return NextResponse.json({ error: "Error creando perfil" }, { status: 500 });

  return NextResponse.json({ profile: data }, { status: 201 });
}

// ─── PUT /api/tournaments/[code]/social/profile ───────────────────────────────
// Updates an existing profile by id. Pass { id, username, photo_url } in body.
// If no id provided, updates the first (oldest) profile — backwards compat.
export async function PUT(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  const { id, username, photo_url } = body as {
    id?: string;
    username?: string;
    photo_url?: string | null;
  };

  if (!username || username.trim().length < 2) {
    return NextResponse.json(
      { error: "El nombre de usuario debe tener al menos 2 caracteres" },
      { status: 400 }
    );
  }

  const supabase = createServerClient();

  let query = supabase
    .from("social_profiles")
    .update({
      username: username.trim(),
      photo_url: photo_url ?? null,
      updated_at: new Date().toISOString(),
    })
    .eq("member_id", auth.memberId)
    .eq("tournament_id", auth.tournamentId);

  if (id) {
    query = query.eq("id", id);
  }

  const { data, error } = await query
    .select("id, username, photo_url, verified")
    .single();

  if (error) return NextResponse.json({ error: "Error guardando perfil" }, { status: 500 });

  return NextResponse.json({ profile: data });
}
