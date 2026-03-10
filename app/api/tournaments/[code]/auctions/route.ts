import { NextRequest, NextResponse } from "next/server";
import {
  createServerClient,
  verifyMemberToken,
  verifyAdminToken,
} from "@/lib/supabase";
import { createBulkNotifications } from "@/lib/notifications";

type Params = { params: Promise<{ code: string }> };

// ─── GET /api/tournaments/[code]/auctions ─────────────────────────────────────
// Returns all auctions for the current market session.

export async function GET(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyMemberToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session) {
    return NextResponse.json({ auctions: [] });
  }

  const sessionId = (session as any).id;

  const { data: auctionsRaw } = await supabase
    .from("icon_auctions")
    .select(
      "id, phase, starts_at, ends_at, min_bid, selected_icon_id, highest_bid, highest_bidder_id, winner_id, final_amount, created_at"
    )
    .eq("session_id", sessionId)
    .order("created_at", { ascending: false });

  if (!auctionsRaw || auctionsRaw.length === 0) {
    return NextResponse.json({ auctions: [] });
  }

  // Gather icon IDs and member IDs for lookups
  const iconIds = [
    ...new Set(
      (auctionsRaw as any[])
        .map((a) => a.selected_icon_id)
        .filter(Boolean)
    ),
  ];
  const memberIds = [
    ...new Set(
      (auctionsRaw as any[])
        .flatMap((a) => [a.highest_bidder_id, a.winner_id])
        .filter(Boolean)
    ),
  ];

  const { data: iconsRaw } = iconIds.length > 0
    ? await supabase
        .from("players")
        .select("id, name, ovr, position, country_name, headshot_url")
        .in("id", iconIds)
    : { data: [] };

  const iconById: Record<string, any> = {};
  for (const p of iconsRaw ?? []) iconById[(p as any).id] = p;

  const { data: membersRaw } = memberIds.length > 0
    ? await supabase
        .from("members")
        .select("id, display_name")
        .in("id", memberIds)
    : { data: [] };

  const memberNameById: Record<string, string> = {};
  for (const m of membersRaw ?? [])
    memberNameById[(m as any).id] = (m as any).display_name;

  // My budget & icon slot
  const { data: myMember } = await supabase
    .from("members")
    .select("budget, icon_slot_used")
    .eq("id", auth.memberId)
    .single();

  const auctions = (auctionsRaw as any[]).map((a) => {
    const icon = iconById[a.selected_icon_id];
    const now = Date.now();
    const endsAt = a.ends_at ? new Date(a.ends_at).getTime() : null;
    const startsAt = a.starts_at ? new Date(a.starts_at).getTime() : null;

    let computedPhase = a.phase;
    if (a.phase === "active" && endsAt && endsAt < now) {
      computedPhase = "finished";
    }
    if (a.phase === "pending" && startsAt && startsAt <= now) {
      computedPhase = "active";
    }

    return {
      id: a.id,
      phase: computedPhase,
      startsAt: a.starts_at,
      endsAt: a.ends_at,
      minBid: a.min_bid,
      highestBid: a.highest_bid ?? 0,
      highestBidderId: a.highest_bidder_id,
      highestBidderName: a.highest_bidder_id
        ? (memberNameById[a.highest_bidder_id] ?? "—")
        : null,
      winnerId: a.winner_id,
      winnerName: a.winner_id
        ? (memberNameById[a.winner_id] ?? "—")
        : null,
      finalAmount: a.final_amount,
      icon: icon
        ? {
            id: icon.id,
            name: icon.name,
            ovr: icon.ovr,
            position: icon.position,
            nation: icon.country_name ?? "—",
            headshotUrl: icon.headshot_url ?? null,
          }
        : null,
      isMyBid: a.highest_bidder_id === auth.memberId,
      timeRemainingMs: endsAt ? Math.max(0, endsAt - now) : null,
    };
  });

  return NextResponse.json({
    auctions,
    myBudget: (myMember as any)?.budget ?? 0,
    myIconSlotUsed: (myMember as any)?.icon_slot_used ?? false,
  });
}

