import { NextRequest, NextResponse } from "next/server";
import { createServerClient, verifyMemberToken } from "@/lib/supabase";
import { createBulkNotifications } from "@/lib/notifications";

type Params = { params: Promise<{ code: string; auctionId: string }> };

const DEFAULT_BIDDING_MINUTES = 30;

// ─── POST /api/tournaments/[code]/auctions/[auctionId]/vote ───────────────────
// Member votes for an icon in the voting phase.
// Body: { iconId }

export async function POST(request: NextRequest, { params }: Params) {
  const { code, auctionId } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: { iconId?: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (!body.iconId) {
    return NextResponse.json({ error: "Se requiere iconId." }, { status: 400 });
  }

  const { data: auction } = await supabase
    .from("icon_auctions")
    .select("*")
    .eq("id", auctionId)
    .maybeSingle();

  if (!auction) {
    return NextResponse.json({ error: "Subasta no encontrada." }, { status: 404 });
  }

  const a = auction as any;

  if (a.phase !== "voting") {
    return NextResponse.json(
      { error: "La subasta no está en fase de votación." },
      { status: 409 }
    );
  }

  // Verify the icon is a valid candidate
  const candidates: string[] = a.candidate_ids ?? [];
  if (!candidates.includes(body.iconId)) {
    return NextResponse.json(
      { error: "Este ícono no es un candidato válido." },
      { status: 422 }
    );
  }

  // Upsert vote (one vote per member per auction)
  const { error: voteErr } = await supabase
    .from("icon_votes")
    .upsert(
      {
        auction_id: auctionId,
        member_id: auth.memberId,
        icon_id: body.iconId,
      },
      { onConflict: "auction_id,member_id" }
    );

  if (voteErr) {
    return NextResponse.json({ error: "Error al registrar voto." }, { status: 500 });
  }

  // Check if majority reached
  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  const totalMembers = (members ?? []).length;

  const { data: allVotes } = await supabase
    .from("icon_votes")
    .select("icon_id")
    .eq("auction_id", auctionId);

  const voteCounts: Record<string, number> = {};
  for (const v of allVotes ?? []) {
    const iid = (v as any).icon_id;
    voteCounts[iid] = (voteCounts[iid] ?? 0) + 1;
  }

  const majority = Math.ceil(totalMembers / 2);
  let winningIconId: string | null = null;

  for (const [iconId, count] of Object.entries(voteCounts)) {
    if (count >= majority) {
      winningIconId = iconId;
      break;
    }
  }

  // Also check if everyone voted (even without strict majority, pick the most voted)
  const totalVotes = (allVotes ?? []).length;
  if (!winningIconId && totalVotes >= totalMembers) {
    let maxCount = 0;
    for (const [iconId, count] of Object.entries(voteCounts)) {
      if (count > maxCount) {
        maxCount = count;
        winningIconId = iconId;
      }
    }
  }

  if (winningIconId) {
    await startBiddingPhase(supabase, a, winningIconId, auth.tournamentId);
    return NextResponse.json({ ok: true, voted: true, biddingStarted: true });
  }

  return NextResponse.json({
    ok: true,
    voted: true,
    biddingStarted: false,
    votesCount: totalVotes,
    totalMembers,
  });
}

async function startBiddingPhase(
  supabase: any,
  auction: any,
  iconId: string,
  tournamentId: string
) {
  const now = new Date();
  const endsAt = new Date(now.getTime() + DEFAULT_BIDDING_MINUTES * 60 * 1000).toISOString();

  await supabase
    .from("icon_auctions")
    .update({
      phase: "active",
      selected_icon_id: iconId,
      starts_at: now.toISOString(),
      ends_at: endsAt,
    })
    .eq("id", auction.id);

  const { data: iconData } = await supabase
    .from("players")
    .select("name")
    .eq("id", iconId)
    .single();

  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", tournamentId);

  await createBulkNotifications(
    supabase,
    tournamentId,
    (members ?? []).map((m: any) => m.id),
    "auction_started",
    "¡Subasta iniciada!",
    `${(iconData as any)?.name ?? "Un ícono"} fue elegido. ¡Puja ahora! Tienes 2h.`,
    { auctionId: auction.id, iconId, iconName: (iconData as any)?.name }
  );
}
