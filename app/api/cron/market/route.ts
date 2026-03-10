import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";
import { createNotification, createBulkNotifications } from "@/lib/notifications";

// ─── GET /api/cron/market ─────────────────────────────────────────────────────
// Called periodically (every 1-2 min) to handle:
// 1. Expire overdue offers
// 2. Auto-close expired markets
// 3. Send "market closing soon" warnings
// Protected by CRON_SECRET header.

export async function GET(request: NextRequest) {
  const secret = request.headers.get("x-cron-secret");
  if (secret !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const supabase = createServerClient();
  const now = new Date().toISOString();

  // ── 1. Expire overdue offers ──────────────────────────────────────────────
  const { data: expiredOffers } = await supabase
    .from("market_offers")
    .select("id, buyer_id, seller_id, player_id, session_id")
    .eq("status", "pending")
    .lt("expires_at", now);

  if (expiredOffers && expiredOffers.length > 0) {
    const expiredIds = expiredOffers.map((o: any) => o.id);

    await supabase
      .from("market_offers")
      .update({ status: "expired", responded_at: now })
      .in("id", expiredIds);

    // Find tournament_id for notifications
    const sessionIds = [...new Set(expiredOffers.map((o: any) => o.session_id))];
    const { data: sessions } = await supabase
      .from("market_sessions")
      .select("id, tournament_id")
      .in("id", sessionIds);

    const tournamentBySession: Record<string, string> = {};
    for (const s of sessions ?? []) {
      tournamentBySession[(s as any).id] = (s as any).tournament_id;
    }

    const playerIds = [...new Set(expiredOffers.map((o: any) => o.player_id))];
    const { data: players } = playerIds.length > 0
      ? await supabase.from("players").select("id, name").in("id", playerIds)
      : { data: [] };
    const playerNameById: Record<string, string> = {};
    for (const p of players ?? []) playerNameById[(p as any).id] = (p as any).name;

    for (const o of expiredOffers) {
      const tid = tournamentBySession[o.session_id];
      if (!tid) continue;

      await createNotification({
        supabase,
        memberId: o.buyer_id,
        tournamentId: tid,
        type: "offer_expired",
        title: "Oferta expirada",
        body: `Tu oferta por ${playerNameById[o.player_id] ?? "un jugador"} ha expirado sin respuesta.`,
        metadata: { offerId: o.id, playerId: o.player_id },
      });
    }
  }

  // ── 2. Auto-close expired markets ─────────────────────────────────────────
  const { data: expiredSessions } = await supabase
    .from("market_sessions")
    .select("id, tournament_id, closes_at")
    .eq("status", "active")
    .lt("closes_at", now);

  for (const es of expiredSessions ?? []) {
    const sid = (es as any).id;
    const tid = (es as any).tournament_id;

    // Expire remaining pending offers
    await supabase
      .from("market_offers")
      .update({ status: "expired", responded_at: now })
      .eq("session_id", sid)
      .eq("status", "pending");

    // Close active auctions without winner
    await supabase
      .from("icon_auctions")
      .update({ phase: "finished", ends_at: now })
      .eq("session_id", sid)
      .eq("phase", "active");

    // Close market
    await supabase
      .from("market_sessions")
      .update({ status: "finished", finished_at: now })
      .eq("id", sid);

    await supabase
      .from("tournaments")
      .update({ status: "lobby" })
      .eq("id", tid);

    const { data: members } = await supabase
      .from("members")
      .select("id")
      .eq("tournament_id", tid);

    await createBulkNotifications(
      supabase,
      tid,
      (members ?? []).map((m: any) => m.id),
      "market_closed",
      "Mercado cerrado",
      "El tiempo del mercado ha terminado. Los fichajes se han finalizado."
    );
  }

  // ── 3. Send "closing soon" warnings ───────────────────────────────────────
  const twoHoursLater = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString();
  const thirtyMinLater = new Date(Date.now() + 30 * 60 * 1000).toISOString();

  // 2-hour warning
  const { data: closingSoon2h } = await supabase
    .from("market_sessions")
    .select("id, tournament_id, closes_at")
    .eq("status", "active")
    .gt("closes_at", now)
    .lt("closes_at", twoHoursLater);

  for (const cs of closingSoon2h ?? []) {
    const tid = (cs as any).tournament_id;
    const closesAt = new Date((cs as any).closes_at);
    const minLeft = Math.round((closesAt.getTime() - Date.now()) / 60000);

    // Only send if between 115-125 min remaining (avoid duplicate warnings)
    if (minLeft > 115 && minLeft <= 125) {
      const { data: members } = await supabase
        .from("members")
        .select("id")
        .eq("tournament_id", tid);

      await createBulkNotifications(
        supabase,
        tid,
        (members ?? []).map((m: any) => m.id),
        "market_closing",
        "Mercado cierra pronto",
        `El mercado cierra en ~${minLeft} minutos. ¡Últimas oportunidades!`
      );
    }
  }

  // 30-min warning
  const { data: closingSoon30m } = await supabase
    .from("market_sessions")
    .select("id, tournament_id, closes_at")
    .eq("status", "active")
    .gt("closes_at", now)
    .lt("closes_at", thirtyMinLater);

  for (const cs of closingSoon30m ?? []) {
    const tid = (cs as any).tournament_id;
    const closesAt = new Date((cs as any).closes_at);
    const minLeft = Math.round((closesAt.getTime() - Date.now()) / 60000);

    if (minLeft > 25 && minLeft <= 35) {
      const { data: members } = await supabase
        .from("members")
        .select("id")
        .eq("tournament_id", tid);

      await createBulkNotifications(
        supabase,
        tid,
        (members ?? []).map((m: any) => m.id),
        "market_closing",
        "¡URGENTE! Mercado cierra en 30 min",
        `Quedan ~${minLeft} minutos para el cierre del mercado.`
      );
    }
  }

  // ── 4. Resolve expired auctions (eBay-style) ─────────────────────────────
  const { data: expiredAuctions } = await supabase
    .from("icon_auctions")
    .select("id, session_id, selected_icon_id, highest_bid, highest_bidder_id")
    .eq("phase", "active")
    .lt("ends_at", now);

  let resolvedAuctions = 0;

  for (const ea of expiredAuctions ?? []) {
    const ax = ea as any;
    const { data: sess } = await supabase
      .from("market_sessions")
      .select("tournament_id")
      .eq("id", ax.session_id)
      .single();
    const tid = (sess as any)?.tournament_id;

    if (ax.highest_bidder_id && ax.highest_bid > 0) {
      // Winner found — transfer icon
      await supabase
        .from("icon_auctions")
        .update({
          phase: "finished",
          winner_id: ax.highest_bidder_id,
          final_amount: ax.highest_bid,
        })
        .eq("id", ax.id);

      // Deduct budget from winner
      const { data: winner } = await supabase
        .from("members")
        .select("budget")
        .eq("id", ax.highest_bidder_id)
        .single();

      await supabase
        .from("members")
        .update({
          budget: Math.max(0, ((winner as any)?.budget ?? 0) - ax.highest_bid),
          icon_slot_used: true,
        })
        .eq("id", ax.highest_bidder_id);

      // Record as market_transfer
      await supabase.from("market_transfers").insert({
        session_id: ax.session_id,
        player_id: ax.selected_icon_id,
        buyer_id: ax.highest_bidder_id,
        seller_id: null,
        amount: ax.highest_bid,
        type: "auction",
      });

      if (tid) {
        // Notify winner
        const { data: iconData } = await supabase
          .from("players")
          .select("name")
          .eq("id", ax.selected_icon_id)
          .single();
        const iconName = (iconData as any)?.name ?? "un ícono";

        await createNotification({
          supabase,
          memberId: ax.highest_bidder_id,
          tournamentId: tid,
          type: "auction_won",
          title: "¡Ganaste la subasta!",
          body: `Has ganado a ${iconName} por €${Math.floor(ax.highest_bid / 1_000_000)}M.`,
          metadata: { auctionId: ax.id, iconName, amount: ax.highest_bid },
        });

        // Notify all other bidders they lost
        const { data: otherBidders } = await supabase
          .from("icon_bids")
          .select("member_id")
          .eq("auction_id", ax.id)
          .neq("member_id", ax.highest_bidder_id);

        const loserIds = [
          ...new Set((otherBidders ?? []).map((b: any) => b.member_id)),
        ];

        if (loserIds.length > 0) {
          await createBulkNotifications(
            supabase,
            tid,
            loserIds,
            "auction_lost",
            "Subasta finalizada",
            `La subasta de ${iconName} terminó. No ganaste esta vez.`,
            { auctionId: ax.id, iconName }
          );
        }
      }
    } else {
      // No bids — auction ends without winner
      await supabase
        .from("icon_auctions")
        .update({ phase: "finished" })
        .eq("id", ax.id);
    }
    resolvedAuctions++;
  }

  // ── 5. Send "auction ending soon" warnings ──────────────────────────────
  const twoMinLater = new Date(Date.now() + 5 * 60 * 1000).toISOString();

  const { data: endingSoonAuctions } = await supabase
    .from("icon_auctions")
    .select("id, session_id, selected_icon_id, ends_at")
    .eq("phase", "active")
    .gt("ends_at", now)
    .lt("ends_at", twoMinLater);

  for (const ea of endingSoonAuctions ?? []) {
    const ax = ea as any;
    const endsAt = new Date(ax.ends_at);
    const minLeft = Math.round((endsAt.getTime() - Date.now()) / 60000);

    if (minLeft >= 3 && minLeft <= 6) {
      const { data: sess } = await supabase
        .from("market_sessions")
        .select("tournament_id")
        .eq("id", ax.session_id)
        .single();
      const tid = (sess as any)?.tournament_id;

      if (tid) {
        const { data: iconData } = await supabase
          .from("players")
          .select("name")
          .eq("id", ax.selected_icon_id)
          .single();
        const iconName = (iconData as any)?.name ?? "un ícono";

        const { data: members } = await supabase
          .from("members")
          .select("id")
          .eq("tournament_id", tid);

        await createBulkNotifications(
          supabase,
          tid,
          (members ?? []).map((m: any) => m.id),
          "auction_ending",
          "Subasta por terminar",
          `La subasta de ${iconName} cierra en ~${minLeft} minutos.`,
          { auctionId: ax.id, iconName }
        );
      }
    }
  }

  return NextResponse.json({
    ok: true,
    expiredOffers: expiredOffers?.length ?? 0,
    closedMarkets: expiredSessions?.length ?? 0,
    resolvedAuctions,
  });
}
