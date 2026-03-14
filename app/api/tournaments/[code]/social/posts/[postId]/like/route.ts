import { NextRequest, NextResponse } from "next/server";
import { verifyMemberToken, createServerClient } from "@/lib/supabase";

type Params = { params: Promise<{ code: string; postId: string }> };

// ─── POST /api/tournaments/[code]/social/posts/[postId]/like ─────────────────
// Toggles a like on a post. Returns { liked: boolean, likeCount: number }.
export async function POST(request: NextRequest, { params }: Params) {
  const { code, postId } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Verify post belongs to this tournament
  const { data: post } = await supabase
    .from("posts")
    .select("id")
    .eq("id", postId)
    .eq("tournament_id", auth.tournamentId)
    .single();

  if (!post) return NextResponse.json({ error: "Post no encontrado" }, { status: 404 });

  // Check if already liked
  const { data: existing } = await supabase
    .from("post_likes")
    .select("id")
    .eq("post_id", postId)
    .eq("member_id", auth.memberId)
    .single();

  if (existing) {
    // Unlike
    await supabase.from("post_likes").delete().eq("id", existing.id);
  } else {
    // Like
    await supabase.from("post_likes").insert({ post_id: postId, member_id: auth.memberId });
  }

  // Return updated like count
  const { count } = await supabase
    .from("post_likes")
    .select("id", { count: "exact", head: true })
    .eq("post_id", postId);

  return NextResponse.json({ liked: !existing, likeCount: count ?? 0 });
}
