"use client";

import { useState, useEffect, useCallback } from "react";
import {
  canInstall,
  triggerInstall,
  dismissInstallPrompt,
  subscribePwa,
  isStandalone,
} from "@/lib/pwa";

export default function InstallPrompt() {
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (isStandalone()) return;

    const timer = setTimeout(() => setShow(canInstall()), 3000);
    const unsub = subscribePwa(() => setShow(canInstall()));

    return () => {
      clearTimeout(timer);
      unsub();
    };
  }, []);

  const handleInstall = useCallback(async () => {
    const accepted = await triggerInstall();
    if (accepted) setShow(false);
  }, []);

  const handleDismiss = useCallback(() => {
    dismissInstallPrompt();
    setShow(false);
  }, []);

  if (!show) return null;

  return (
    <div className="mx-4 mt-3 lg:mx-6 flex items-center gap-3 px-4 py-3 rounded-2xl bg-[#131722] border border-[#8B5CF6]/15 shadow-lg shadow-[#8B5CF6]/5">
      <div className="w-10 h-10 rounded-xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center shrink-0">
        <span className="text-lg font-black text-[#8B5CF6]">M</span>
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-[13px] font-semibold text-[#F3F4F6] leading-tight">
          Instalar Mercatto
        </p>
        <p className="text-[11px] text-[#9CA3AF] mt-0.5">
          Accede más rápido desde tu pantalla de inicio
        </p>
      </div>
      <button
        onClick={handleInstall}
        className="shrink-0 px-3.5 py-2 rounded-xl bg-[#8B5CF6] text-white text-xs font-semibold active:bg-[#7C3AED] transition-colors cursor-pointer shadow-sm shadow-[#8B5CF6]/30"
      >
        Instalar
      </button>
      <button
        onClick={handleDismiss}
        className="shrink-0 p-1.5 rounded-lg text-[#9CA3AF]/50 active:text-[#9CA3AF] active:bg-[#1A1F2E] transition-colors cursor-pointer"
      >
        <svg
          width="14"
          height="14"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
        >
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>
    </div>
  );
}
