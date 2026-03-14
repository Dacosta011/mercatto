import { NextRequest, NextResponse } from "next/server";
import { verifyMemberToken, createServerClient } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/social/profile ───────────────────────────────
// Returns the current member's social profile for this tournament.
export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();
  const { data, error } = await supabase
    .from("social_profiles")
    .select("id, username, photo_url")
    .eq("member_id", auth.memberId)
    .eq("tournament_id", auth.tournamentId)
    .single();

  if (error && error.code !== "PGRST116") {
    return NextResponse.json({ error: "Error fetching profile" }, { status: 500 });
  }

  return NextResponse.json({ profile: data ?? null });
}

// ─── PUT /api/tournaments/[code]/social/profile ───────────────────────────────
// Creates or updates the member's social profile (upsert).
export async function PUT(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const body = await request.json();
  const { username, photo_url } = body as { username?: string; photo_url?: string | null };

  if (!username || username.trim().length < 2) {
    return NextResponse.json({ error: "El nombre de usuario debe tener al menos 2 caracteres" }, { status: 400 });
  }

  const supabase = createServerClient();
  const { data, error } = await supabase
    .from("social_profiles")
    .upsert(
      {
        member_id: auth.memberId,
        tournament_id: auth.tournamentId,
        username: username.trim(),
        photo_url: photo_url ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "member_id,tournament_id" }
    )
    .select("id, username, photo_url")
    .single();

  if (error) return NextResponse.json({ error: "Error guardando perfil" }, { status: 500 });

  return NextResponse.json({ profile: data });
}
