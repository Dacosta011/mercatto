"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { motion } from "motion/react";
import Link from "next/link";
import { getLastTournamentCode } from "@/lib/tokenStorage";

export default function Home() {
  const router = useRouter();
  const [checking, setChecking] = useState(true);
  const [standalone, setStandalone] = useState(false);
  const [pasteValue, setPasteValue] = useState("");
  const [pasteError, setPasteError] = useState(false);

  useEffect(() => {
    const code = getLastTournamentCode();
    if (code) {
      router.replace(`/lobby/${code}`);
    } else {
      const isStandaloneMode =
        window.matchMedia("(display-mode: standalone)").matches ||
        (window.navigator as unknown as Record<string, unknown>).standalone ===
          true;
      setStandalone(isStandaloneMode);
      setChecking(false);
    }
  }, [router]);

  const handleLinkInput = (val: string) => {
    setPasteValue(val);
    setPasteError(false);
    const trimmed = val.trim();
    if (!trimmed) return;

    try {
      const url = new URL(trimmed);
      const c = url.searchParams.get("code");
      const t = url.searchParams.get("token");
      if (c && t) {
        router.push(
          `/rejoin?code=${encodeURIComponent(c)}&token=${encodeURIComponent(t)}`,
        );
        return;
      }
    } catch {}

    if (trimmed.length > 20) setPasteError(true);
  };

  if (checking) {
    return (
      <div className="min-h-screen bg-[#0D0F14] flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <div className="w-8 h-8 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          <p className="text-[#9CA3AF] text-sm">Cargando…</p>
        </div>
      </div>
    );
  }

  if (standalone) {
    return (
      <div className="min-h-dvh bg-[#0D0F14] flex items-center justify-center relative overflow-hidden p-6">
        <div
          className="absolute pointer-events-none"
          style={{
            width: 600,
            height: 600,
            background:
              "radial-gradient(circle, rgba(139,92,246,0.1) 0%, transparent 65%)",
            top: "50%",
            left: "50%",
            transform: "translate(-50%, -50%)",
          }}
        />

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="text-center z-10 w-full max-w-md"
        >
          <img src="/mercatto-logo.svg" alt="" className="w-14 h-auto mx-auto mb-4" />
          <img src="/mercatto-text.svg" alt="Mercatto" className="h-5 w-auto mx-auto mb-2 brightness-0 invert" />
          <p className="text-[#9CA3AF] text-sm mb-8">
            Pega tu enlace mágico para restaurar tu sesión
          </p>

          <div className="bg-[#131722] rounded-2xl border border-white/5 p-4 mb-4">
            <label className="block text-[#9CA3AF] text-[10px] font-semibold uppercase tracking-widest mb-2 text-left">
              Enlace mágico
            </label>
            <input
              type="url"
              value={pasteValue}
              onChange={(e) => handleLinkInput(e.target.value)}
              placeholder="Pega tu enlace aquí…"
              autoComplete="off"
              className={`w-full bg-[#0D0F14] border rounded-xl px-4 py-3.5 text-sm text-[#F3F4F6] placeholder-[#9CA3AF]/30 outline-none transition-colors duration-150 ${
                pasteError
                  ? "border-[#EF4444]/30 focus:border-[#EF4444]/50"
                  : "border-white/8 focus:border-[#8B5CF6]/40"
              }`}
            />
            {pasteError && (
              <p className="text-[#EF4444] text-xs mt-2 text-left">
                Enlace no reconocido. Asegúrate de copiar el enlace completo
                desde Mi Enlace.
              </p>
            )}
          </div>

          <div className="flex items-start gap-2.5 bg-[#8B5CF6]/5 border border-[#8B5CF6]/15 rounded-xl px-3.5 py-3 mb-8 text-left">
            <svg
              width="14"
              height="14"
              viewBox="0 0 24 24"
              fill="none"
              stroke="#8B5CF6"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              className="shrink-0 mt-0.5"
            >
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
            <p className="text-[#9CA3AF] text-xs leading-relaxed">
              Abre Safari → entra a Mercatto → ve a{" "}
              <strong className="text-[#F3F4F6]">Más → Mi Enlace</strong> →
              copia el enlace y pégalo aquí.
            </p>
          </div>

          <div className="flex items-center gap-3 mb-6">
            <div className="h-px flex-1 bg-white/6" />
            <span className="text-[#9CA3AF]/40 text-[10px] uppercase tracking-widest">
              o
            </span>
            <div className="h-px flex-1 bg-white/6" />
          </div>

          <div className="flex flex-col gap-3">
            <Link
              href="/rejoin"
              className="w-full flex items-center justify-center gap-2 py-3.5 rounded-xl border border-white/10 text-[#F3F4F6] text-sm font-semibold active:bg-[#1A1F2E] transition-colors"
            >
              <svg
                width="16"
                height="16"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" />
                <polyline points="10 17 15 12 10 7" />
                <line x1="15" y1="12" x2="3" y2="12" />
              </svg>
              Reingresar manualmente
            </Link>
            <div className="flex gap-3">
              <Link
                href="/create"
                className="flex-1 flex items-center justify-center gap-2 py-3 rounded-xl bg-[#8B5CF6] text-white text-sm font-semibold active:bg-[#7C3AED] transition-colors shadow-lg shadow-[#8B5CF6]/20"
              >
                Crear Torneo
              </Link>
              <Link
                href="/join"
                className="flex-1 flex items-center justify-center gap-2 py-3 rounded-xl border border-[#8B5CF6]/30 text-[#F3F4F6] text-sm font-semibold active:bg-[#8B5CF6]/5 transition-colors"
              >
                Unirse
              </Link>
            </div>
          </div>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="min-h-dvh bg-[#0D0F14] flex items-center justify-center relative overflow-hidden">
      {/* Background radial glow */}
      <div
        className="absolute pointer-events-none"
        style={{
          width: 700,
          height: 700,
          background:
            "radial-gradient(circle, rgba(139,92,246,0.12) 0%, transparent 65%)",
          top: "50%",
          left: "50%",
          transform: "translate(-50%, -50%)",
        }}
      />

      {/* Subtle grid overlay */}
      <div
        className="absolute inset-0 pointer-events-none opacity-[0.03]"
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.5) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.5) 1px, transparent 1px)",
          backgroundSize: "64px 64px",
        }}
      />

      {/* Content */}
      <motion.div
        initial={{ opacity: 0, y: 24 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.7, ease: "easeOut" }}
        className="text-center z-10 px-6 sm:px-8 max-w-2xl w-full"
      >
        {/* Eyebrow label */}
        <motion.div
          initial={{ opacity: 0, scale: 0.9 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.1, duration: 0.5 }}
          className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 mb-6 sm:mb-8"
        >
          <span className="w-1.5 h-1.5 rounded-full bg-[#8B5CF6] animate-pulse" />
          <span className="text-[#8B5CF6] text-[11px] sm:text-xs font-medium tracking-widest uppercase">
            Temporada 2026
          </span>
        </motion.div>

        {/* Title */}
        <motion.div
          initial={{ opacity: 0, scale: 0.92 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.2, duration: 0.7, ease: "easeOut" }}
          className="flex justify-center mb-4 sm:mb-5"
        >
          <img src="/mercatto-text.svg" alt="Mercatto" className="h-8 sm:h-12 md:h-14 w-auto brightness-0 invert" />
        </motion.div>

        {/* Subtitle */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.4, duration: 0.6 }}
          className="text-[#9CA3AF] text-base sm:text-xl mb-8 sm:mb-12 font-light tracking-wide"
        >
          La ruleta decide.{" "}
          <span className="text-[#F3F4F6]/70">El mercado juzga.</span>
        </motion.p>

        {/* CTA Buttons */}
        <motion.div
          initial={{ opacity: 0, y: 16 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.55, duration: 0.6 }}
          className="flex flex-col sm:flex-row items-center justify-center gap-3 sm:gap-4 px-4 sm:px-0"
        >
          <Link href="/create" className="w-full sm:w-auto">
            <span className="w-full inline-flex items-center justify-center gap-2 px-8 sm:px-10 py-3.5 sm:py-4 text-sm sm:text-base font-semibold rounded-2xl bg-[#8B5CF6] hover:bg-[#7C3AED] active:bg-[#6D28D9] text-white shadow-2xl shadow-[#8B5CF6]/25 transition-all duration-200 cursor-pointer">
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <line x1="12" y1="5" x2="12" y2="19" />
                <line x1="5" y1="12" x2="19" y2="12" />
              </svg>
              Crear Torneo
            </span>
          </Link>

          <Link href="/join" className="w-full sm:w-auto">
            <span className="w-full inline-flex items-center justify-center gap-2 px-8 sm:px-10 py-3.5 sm:py-4 text-sm sm:text-base font-semibold rounded-2xl bg-transparent border-2 border-[#8B5CF6]/30 hover:border-[#8B5CF6]/60 hover:bg-[#8B5CF6]/5 text-[#F3F4F6] transition-all duration-200 cursor-pointer">
              <svg
                width="18"
                height="18"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" />
                <polyline points="10 17 15 12 10 7" />
                <line x1="15" y1="12" x2="3" y2="12" />
              </svg>
              Unirse
            </span>
          </Link>
        </motion.div>

        {/* Bottom hint */}
        <motion.p
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 0.9, duration: 0.6 }}
          className="text-[#9CA3AF]/50 text-[10px] sm:text-xs mt-10 sm:mt-16 tracking-wider uppercase"
        >
          Draft · Transfer Market · Squad Management
        </motion.p>
      </motion.div>
    </div>
  );
}
