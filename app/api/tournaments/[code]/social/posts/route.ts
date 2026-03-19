import { NextRequest, NextResponse } from "next/server";
import { verifyMemberToken, createServerClient } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/social/posts ─────────────────────────────────
// Returns the 50 most recent top-level posts for the tournament, enriched with
// author profile, like data, and reply count. Optionally returns replies for a
// specific post via ?parent_id=<postId>.
export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { searchParams } = new URL(request.url);
  const parentId = searchParams.get("parent_id");

  const query = supabase
    .from("posts")
    .select("id, content, image_url, created_at, member_id, parent_id")
    .eq("tournament_id", auth.tournamentId)
    .order("created_at", { ascending: parentId ? true : false })
    .limit(50);

  if (parentId) {
    query.eq("parent_id", parentId);
  } else {
    query.is("parent_id", null);
  }

  const { data: posts, error } = await query;

  if (error) return NextResponse.json({ error: "Error fetching posts" }, { status: 500 });

  const postList = posts ?? [];
  if (postList.length === 0) return NextResponse.json({ posts: [] });

  // Fetch social profiles for all authors in one query
  const memberIds = [...new Set(postList.map((p) => p.member_id as string))];
  const { data: profiles } = await supabase
    .from("social_profiles")
    .select("member_id, username, photo_url")
    .in("member_id", memberIds);

  const profileMap: Record<string, { username: string; photo_url: string | null }> = {};
  for (const p of profiles ?? []) profileMap[p.member_id] = p;

  // Fetch all likes for these posts
  const postIds = postList.map((p) => p.id as string);
  const { data: likes } = await supabase
    .from("post_likes")
    .select("post_id, member_id")
    .in("post_id", postIds);

  const likeMap: Record<string, { count: number; likedByMe: boolean }> = {};
  for (const like of likes ?? []) {
    if (!likeMap[like.post_id]) likeMap[like.post_id] = { count: 0, likedByMe: false };
    likeMap[like.post_id].count++;
    if (like.member_id === auth.memberId) likeMap[like.post_id].likedByMe = true;
  }

  // Fetch reply counts for top-level posts
  const replyCountMap: Record<string, number> = {};
  if (!parentId && postIds.length > 0) {
    const { data: replyCounts } = await supabase
      .from("posts")
      .select("parent_id")
      .in("parent_id", postIds);
    for (const r of replyCounts ?? []) {
      replyCountMap[r.parent_id] = (replyCountMap[r.parent_id] ?? 0) + 1;
    }
  }

  const enriched = postList.map((post) => ({
    id: post.id,
    content: post.content,
    image_url: post.image_url,
    created_at: post.created_at,
    parent_id: post.parent_id ?? null,
    isMe: post.member_id === auth.memberId,
    author: profileMap[post.member_id] ?? null,
    likeCount: likeMap[post.id]?.count ?? 0,
    likedByMe: likeMap[post.id]?.likedByMe ?? false,
    replyCount: replyCountMap[post.id] ?? 0,
  }));

  return NextResponse.json({ posts: enriched });
}

// ─── POST /api/tournaments/[code]/social/posts ────────────────────────────────
// Creates a new post or reply. Available to any member with a social profile.
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Verify social profile exists
  const { data: profile } = await supabase
    .from("social_profiles")
    .select("id, username, photo_url")
    .eq("member_id", auth.memberId)
    .eq("tournament_id", auth.tournamentId)
    .single();

  if (!profile) {
    return NextResponse.json(
      { error: "Configura tu perfil social primero" },
      { status: 400 }
    );
  }

  const body = await request.json();
  const { content, image_url, parent_id } = body as {
    content?: string;
    image_url?: string;
    parent_id?: string;
  };

  const trimmedContent = content?.trim() || null;
  if (!trimmedContent && !image_url) {
    return NextResponse.json({ error: "El post debe tener texto o imagen" }, { status: 400 });
  }

  // If replying, verify parent post belongs to the same tournament
  if (parent_id) {
    const { data: parentPost } = await supabase
      .from("posts")
      .select("id")
      .eq("id", parent_id)
      .eq("tournament_id", auth.tournamentId)
      .single();
    if (!parentPost) {
      return NextResponse.json({ error: "Post padre no encontrado" }, { status: 404 });
    }
  }

  const { data: post, error } = await supabase
    .from("posts")
    .insert({
      member_id: auth.memberId,
      tournament_id: auth.tournamentId,
      content: trimmedContent,
      image_url: image_url || null,
      parent_id: parent_id || null,
    })
    .select("id, content, image_url, created_at, member_id, parent_id")
    .single();

  if (error) return NextResponse.json({ error: "Error creando post" }, { status: 500 });

  return NextResponse.json(
    {
      post: {
        id: post.id,
        content: post.content,
        image_url: post.image_url,
        created_at: post.created_at,
        parent_id: post.parent_id ?? null,
        isMe: true,
        author: { username: profile.username, photo_url: profile.photo_url },
        likeCount: 0,
        likedByMe: false,
        replyCount: 0,
      },
    },
    { status: 201 }
  );
}
