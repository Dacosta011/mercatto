import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── POST /api/tournaments/[code]/push/subscribe ──────────────────────────────
// Registers a Web Push subscription for the member.
// Body: { endpoint, p256dh, auth }

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const authResult = await verifyMemberToken(request, code);
  if (!authResult.ok)
    return NextResponse.json(
      { error: authResult.error },
      { status: authResult.status }
    );

  const supabase = createServerClient();

  let body: { endpoint?: string; p256dh?: string; auth?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (!body.endpoint || !body.p256dh || !body.auth) {
    return NextResponse.json(
      { error: "Se requieren endpoint, p256dh y auth." },
      { status: 400 }
    );
  }

  await supabase.from("push_subscriptions").upsert(
    {
      member_id: authResult.memberId,
      endpoint: body.endpoint,
      p256dh: body.p256dh,
      auth: body.auth,
    },
    { onConflict: "endpoint" }
  );

  return NextResponse.json({ ok: true });
}

// ─── DELETE /api/tournaments/[code]/push/subscribe ────────────────────────────
// Removes a push subscription.

export async function DELETE(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const authResult = await verifyMemberToken(request, code);
  if (!authResult.ok)
    return NextResponse.json(
      { error: authResult.error },
      { status: authResult.status }
    );

  const supabase = createServerClient();

  let body: { endpoint?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (body.endpoint) {
    await supabase
      .from("push_subscriptions")
      .delete()
      .eq("endpoint", body.endpoint)
      .eq("member_id", authResult.memberId);
  }

  return NextResponse.json({ ok: true });
}
