"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "motion/react";
import Link from "next/link";
import FormInput from "../../Components/FormInput";
import Button from "../../Components/Button";
import { saveMemberToken, saveUserProfile } from "@/lib/tokenStorage";

type Phase = "form" | "success";

interface JoinResult {
  memberId: string;
  memberToken: string;
  tournamentName: string;
  displayName: string;
  code: string;
}

function CopyButton({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    await navigator.clipboard.writeText(value);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  return (
    <button
      onClick={handleCopy}
      className={`
        flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium
        transition-all duration-200 cursor-pointer shrink-0
        ${copied
          ? "bg-[#22C55E]/15 text-[#22C55E] border border-[#22C55E]/25"
          : "bg-[#131722] hover:bg-[#1A1F2E] text-[#9CA3AF] hover:text-[#F3F4F6] border border-white/[0.07]"
        }
      `}
    >
      {copied ? (
        <>
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="20 6 9 17 4 12" />
          </svg>
          Copiado
        </>
      ) : (
        <>
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
          </svg>
          Copiar
        </>
      )}
    </button>
  );
}

export default function JoinTournamentPage() {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>("form");
  const [code, setCode] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<JoinResult | null>(null);
  const [errors, setErrors] = useState<{ code?: string; displayName?: string; api?: string }>({});

  const validate = () => {
    const errs: Omit<typeof errors, "api"> = {};
    if (!code.trim()) errs.code = "Ingresa el código del torneo.";
    else if (code.trim().length < 5) errs.code = "Código demasiado corto.";
    if (!displayName.trim()) errs.displayName = "Ingresa tu nombre de jugador.";
    return errs;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const errs = validate();
    if (Object.keys(errs).length > 0) {
      setErrors(errs);
      return;
    }
    setErrors({});
    setLoading(true);

    try {
      const res = await fetch(`/api/tournaments/${code.trim()}/join`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ displayName: displayName.trim() }),
      });

      const data = await res.json();

      if (!res.ok) {
        setErrors({ api: data.error ?? "Error al unirse al torneo." });
        return;
      }

      // Guardar token y redirigir a la ruleta directamente
      saveMemberToken(data.code, data.memberToken);
      saveUserProfile(data.code, displayName.trim(), "member");
      router.push(`/roulette/${data.code}`);
    } catch {
      setErrors({ api: "No se pudo conectar con el servidor." });
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-6">
      {/* Faint background glow */}
      <div
        className="fixed pointer-events-none"
        style={{
          width: 450,
          height: 450,
          background: "radial-gradient(circle, rgba(139,92,246,0.07) 0%, transparent 65%)",
          top: "50%",
          left: "50%",
          transform: "translate(-30%, -50%)",
        }}
      />

      <div className="w-full max-w-110 z-10">
        <AnimatePresence mode="wait">
          {phase === "form" ? (
            <motion.div
              key="form"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -16, scale: 0.98 }}
              transition={{ duration: 0.4, ease: "easeOut" }}
            >
              {/* Back link */}
              <Link
                href="/"
                className="inline-flex items-center gap-2 text-[#9CA3AF] hover:text-[#F3F4F6] text-sm mb-6 transition-colors duration-150 group"
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="group-hover:-translate-x-0.5 transition-transform duration-150">
                  <polyline points="15 18 9 12 15 6" />
                </svg>
                Volver al inicio
              </Link>

              {/* Header */}
              <div className="mb-8">
                <h1 className="text-[#F3F4F6] text-3xl font-bold tracking-tight mb-2">
                  Unirse al Torneo
                </h1>
                <p className="text-[#9CA3AF] text-sm">
                  Ingresá el código e identifica tu equipo.
                </p>
              </div>

              {/* Form card */}
              <form
                onSubmit={handleSubmit}
                className="bg-[#131722] rounded-2xl border border-white/5 overflow-hidden"
              >
                <div className="h-px w-full bg-linear-to-r from-transparent via-[#8B5CF6]/40 to-transparent" />

                <div className="p-8 flex flex-col gap-6">
                  {/* Tournament Code */}
                  <FormInput
                    label="Código del Torneo"
                    placeholder="Ej. XYZ-1234-ABC"
                    value={code}
                    onChange={(e) => {
                      setCode(e.target.value.toUpperCase());
                      if (e.target.value.trim()) setErrors((er) => ({ ...er, code: undefined }));
                    }}
                    error={errors.code}
                    className="font-mono tracking-widest uppercase"
                    icon={
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                        <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                      </svg>
                    }
                  />

                  {/* Display Name */}
                  <FormInput
                    label="Tu Nombre de Jugador"
                    placeholder="Ej. David García"
                    value={displayName}
                    onChange={(e) => {
                      setDisplayName(e.target.value);
                      if (e.target.value.trim()) setErrors((er) => ({ ...er, displayName: undefined }));
                    }}
                    error={errors.displayName}
                    icon={
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                        <circle cx="12" cy="7" r="4" />
                      </svg>
                    }
                  />

                  {/* Info note */}
                  <div className="flex items-start gap-2.5 bg-[#8B5CF6]/5 border border-[#8B5CF6]/15 rounded-xl px-3.5 py-3">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 mt-0.5">
                      <circle cx="12" cy="12" r="10" />
                      <line x1="12" y1="8" x2="12" y2="12" />
                      <line x1="12" y1="16" x2="12.01" y2="16" />
                    </svg>
                    <p className="text-[#9CA3AF] text-xs leading-relaxed">
                      Necesitas el código del torneo. Pídelo al administrador que creó la partida.
                    </p>
                  </div>

                  {/* Divider */}
                  <div className="h-px bg-white/4" />

                  {/* API error */}
                  {errors.api && (
                    <div className="flex items-center gap-2.5 bg-[#EF4444]/8 border border-[#EF4444]/20 rounded-xl px-3.5 py-3">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                        <circle cx="12" cy="12" r="10" />
                        <line x1="12" y1="8" x2="12" y2="12" />
                        <line x1="12" y1="16" x2="12.01" y2="16" />
                      </svg>
                      <p className="text-[#EF4444] text-sm">{errors.api}</p>
                    </div>
                  )}

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
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                          <path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4" />
                          <polyline points="10 17 15 12 10 7" />
                          <line x1="15" y1="12" x2="3" y2="12" />
                        </svg>
                        Entrar
                      </>
                    )}
                  </button>

                  <p className="text-center text-[#9CA3AF] text-xs">
                    ¿Quieres crear un torneo?{" "}
                    <Link href="/create" className="text-[#8B5CF6] hover:text-[#A78BFA] transition-colors duration-150">
                      Crear uno nuevo
                    </Link>
                  </p>
                </div>
              </form>
            </motion.div>
          ) : (
            /* ── SUCCESS STATE ─────────────────────────────────── */
            <motion.div
              key="success"
              initial={{ opacity: 0, scale: 0.96, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              transition={{ duration: 0.5, ease: "easeOut" }}
            >
              <div className="bg-[#131722] rounded-2xl border border-[#22C55E]/20 overflow-hidden shadow-2xl shadow-[#22C55E]/5">
                <div className="h-1 w-full bg-linear-to-r from-transparent via-[#22C55E]/60 to-transparent" />

                <div className="p-8">
                  {/* Icon + title */}
                  <div className="flex items-center gap-4 mb-8">
                    <div className="w-12 h-12 rounded-2xl bg-[#22C55E]/10 border border-[#22C55E]/20 flex items-center justify-center shrink-0">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                        <polyline points="22 4 12 14.01 9 11.01" />
                      </svg>
                    </div>
                    <div>
                      <h2 className="text-[#F3F4F6] text-xl font-bold tracking-tight">
                        ¡Te uniste!
                      </h2>
                      <p className="text-[#9CA3AF] text-sm mt-0.5">
                        Bienvenido a{" "}
                        <span className="text-[#F3F4F6] font-medium">
                          {result?.tournamentName}
                        </span>
                      </p>
                    </div>
                  </div>

                  {/* Player identity */}
                  <div className="flex items-center gap-3 bg-[#0D0F14] rounded-xl px-4 py-3 mb-6 border border-white/4">
                    <div className="w-8 h-8 rounded-full bg-linear-to-br from-[#8B5CF6]/30 to-[#6D28D9]/30 border border-[#8B5CF6]/20 flex items-center justify-center shrink-0">
                      <span className="text-[#8B5CF6] text-xs font-bold">
                        {result?.displayName.charAt(0).toUpperCase()}
                      </span>
                    </div>
                    <div>
                      <p className="text-[#F3F4F6] text-sm font-medium">
                        {result?.displayName}
                      </p>
                      <p className="text-[#9CA3AF] text-xs">Participante</p>
                    </div>
                    <div className="ml-auto">
                      <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium bg-[#22C55E]/10 text-[#22C55E]">
                        <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E] animate-pulse" />
                        Activo
                      </span>
                    </div>
                  </div>

                  {/* Member Token */}
                  <div className="flex flex-col gap-2 mb-6">
                    <div className="flex items-center justify-between">
                      <label className="text-[#9CA3AF] text-xs uppercase tracking-wider font-semibold">
                        Tu Token de Miembro
                      </label>
                      <CopyButton value={result?.memberToken ?? ""} />
                    </div>
                    <div className="bg-[#0D0F14] border border-white/[0.07] rounded-xl px-4 py-3">
                      <span className="font-mono text-[#9CA3AF] text-xs tracking-wider break-all">
                        {result?.memberToken}
                      </span>
                    </div>
                  </div>

                  {/* Storage confirmation */}
                  <div className="flex items-start gap-2.5 bg-[#22C55E]/5 border border-[#22C55E]/15 rounded-xl px-3.5 py-3 mb-8">
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 mt-0.5">
                      <path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" />
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                    <p className="text-[#22C55E]/80 text-xs leading-relaxed">
                      Token guardado automáticamente en este navegador. Puedes copiarlo como respaldo por si cambias de dispositivo.
                    </p>
                  </div>

                  {/* Actions */}
                  <div className="flex gap-3">
                    <Button
                      variant="primary"
                      size="md"
                      className="flex-1"
                      onClick={() => router.push(`/lobby/${result?.code}`)}
                    >
                      Ir al Lobby
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <polyline points="9 18 15 12 9 6" />
                      </svg>
                    </Button>
                    <Button
                      variant="ghost"
                      size="md"
                      onClick={() => {
                        setPhase("form");
                        setCode("");
                        setDisplayName("");
                        setResult(null);
                        setErrors({});
                      }}
                    >
                      Otro torneo
                    </Button>
                  </div>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
