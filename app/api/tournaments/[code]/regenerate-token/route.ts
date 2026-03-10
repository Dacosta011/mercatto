import { NextRequest, NextResponse } from "next/server";
import { createServerClient, hashToken, verifyMemberToken } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) {
    return NextResponse.json({ error: auth.error }, { status: auth.status });
  }

  const newToken = crypto.randomUUID();
  const newHash = hashToken(newToken);
  const supabase = createServerClient();

  const { error } = await supabase
    .from("members")
    .update({ member_token_hash: newHash })
    .eq("id", auth.memberId);

  if (error) {
    return NextResponse.json(
      { error: "No se pudo regenerar el enlace." },
      { status: 500 }
    );
  }

  return NextResponse.json({ newToken });
}
