"use client";

import { useEffect, useRef } from "react";
import { useRouter, usePathname } from "next/navigation";
import { getBrowserClient } from "@/lib/supabase-browser";
import {
  getLastTournamentCode,
  getMemberId,
  clearTournamentTokens,
  saveTournamentStatus,
  saveMarketOpen,
  getMarketOpen,
  getTournamentStatus,
  type TournamentStatus,
} from "@/lib/tokenStorage";

const SUPPRESS_PREFIXES = ["/roulette"];

const PHASE_DESTINATIONS: Record<string, string> = {
  lobby:    "%%LOBBY%%",
  market:   "/market",
  league:   "/calendar",
  complete: "/table",
};

export default function PhaseRedirectGuard() {
  const router      = useRouter();
  const pathname    = usePathname();
  const pathnameRef = useRef(pathname);
  const prevStatusRef = useRef<TournamentStatus | null>(null);

  useEffect(() => { pathnameRef.current = pathname; }, [pathname]);

  useEffect(() => {
    const code = getLastTournamentCode();
    if (!code) return;

    const supabase = getBrowserClient();
    let cancelled = false;

    // Seed the ref from localStorage so we know the starting point
    prevStatusRef.current = getTournamentStatus(code) ?? null;

    function maybeRedirect(newStatus: TournamentStatus) {
      if (cancelled) return;

      const prev = prevStatusRef.current;
      prevStatusRef.current = newStatus;
      saveTournamentStatus(code!, newStatus);

      if (prev === newStatus) return;

      const dest = PHASE_DESTINATIONS[newStatus]?.replace("%%LOBBY%%", `/lobby/${code}`);
      if (!dest) return;

      const current = pathnameRef.current;
      if (SUPPRESS_PREFIXES.some((p) => current.startsWith(p))) return;
      if (current === dest || current.startsWith(dest + "/")) return;

      // In hybrid mode, don't redirect away from market pages during league transition
      const marketStillOpen = getMarketOpen(code!);
      if (
        marketStillOpen &&
        newStatus === "league" &&
        (current === "/market" || current.startsWith("/market/") ||
         current === "/subastas" || current.startsWith("/subastas/"))
      ) return;

      router.push(dest);
    }

    // ── Initial fetch: seed cached status only, never redirect ──────────
    // Redirects only fire on realtime status changes, not on page load.
    // This prevents the guard from bouncing the admin back to lobby when
    // they manually navigate to /squad or /feed.
    async function fetchStatus() {
      try {
        const res = await fetch(`/api/tournaments/${code}`);
        if (!res.ok) return;
        const data = await res.json();
        if (data.status) {
          prevStatusRef.current = data.status as TournamentStatus;
          saveTournamentStatus(code!, data.status as TournamentStatus);
        }
        if (typeof data.marketOpen === "boolean") {
          saveMarketOpen(code!, data.marketOpen);
        }
      } catch { /* non-blocking */ }
    }
    fetchStatus();

    // ── Realtime: instant phase changes ─────────────────────────────────
    const phaseChannel = supabase
      .channel(`phase-redirect-${code}`)
      .on(
        "postgres_changes" as any,
        { event: "UPDATE", schema: "public", table: "tournaments" },
        (payload: any) => {
          const newStatus = payload?.new?.status as TournamentStatus | undefined;
          if (newStatus) maybeRedirect(newStatus);
          if (typeof payload?.new?.market_open === "boolean") {
            saveMarketOpen(code!, payload.new.market_open);
          }
        },
      )
      .on(
        "postgres_changes" as any,
        { event: "UPDATE", schema: "public", table: "market_sessions" },
        (payload: any) => {
          const sessionStatus = payload?.new?.status;
          if (sessionStatus === "active") {
            saveMarketOpen(code!, true);
          } else if (sessionStatus === "finished") {
            saveMarketOpen(code!, false);
          }
        },
      )
      .subscribe();

    // ── Self-deletion detection (realtime only) ─────────────────────────
    const myMemberId = getMemberId(code);
    let kickChannel: ReturnType<typeof supabase.channel> | null = null;

    function handleKick() {
      clearTournamentTokens(code!);
      router.replace("/");
    }

    if (myMemberId) {
      kickChannel = supabase
        .channel(`kick-${myMemberId}`)
        .on(
          "postgres_changes" as any,
          {
            event:  "DELETE",
            schema: "public",
            table:  "members",
            filter: `id=eq.${myMemberId}`,
          },
          handleKick,
        )
        .subscribe();
    }

    return () => {
      cancelled = true;
      supabase.removeChannel(phaseChannel);
      if (kickChannel) supabase.removeChannel(kickChannel);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
