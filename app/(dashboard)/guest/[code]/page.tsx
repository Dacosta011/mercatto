"use client";

import { useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { motion } from "motion/react";
import Link from "next/link";
import FormInput from "../../../Components/FormInput";
import {
  saveMemberToken,
  saveMemberId,
  saveUserProfile,
  saveTournamentStatus,
} from "@/lib/tokenStorage";

export default function GuestJoinPage() {
  const { code } = useParams<{ code: string }>();
  const router = useRouter();
  const [displayName, setDisplayName] = useState("");
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<{ displayName?: string; api?: string }>({});

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!displayName.trim()) {
      setErrors({ displayName: "Ingresa un nombre para continuar." });
      return;
    }
    setErrors({});
    setLoading(true);

    try {
      const res = await fetch(`/api/tournaments/${code}/guest`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ displayName: displayName.trim() }),
      });

      const data = await res.json();

      if (!res.ok) {
        setErrors({ api: data.error ?? "Error al ingresar como invitado." });
        return;
      }

      saveMemberToken(data.code, data.memberToken);
      saveMemberId(data.code, data.memberId);
      saveUserProfile(data.code, displayName.trim(), "guest");
      saveTournamentStatus(data.code, "league");

      router.push("/calendar");
    } catch {
      setErrors({ api: "No se pudo conectar con el servidor." });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-dvh flex items-center justify-center p-4 sm:p-6">
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

      <div className="w-full max-w-lg z-10">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.4, ease: "easeOut" }}
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

          <div className="mb-6 sm:mb-8">
            <div className="flex items-center gap-2.5 mb-3">
              <span className="px-2.5 py-1 rounded-lg bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 text-[#8B5CF6] text-[10px] font-bold uppercase tracking-widest">
                Invitado
              </span>
            </div>
            <h1 className="text-[#F3F4F6] text-2xl sm:text-3xl font-bold tracking-tight mb-1.5 sm:mb-2">
              Entrar como Espectador
            </h1>
            <p className="text-[#9CA3AF] text-sm">
              Podrás ver la clasificación, el calendario y participar en el feed social.
            </p>
          </div>

          <form
            onSubmit={handleSubmit}
            className="bg-[#131722] rounded-2xl border border-white/5 overflow-hidden"
          >
            <div className="h-px w-full bg-linear-to-r from-transparent via-[#8B5CF6]/40 to-transparent" />

            <div className="p-5 sm:p-8 flex flex-col gap-5 sm:gap-6">
              <FormInput
                label="Tu Nombre"
                placeholder="Ej. Carlos López"
                value={displayName}
                onChange={(e) => {
                  setDisplayName(e.target.value);
                  if (e.target.value.trim())
                    setErrors((er) => ({ ...er, displayName: undefined }));
                }}
                error={errors.displayName}
                icon={
                  <svg
                    width="15"
                    height="15"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                    <circle cx="12" cy="7" r="4" />
                  </svg>
                }
              />

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
                  Como invitado puedes ver la liga y participar en el feed, pero no
                  tendrás equipo ni participarás en los partidos.
                </p>
              </div>

              <div className="h-px bg-white/4" />

              {errors.api && (
                <div className="flex items-center gap-2.5 bg-[#EF4444]/8 border border-[#EF4444]/20 rounded-xl px-3.5 py-3">
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
                    <line x1="12" y1="8" x2="12" y2="12" />
                    <line x1="12" y1="16" x2="12.01" y2="16" />
                  </svg>
                  <p className="text-[#EF4444] text-sm">{errors.api}</p>
                </div>
              )}

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
                    Ingresando…
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
                      <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                      <circle cx="12" cy="12" r="3" />
                    </svg>
                    Entrar como Espectador
                  </>
                )}
              </button>
            </div>
          </form>
        </motion.div>
      </div>
    </div>
  );
}
