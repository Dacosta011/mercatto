"use client";

import { useEffect, useState, useCallback } from "react";
import { usePathname, useRouter } from "next/navigation";
import {
  getLastTournamentCode,
  hasTeamAssignment,
  getTournamentStatus,
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

    // Lobby pages are always allowed when there's a tournament
    if (pathname.startsWith("/lobby")) { setAllowed(true); return; }

    const code = getLastTournamentCode();
    if (!code) { router.replace("/"); return; }

    const hasTeam = hasTeamAssignment(code);
    const status  = getTournamentStatus(code);
    const fallback = FALLBACK(code);

    if ((pathname === "/squad" || pathname.startsWith("/squad/")) && !hasTeam) {
      router.replace(fallback); return;
    }

    if ((pathname === "/market" || pathname.startsWith("/market/")) &&
        status !== null && status !== "market") {
      router.replace(fallback); return;
    }

    if (
      (pathname === "/calendar" || pathname.startsWith("/calendar/") ||
       pathname === "/table"    || pathname.startsWith("/table/")) &&
      status !== null && status !== "league" && status !== "complete"
    ) {
      router.replace(fallback); return;
    }

    setAllowed(true);
  }, [pathname, router]);

  // Re-check on pathname change
  useEffect(() => {
    setAllowed(false);
    checkAccess();
  }, [checkAccess]);

  // Also re-check when localStorage changes (status update before navigation)
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
