"use client";

import { useEffect, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import { getLastTournamentCode } from "@/lib/tokenStorage";

// Rutas accesibles sin torneo activo
const PUBLIC_PATHS = ["/create", "/join"];

export default function RouteGuard({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [allowed, setAllowed] = useState(false);

  useEffect(() => {
    const isPublic = PUBLIC_PATHS.some(
      (p) => pathname === p || pathname.startsWith(p + "/")
    );

    if (isPublic) {
      setAllowed(true);
      return;
    }

    const code = getLastTournamentCode();
    if (!code) {
      router.replace("/");
    } else {
      setAllowed(true);
    }
  }, [pathname, router]);

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
