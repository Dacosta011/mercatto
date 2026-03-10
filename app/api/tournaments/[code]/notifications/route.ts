import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/notifications ────────────────────────────────
// Returns the member's notifications (paginated).

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();
  const url = new URL(request.url);
  const limit = parseInt(url.searchParams.get("limit") ?? "30", 10);
  const offset = parseInt(url.searchParams.get("offset") ?? "0", 10);

  const { data: notifications, count } = await supabase
    .from("notifications")
    .select("*", { count: "exact" })
    .eq("member_id", auth.memberId)
    .eq("tournament_id", auth.tournamentId)
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  return NextResponse.json({
    notifications: notifications ?? [],
    total: count ?? 0,
  });
}

// ─── PATCH /api/tournaments/[code]/notifications ──────────────────────────────
// Mark notifications as read.
// Body: { ids: string[] } or { all: true }

export async function PATCH(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { ids?: string[]; all?: boolean };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (body.all) {
    await supabase
      .from("notifications")
      .update({ read: true })
      .eq("member_id", auth.memberId)
      .eq("tournament_id", auth.tournamentId)
      .eq("read", false);
  } else if (body.ids && body.ids.length > 0) {
    await supabase
      .from("notifications")
      .update({ read: true })
      .in("id", body.ids)
      .eq("member_id", auth.memberId);
  }

  return NextResponse.json({ ok: true });
}
