import { SupabaseClient } from "@supabase/supabase-js";
import webPush from "web-push";

const VAPID_PUBLIC = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY ?? "";
const VAPID_PRIVATE = process.env.VAPID_PRIVATE_KEY ?? "";
const VAPID_EMAIL = process.env.VAPID_EMAIL ?? "mailto:mercatto@app.com";

if (VAPID_PUBLIC && VAPID_PRIVATE) {
  webPush.setVapidDetails(VAPID_EMAIL, VAPID_PUBLIC, VAPID_PRIVATE);
}

export type NotificationType =
  | "offer_received"
  | "offer_accepted"
  | "offer_rejected"
  | "offer_expired"
  | "offer_countered"
  | "offer_expiring"
  | "clause_paid"
  | "clause_protected"
  | "auction_started"
  | "auction_outbid"
  | "auction_ending"
  | "auction_won"
  | "auction_lost"
  | "market_closing"
  | "market_closed"
  | "transfer_completed";

interface CreateNotificationParams {
  supabase: SupabaseClient;
  memberId: string;
  tournamentId: string;
  type: NotificationType;
  title: string;
  body?: string;
  metadata?: Record<string, unknown>;
}

export async function createNotification({
  supabase,
  memberId,
  tournamentId,
  type,
  title,
  body,
  metadata,
}: CreateNotificationParams) {
  const { data: notification } = await supabase
    .from("notifications")
    .insert({
      member_id: memberId,
      tournament_id: tournamentId,
      type,
      title,
      body: body ?? null,
      metadata: metadata ?? {},
    })
    .select("id")
    .single();

  await sendPush(supabase, memberId, title, body ?? "");

  return notification;
}

export async function createBulkNotifications(
  supabase: SupabaseClient,
  tournamentId: string,
  memberIds: string[],
  type: NotificationType,
  title: string,
  body?: string,
  metadata?: Record<string, unknown>
) {
  const rows = memberIds.map((mid) => ({
    member_id: mid,
    tournament_id: tournamentId,
    type,
    title,
    body: body ?? null,
    metadata: metadata ?? {},
  }));

  await supabase.from("notifications").insert(rows);

  for (const mid of memberIds) {
    await sendPush(supabase, mid, title, body ?? "");
  }
}

async function sendPush(
  supabase: SupabaseClient,
  memberId: string,
  title: string,
  body: string
) {
  if (!VAPID_PUBLIC || !VAPID_PRIVATE) return;

  const { data: subs } = await supabase
    .from("push_subscriptions")
    .select("endpoint, p256dh, auth")
    .eq("member_id", memberId);

  for (const sub of subs ?? []) {
    try {
      await webPush.sendNotification(
        {
          endpoint: sub.endpoint,
          keys: { p256dh: sub.p256dh, auth: sub.auth },
        },
        JSON.stringify({ title, body, icon: "/icon-192.png" })
      );
    } catch (err: unknown) {
      const status = (err as { statusCode?: number })?.statusCode;
      if (status === 410 || status === 404) {
        await supabase
          .from("push_subscriptions")
          .delete()
          .eq("endpoint", sub.endpoint);
      }
    }
  }
}

export const OFFER_EXPIRY_HOURS = 4;

export function offerExpiresAt(): string {
  const d = new Date();
  d.setHours(d.getHours() + OFFER_EXPIRY_HOURS);
  return d.toISOString();
}
