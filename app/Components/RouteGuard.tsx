"use client";

import { useEffect, useState, useCallback } from "react";
import { usePathname, useRouter } from "next/navigation";
import {
  getLastTournamentCode,
  hasTeamAssignment,
  isMarketActive,
  isLeagueActive,
  isGuest,
  subscribeToStore,
} from "@/lib/tokenStorage";

const PUBLIC_PATHS = ["/create", "/join"];
const FALLBACK = (code: string) => `/lobby/${code}`;

export default function RouteGuard({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router   = useRouter();
  const [allowed, setAllowed] = useState(false);

  const checkAccess = useCallback(() => {
    const isPublic = PUBLIC_PATHS.some(
      (p) => pathname === p || pathname.startsWith(p + "/"),
    );
    if (isPublic) { setAllowed(true); return; }

    if (pathname.startsWith("/lobby")) { setAllowed(true); return; }
    if (pathname.startsWith("/guest")) { setAllowed(true); return; }

    const code = getLastTournamentCode();
    if (!code) { router.replace("/"); return; }

    const guest = isGuest(code);
    const hasTeam = hasTeamAssignment(code);
    const fallback = FALLBACK(code);
    const mActive = isMarketActive(code);
    const lActive = isLeagueActive(code);

    // Guests can only access feed, table, and calendar
    if (guest) {
      const guestAllowed =
        pathname === "/feed" || pathname.startsWith("/feed/") ||
        pathname === "/table" || pathname.startsWith("/table/") ||
        pathname === "/calendar" || pathname.startsWith("/calendar/");
      if (!guestAllowed) { router.replace("/calendar"); return; }
      setAllowed(true); return;
    }

    if ((pathname === "/squad" || pathname.startsWith("/squad/")) && !hasTeam) {
      router.replace(fallback); return;
    }

    if (
      (pathname === "/market" || pathname.startsWith("/market/") ||
       pathname === "/subastas" || pathname.startsWith("/subastas/")) &&
      !mActive
    ) {
      router.replace(fallback); return;
    }

    if (
      (pathname === "/calendar" || pathname.startsWith("/calendar/") ||
       pathname === "/table"    || pathname.startsWith("/table/")) &&
      !lActive
    ) {
      router.replace(fallback); return;
    }

    setAllowed(true);
  }, [pathname, router]);

  useEffect(() => {
    setAllowed(false);
    checkAccess();
  }, [checkAccess]);

  useEffect(() => subscribeToStore(checkAccess), [checkAccess]);

  if (!allowed) {
    return (
      <div className="flex-1 flex items-center justify-center bg-[#0D0F14]">
        <div className="flex flex-col items-center gap-3">
          <div className="w-7 h-7 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          <p className="text-[#9CA3AF] text-xs">Verificando acceso…</p>
        </div>
      </div>
    );
  }

  return <>{children}</>;
}
