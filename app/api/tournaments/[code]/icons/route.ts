import { NextRequest, NextResponse } from "next/server";
import {
  createServerClient,
  verifyMemberToken,
  verifyAdminToken,
} from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/icons ────────────────────────────────────────
// Returns all icon players available for auction.
// Accepts both member and admin tokens.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;

  // Try member token first, then admin token
  const memberAuth = await verifyMemberToken(request, code);
  if (!memberAuth.ok) {
    const adminAuth = await verifyAdminToken(request, code);
    if (!adminAuth.ok) {
      return NextResponse.json(
        { error: "Token inválido." },
        { status: 403 }
      );
    }
  }

  const supabase = createServerClient();

  const { data: iconsRaw } = await supabase
    .from("players")
    .select("id, name, ovr, position, country_name, headshot_url")
    .eq("is_icon", true)
    .order("ovr", { ascending: false });

  const icons = (iconsRaw ?? []).map((p: any) => ({
    id: p.id,
    name: p.name,
    ovr: p.ovr,
    position: p.position,
    nation: p.country_name ?? "—",
    headshotUrl: p.headshot_url ?? null,
  }));

  return NextResponse.json({ icons });
}
