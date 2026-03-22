"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { motion } from "motion/react";
import Link from "next/link";
import { getLastTournamentCode } from "@/lib/tokenStorage";

export default function Home() {
  const router = useRouter();
  const [checking, setChecking] = useState(true);

  useEffect(() => {
    const code = getLastTournamentCode();
    if (code) {
      router.replace(`/lobby/${code}`);
    } else {
      setChecking(false);
    }
  }, [router]);

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
        <motion.h1
          initial={{ opacity: 0, scale: 0.92 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ delay: 0.2, duration: 0.7, ease: "easeOut" }}
          className="text-[#F3F4F6] text-[3rem] sm:text-[4.5rem] md:text-[5.5rem] mb-4 sm:mb-5 tracking-tight font-black leading-none"
          style={{ letterSpacing: "-0.04em" }}
        >
          MERCATTO
        </motion.h1>

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
