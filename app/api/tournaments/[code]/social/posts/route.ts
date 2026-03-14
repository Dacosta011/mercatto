import { NextRequest, NextResponse } from "next/server";
import { verifyMemberToken, createServerClient } from "@/lib/supabase";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/social/posts ─────────────────────────────────
// Returns the 50 most recent posts for the tournament, enriched with author
// profile and like data.
export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: posts, error } = await supabase
    .from("posts")
    .select("id, content, image_url, created_at, member_id")
    .eq("tournament_id", auth.tournamentId)
    .order("created_at", { ascending: false })
    .limit(50);

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

  const enriched = postList.map((post) => ({
    id: post.id,
    content: post.content,
    image_url: post.image_url,
    created_at: post.created_at,
    isMe: post.member_id === auth.memberId,
    author: profileMap[post.member_id] ?? null,
    likeCount: likeMap[post.id]?.count ?? 0,
    likedByMe: likeMap[post.id]?.likedByMe ?? false,
  }));

  return NextResponse.json({ posts: enriched });
}

// ─── POST /api/tournaments/[code]/social/posts ────────────────────────────────
// Creates a new post. Requires the tournament to be in "league" status and the
// member to have a social profile set up.
export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok) return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  // Verify league phase
  const { data: tournament } = await supabase
    .from("tournaments")
    .select("status")
    .eq("id", auth.tournamentId)
    .single();

  if (tournament?.status !== "league") {
    return NextResponse.json(
      { error: "El feed solo está disponible durante la liga" },
      { status: 403 }
    );
  }

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
  const { content, image_url } = body as { content?: string; image_url?: string };

  const trimmedContent = content?.trim() || null;
  if (!trimmedContent && !image_url) {
    return NextResponse.json({ error: "El post debe tener texto o imagen" }, { status: 400 });
  }

  const { data: post, error } = await supabase
    .from("posts")
    .insert({
      member_id: auth.memberId,
      tournament_id: auth.tournamentId,
      content: trimmedContent,
      image_url: image_url || null,
    })
    .select("id, content, image_url, created_at, member_id")
    .single();

  if (error) return NextResponse.json({ error: "Error creando post" }, { status: 500 });

  return NextResponse.json(
    {
      post: {
        id: post.id,
        content: post.content,
        image_url: post.image_url,
        created_at: post.created_at,
        isMe: true,
        author: { username: profile.username, photo_url: profile.photo_url },
        likeCount: 0,
        likedByMe: false,
      },
    },
    { status: 201 }
  );
}
