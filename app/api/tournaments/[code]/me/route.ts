import { NextRequest, NextResponse } from "next/server";
import { verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/me ──────────────────────────────────────────
// Lightweight membership check. Returns 200 if the bearer token is valid for
// this tournament, 401/403 if not. Used by PhaseRedirectGuard to detect kicks.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }
  return NextResponse.json({ ok: true, memberId: auth.memberId });
}
