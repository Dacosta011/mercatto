"use client";

import { useState, useEffect, useCallback } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense } from "react";
import { motion, AnimatePresence } from "motion/react";
import Link from "next/link";
import {
  saveMemberToken,
  saveMemberId,
  saveUserProfile,
  saveTeamAssignment,
  saveTournamentStatus,
} from "@/lib/tokenStorage";
import type { TournamentStatus } from "@/lib/tokenStorage";

function RejoinContent() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [code, setCode] = useState("");
  const [token, setToken] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [autoAttempted, setAutoAttempted] = useState(false);

  const doRejoin = useCallback(
    async (c: string, t: string) => {
      setLoading(true);
      setError(null);

      try {
        const res = await fetch(`/api/tournaments/${c.trim()}/rejoin`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ token: t.trim() }),
        });

        const data = await res.json();

        if (!res.ok) {
          setError(data.error ?? "Enlace inválido o expirado.");
          return;
        }

        saveMemberToken(data.code, t.trim());
        saveMemberId(data.code, data.memberId);
        saveUserProfile(data.code, data.displayName, "member");
        if (data.team) {
          saveTeamAssignment(data.code, data.team.name, data.team.crestUrl);
        }
        if (data.tournamentStatus) {
          saveTournamentStatus(
            data.code,
            data.tournamentStatus as TournamentStatus
          );
        }

        router.push(`/lobby/${data.code}`);
      } catch {
        setError("No se pudo conectar con el servidor.");
      } finally {
        setLoading(false);
      }
    },
    [router]
  );

  useEffect(() => {
    if (autoAttempted) return;
    const urlCode = searchParams.get("code");
    const urlToken = searchParams.get("token");
    if (urlCode) setCode(urlCode.toUpperCase());
    if (urlToken) setToken(urlToken);

    if (urlCode && urlToken) {
      setAutoAttempted(true);
      doRejoin(urlCode, urlToken);
    } else {
      setAutoAttempted(true);
    }
  }, [searchParams, autoAttempted, doRejoin]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!code.trim() || !token.trim()) {
      setError("Completa ambos campos.");
      return;
    }
    doRejoin(code, token);
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-6 bg-[#0D0F14]">
      <div
        className="fixed pointer-events-none"
        style={{
          width: 450,
          height: 450,
          background:
            "radial-gradient(circle, rgba(139,92,246,0.07) 0%, transparent 65%)",
          top: "50%",
          left: "50%",
          transform: "translate(-30%, -50%)",
        }}
      />

      <div className="w-full max-w-md z-10">
        <AnimatePresence mode="wait">
          {loading && !error ? (
            <motion.div
              key="loading"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              className="flex flex-col items-center gap-5"
            >
              <div className="w-14 h-14 rounded-2xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center">
                <span className="w-6 h-6 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
              </div>
              <div className="text-center">
                <p className="text-[#F3F4F6] font-semibold text-lg">
                  Restaurando sesión…
                </p>
                <p className="text-[#9CA3AF] text-sm mt-1">
                  Verificando tu enlace mágico
                </p>
              </div>
            </motion.div>
          ) : (
            <motion.div
              key="form"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -16 }}
              transition={{ duration: 0.4 }}
            >
              <Link
                href="/"
                className="inline-flex items-center gap-2 text-[#9CA3AF] hover:text-[#F3F4F6] text-sm mb-6 transition-colors duration-150 group"
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
                  className="group-hover:-translate-x-0.5 transition-transform duration-150"
                >
                  <polyline points="15 18 9 12 15 6" />
                </svg>
                Volver al inicio
              </Link>

              <div className="mb-8">
                <div className="flex items-center gap-3 mb-3">
                  <div className="w-10 h-10 rounded-xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center">
                    <svg
                      width="18"
                      height="18"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="#8B5CF6"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    >
                      <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" />
                      <polyline points="10 17 15 12 10 7" />
                      <line x1="15" y1="12" x2="3" y2="12" />
                    </svg>
                  </div>
                  <div>
                    <h1 className="text-[#F3F4F6] text-2xl font-bold tracking-tight">
                      Reingresar al Torneo
                    </h1>
                    <p className="text-[#9CA3AF] text-sm">
                      Usa tu enlace mágico o ingresa los datos manualmente
                    </p>
                  </div>
                </div>
              </div>

              <form
                onSubmit={handleSubmit}
                className="bg-[#131722] rounded-2xl border border-white/5 overflow-hidden"
              >
                <div className="h-px w-full bg-linear-to-r from-transparent via-[#8B5CF6]/40 to-transparent" />

                <div className="p-6 flex flex-col gap-5">
                  {/* Code */}
                  <div>
                    <label className="block text-[#9CA3AF] text-xs font-semibold uppercase tracking-wider mb-2">
                      Código del Torneo
                    </label>
                    <input
                      type="text"
                      value={code}
                      onChange={(e) => {
                        setCode(e.target.value.toUpperCase());
                        setError(null);
                      }}
                      placeholder="Ej. XYZ-1234-ABC"
                      className="w-full bg-[#0D0F14] border border-white/8 rounded-xl px-4 py-3 text-[#F3F4F6] text-sm font-mono tracking-widest placeholder:text-[#9CA3AF]/30 focus:outline-none focus:border-[#8B5CF6]/40 transition-colors"
                    />
                  </div>

                  {/* Token */}
                  <div>
                    <label className="block text-[#9CA3AF] text-xs font-semibold uppercase tracking-wider mb-2">
                      Token de Acceso
                    </label>
                    <input
                      type="text"
                      value={token}
                      onChange={(e) => {
                        setToken(e.target.value);
                        setError(null);
                      }}
                      placeholder="Tu token de miembro"
                      className="w-full bg-[#0D0F14] border border-white/8 rounded-xl px-4 py-3 text-[#F3F4F6] text-sm font-mono tracking-wider placeholder:text-[#9CA3AF]/30 focus:outline-none focus:border-[#8B5CF6]/40 transition-colors"
                    />
                  </div>

                  {/* Info */}
                  <div className="flex items-start gap-2.5 bg-[#8B5CF6]/5 border border-[#8B5CF6]/15 rounded-xl px-3.5 py-3">
                    <svg
                      width="13"
                      height="13"
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
                      Si tienes tu enlace mágico, ábrelo directamente. Los
                      campos se completarán automáticamente.
                    </p>
                  </div>

                  {/* Error */}
                  <AnimatePresence>
                    {error && (
                      <motion.div
                        initial={{ opacity: 0, height: 0 }}
                        animate={{ opacity: 1, height: "auto" }}
                        exit={{ opacity: 0, height: 0 }}
                        className="flex items-center gap-2.5 bg-[#EF4444]/8 border border-[#EF4444]/20 rounded-xl px-3.5 py-3"
                      >
                        <svg
                          width="14"
                          height="14"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="#EF4444"
                          strokeWidth="2"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          className="shrink-0"
                        >
                          <circle cx="12" cy="12" r="10" />
                          <line x1="15" y1="9" x2="9" y2="15" />
                          <line x1="9" y1="9" x2="15" y2="15" />
                        </svg>
                        <p className="text-[#EF4444] text-sm">{error}</p>
                      </motion.div>
                    )}
                  </AnimatePresence>

                  <div className="h-px bg-white/4" />

                  {/* Submit */}
                  <button
                    type="submit"
                    disabled={loading}
                    className="w-full flex items-center justify-center gap-2.5 py-3.5 rounded-xl text-sm font-semibold text-white
                      bg-[#8B5CF6] hover:bg-[#7C3AED] active:bg-[#6D28D9]
                      shadow-lg shadow-[#8B5CF6]/20 hover:shadow-[#8B5CF6]/30
                      transition-all duration-200 disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
                  >
                    {loading ? (
                      <>
                        <span className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                        Verificando…
                      </>
                    ) : (
                      <>
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
                        Reingresar
                      </>
                    )}
                  </button>

                  <p className="text-center text-[#9CA3AF] text-xs">
                    ¿Nuevo?{" "}
                    <Link
                      href="/join"
                      className="text-[#8B5CF6] hover:text-[#A78BFA] transition-colors duration-150"
                    >
                      Unirse a un torneo
                    </Link>
                  </p>
                </div>
              </form>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

export default function RejoinPage() {
  return (
    <Suspense>
      <RejoinContent />
    </Suspense>
  );
}