// ─── POST /api/tournaments/[code]/auctions ────────────────────────────────────
// Admin creates a new eBay-style auction.
// Body: { iconId, minBid, durationMinutes? }

export async function POST(request: NextRequest, { params }: Params) {
  const { code } = await params;
  const auth = await verifyAdminToken(request, code);
  if (!auth.ok)
    return NextResponse.json({ error: auth.error }, { status: auth.status });

  const supabase = createServerClient();

  let body: {
    iconId?: string;
    minBid?: number;
    durationMinutes?: number;
  };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "JSON inválido." }, { status: 400 });
  }

  if (!body.iconId) {
    return NextResponse.json(
      { error: "Se requiere iconId." },
      { status: 400 }
    );
  }

  const { data: session } = await supabase
    .from("market_sessions")
    .select("id, status")
    .eq("tournament_id", auth.tournamentId)
    .maybeSingle();

  if (!session || (session as any).status !== "active") {
    return NextResponse.json(
      { error: "El mercado no está activo." },
      { status: 409 }
    );
  }

  // Verify icon exists and is an icon
  const { data: icon } = await supabase
    .from("players")
    .select("id, name, is_icon")
    .eq("id", body.iconId)
    .single();

  if (!icon || !(icon as any).is_icon) {
    return NextResponse.json(
      { error: "Ícono no válido." },
      { status: 422 }
    );
  }

  // Check if this icon was already won in any auction for this session
  const { data: alreadyWon } = await supabase
    .from("icon_auctions")
    .select("id")
    .eq("session_id", (session as any).id)
    .eq("selected_icon_id", body.iconId)
    .not("winner_id", "is", null)
    .limit(1);

  if ((alreadyWon ?? []).length > 0) {
    return NextResponse.json(
      { error: "Este ícono ya fue subastado y ganado." },
      { status: 422 }
    );
  }

  // Check no active auction for this session
  const { data: activeAuction } = await supabase
    .from("icon_auctions")
    .select("id")
    .eq("session_id", (session as any).id)
    .in("phase", ["active", "pending"])
    .limit(1);

  if ((activeAuction ?? []).length > 0) {
    return NextResponse.json(
      { error: "Ya hay una subasta activa o programada." },
      { status: 409 }
    );
  }

  const durationMinutes = body.durationMinutes ?? 120;
  const minBid = body.minBid ?? 0;
  const now = new Date();
  const startsAt = now.toISOString();
  const endsAt = new Date(
    now.getTime() + durationMinutes * 60 * 1000
  ).toISOString();

  // Get next round_num
  const { data: lastAuction } = await supabase
    .from("icon_auctions")
    .select("round_num")
    .eq("session_id", (session as any).id)
    .order("round_num", { ascending: false })
    .limit(1)
    .maybeSingle();

  const roundNum = ((lastAuction as any)?.round_num ?? 0) + 1;

  const { data: auction, error: auctionErr } = await supabase
    .from("icon_auctions")
    .insert({
      session_id: (session as any).id,
      round_num: roundNum,
      phase: "active",
      selected_icon_id: body.iconId,
      starts_at: startsAt,
      ends_at: endsAt,
      min_bid: minBid,
      highest_bid: 0,
      presented_icon_ids: [body.iconId],
    })
    .select("id")
    .single();

  if (auctionErr) {
    return NextResponse.json(
      { error: "Error al crear la subasta." },
      { status: 500 }
    );
  }

  // Notify all members
  const { data: members } = await supabase
    .from("members")
    .select("id")
    .eq("tournament_id", auth.tournamentId);

  await createBulkNotifications(
    supabase,
    auth.tournamentId,
    (members ?? []).map((m: any) => m.id),
    "auction_started",
    "Nueva subasta de ícono",
    `Subasta de ${(icon as any).name} abierta por ${durationMinutes >= 60 ? `${Math.floor(durationMinutes / 60)}h` : `${durationMinutes}min`}. ¡Puja ahora!`,
    {
      auctionId: (auction as any).id,
      iconId: body.iconId,
      iconName: (icon as any).name,
    }
  );

  return NextResponse.json(
    {
      ok: true,
      auctionId: (auction as any).id,
      startsAt,
      endsAt,
    },
    { status: 201 }
  );
}
