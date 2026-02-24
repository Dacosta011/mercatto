"use client";

import { useEffect, useRef } from "react";
import { useRouter, usePathname } from "next/navigation";
import { getBrowserClient } from "@/lib/supabase-browser";
import {
  getLastTournamentCode,
  getMemberId,
  clearTournamentTokens,
  saveTournamentStatus,
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

  useEffect(() => { pathnameRef.current = pathname; }, [pathname]);

  useEffect(() => {
    const code = getLastTournamentCode();
    if (!code) return;

    const supabase = getBrowserClient();
    let cancelled = false;

    function maybeRedirect(newStatus: TournamentStatus) {
      if (cancelled) return;
      const prev = getTournamentStatus(code!);
      saveTournamentStatus(code!, newStatus);

      if (prev === newStatus) return;

      const dest = PHASE_DESTINATIONS[newStatus]?.replace("%%LOBBY%%", `/lobby/${code}`);
      if (!dest) return;

      const current = pathnameRef.current;
      if (SUPPRESS_PREFIXES.some((p) => current.startsWith(p))) return;
      if (current === dest || current.startsWith(dest + "/")) return;

      router.push(dest);
    }

    // ── Initial fetch: seed localStorage with current status ────────────
    async function fetchStatus() {
      try {
        const res = await fetch(`/api/tournaments/${code}`);
        if (!res.ok) return;
        const data = await res.json();
        if (data.status) maybeRedirect(data.status as TournamentStatus);
      } catch { /* non-blocking */ }
    }
    fetchStatus();

    // ── Polling fallback: check status every 4s ─────────────────────────
    const statusPoll = setInterval(fetchStatus, 4_000);

    // ── Realtime: instant phase changes ─────────────────────────────────
    const phaseChannel = supabase
      .channel(`phase-redirect-${code}`)
      .on(
        "postgres_changes" as any,
        { event: "UPDATE", schema: "public", table: "tournaments" },
        (payload: any) => {
          const newStatus = payload?.new?.status as TournamentStatus | undefined;
          if (newStatus) maybeRedirect(newStatus);
        },
      )
      .subscribe();

    // ── Self-deletion detection ────────────────────────────────────────────
    const myMemberId = getMemberId(code);
    let kickChannel: ReturnType<typeof supabase.channel> | null = null;
    let kickPoll: ReturnType<typeof setInterval> | null = null;

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

      kickPoll = setInterval(async () => {
        try {
          const token = localStorage.getItem(`mercatto:member:${code}`);
          if (!token) return;
          const r = await fetch(`/api/tournaments/${code}/me`, {
            headers: { Authorization: `Bearer ${token}` },
          });
          if (r.status === 401 || r.status === 403) {
            handleKick();
          }
        } catch { /* ignore */ }
      }, 5_000);
    }

    return () => {
      cancelled = true;
      clearInterval(statusPoll);
      if (kickPoll) clearInterval(kickPoll);
      supabase.removeChannel(phaseChannel);
      if (kickChannel) supabase.removeChannel(kickChannel);
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
