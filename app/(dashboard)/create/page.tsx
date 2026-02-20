"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { motion, AnimatePresence } from "motion/react";
import Link from "next/link";
import FormInput from "../../Components/FormInput";
import Button from "../../Components/Button";
import { saveAdminToken, saveMemberToken } from "@/lib/tokenStorage";

type Phase = "form" | "success";

interface TournamentResult {
  id: string;
  code: string;
  adminToken: string;
  memberToken: string | null;
  memberId: string | null;
  rerolls: number;
  createdAt: string;
}

interface CopyButtonProps {
  value: string;
}

function CopyButton({ value }: CopyButtonProps) {
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

export default function CreateTournamentPage() {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>("form");
  const [name, setName] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [rerolls, setRerolls] = useState(1);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<TournamentResult | null>(null);
  const [errors, setErrors] = useState<{ name?: string; displayName?: string }>({});
  const [apiError, setApiError] = useState("");

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const errs: typeof errors = {};
    if (!name.trim()) errs.name = "El nombre del torneo es obligatorio.";
    if (!displayName.trim()) errs.displayName = "Tu nombre de jugador es obligatorio.";
    if (Object.keys(errs).length > 0) { setErrors(errs); return; }
    setErrors({});
    setApiError("");
    setLoading(true);

    try {
      const res = await fetch("/api/tournaments", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: name.trim(), displayName: displayName.trim(), rerolls }),
      });

      const data = await res.json();

      if (!res.ok) {
        setApiError(data.error ?? "Error al crear el torneo. Inténtalo de nuevo.");
        return;
      }

      const tournament = data as TournamentResult;
      saveAdminToken(tournament.code, tournament.adminToken);
      if (tournament.memberToken) {
        saveMemberToken(tournament.code, tournament.memberToken);
      }
      // Ir directo a la ruleta para que el admin también gire
      router.push(`/roulette/${tournament.code}`);
    } catch {
      setApiError("No se pudo conectar con el servidor.");
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
          width: 500,
          height: 500,
          background: "radial-gradient(circle, rgba(139,92,246,0.07) 0%, transparent 65%)",
          top: "50%",
          left: "50%",
          transform: "translate(-30%, -50%)",
        }}
      />

      <div className="w-full max-w-125 z-10">
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
                  Crear Torneo
                </h1>
                <p className="text-[#9CA3AF] text-sm">
                  Configura tu mercado y empieza el draft.
                </p>
              </div>

              {/* Form card */}
              <form
                onSubmit={handleSubmit}
                className="bg-[#131722] rounded-2xl border border-white/5 overflow-hidden"
              >
                {/* Top accent */}
                <div className="h-px w-full bg-linear-to-r from-transparent via-[#8B5CF6]/40 to-transparent" />

                <div className="p-8 flex flex-col gap-7">
                  {/* Tournament name */}
                  <FormInput
                    label="Nombre del Torneo"
                    placeholder="Ej. Liga Verano 2026"
                    value={name}
                    onChange={(e) => {
                      setName(e.target.value);
                      if (e.target.value.trim()) setErrors((p) => ({ ...p, name: undefined }));
                    }}
                    error={errors.name}
                    icon={
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
                      </svg>
                    }
                  />

                  {/* Display name */}
                  <FormInput
                    label="Tu Nombre de Jugador"
                    placeholder="Ej. David García"
                    value={displayName}
                    onChange={(e) => {
                      setDisplayName(e.target.value);
                      if (e.target.value.trim()) setErrors((p) => ({ ...p, displayName: undefined }));
                    }}
                    error={errors.displayName}
                    hint="Así te verán los demás participantes en el lobby."
                    icon={
                      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                        <circle cx="12" cy="7" r="4" />
                      </svg>
                    }
                  />

                  {/* Budget Range — display only */}
                  <div className="flex flex-col gap-2">
                    <div className="flex items-center justify-between">
                      <label className="text-[#F3F4F6] text-sm font-medium">
                        Rango de Presupuesto
                      </label>
                      <span className="text-[#9CA3AF] text-xs">Fijo</span>
                    </div>
                    <div className="bg-[#0D0F14] border border-white/[0.07] rounded-xl p-4">
                      <div className="flex items-center justify-between mb-3">
                        <div className="text-center">
                          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mb-1">Mínimo</p>
                          <p className="text-[#F3F4F6] text-lg font-semibold">€100M</p>
                        </div>
                        <div className="flex-1 mx-5 flex flex-col items-center gap-2">
                          <div className="w-full h-1 bg-[#1A1F2E] rounded-full overflow-hidden">
                            <div className="h-full bg-linear-to-r from-[#8B5CF6] to-[#6D28D9] rounded-full w-full" />
                          </div>
                          <span className="text-[#9CA3AF] text-[10px]">Asignado por ruleta</span>
                        </div>
                        <div className="text-center">
                          <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mb-1">Máximo</p>
                          <p className="text-[#F3F4F6] text-lg font-semibold">€400M</p>
                        </div>
                      </div>
                    </div>
                    <p className="text-[#9CA3AF] text-xs">
                      El presupuesto exacto se asigna al girar la ruleta.
                    </p>
                  </div>

                  {/* Rerolls stepper */}
                  <div className="flex flex-col gap-2">
                    <div className="flex items-center justify-between">
                      <label className="text-[#F3F4F6] text-sm font-medium">
                        Rerolls Permitidos
                      </label>
                      <span className="text-[#9CA3AF] text-xs">Por participante</span>
                    </div>
                    <div className="bg-[#0D0F14] border border-white/[0.07] rounded-xl px-4 py-3 flex items-center justify-between">
                      <p className="text-[#9CA3AF] text-sm">
                        Veces que se puede girar de nuevo
                      </p>
                      <div className="flex items-center gap-3">
                        <button
                          type="button"
                          onClick={() => setRerolls((r) => Math.max(0, r - 1))}
                          className="w-8 h-8 rounded-lg bg-[#131722] border border-white/[0.07] hover:border-[#8B5CF6]/30 hover:bg-[#1A1F2E] flex items-center justify-center text-[#9CA3AF] hover:text-[#F3F4F6] transition-all duration-150 cursor-pointer"
                        >
                          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                            <line x1="5" y1="12" x2="19" y2="12" />
                          </svg>
                        </button>
                        <span className="text-[#F3F4F6] text-lg font-semibold w-6 text-center tabular-nums">
                          {rerolls}
                        </span>
                        <button
                          type="button"
                          onClick={() => setRerolls((r) => Math.min(5, r + 1))}
                          className="w-8 h-8 rounded-lg bg-[#131722] border border-white/[0.07] hover:border-[#8B5CF6]/30 hover:bg-[#1A1F2E] flex items-center justify-center text-[#9CA3AF] hover:text-[#F3F4F6] transition-all duration-150 cursor-pointer"
                        >
                          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                            <line x1="12" y1="5" x2="12" y2="19" />
                            <line x1="5" y1="12" x2="19" y2="12" />
                          </svg>
                        </button>
                      </div>
                    </div>
                  </div>

                  {/* Divider */}
                  <div className="h-px bg-white/4" />

                  {/* API error */}
                  {apiError && (
                    <div className="flex items-center gap-2.5 bg-[#EF4444]/8 border border-[#EF4444]/20 rounded-xl px-3.5 py-3">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0">
                        <circle cx="12" cy="12" r="10" />
                        <line x1="12" y1="8" x2="12" y2="12" />
                        <line x1="12" y1="16" x2="12.01" y2="16" />
                      </svg>
                      <p className="text-[#EF4444] text-sm">{apiError}</p>
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
                        Creando torneo…
                      </>
                    ) : (
                      <>
                        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                          <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
                        </svg>
                        Crear Torneo
                      </>
                    )}
                  </button>
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
              {/* Success card */}
              <div className="bg-[#131722] rounded-2xl border border-[#22C55E]/20 overflow-hidden shadow-2xl shadow-[#22C55E]/5">
                {/* Green accent top bar */}
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
                        ¡Torneo creado!
                      </h2>
                      <p className="text-[#9CA3AF] text-sm mt-0.5">
                        Comparte el código con los participantes.
                      </p>
                    </div>
                  </div>

                  {/* Tournament name pill */}
                  <div className="flex items-center gap-2 mb-6">
                    <span className="text-[#9CA3AF] text-xs">Torneo:</span>
                    <span className="text-[#F3F4F6] text-xs font-medium px-2.5 py-1 bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 rounded-full">
                      {name}
                    </span>
                  </div>

                  <div className="flex flex-col gap-5">
                    {/* Tournament Code */}
                    <div className="flex flex-col gap-2">
                      <div className="flex items-center justify-between">
                        <label className="text-[#9CA3AF] text-xs uppercase tracking-wider font-semibold">
                          Código del Torneo
                        </label>
                        <CopyButton value={result?.code ?? ""} />
                      </div>
                      <div className="bg-[#0D0F14] border border-[#22C55E]/15 rounded-xl px-5 py-4 flex items-center justify-between">
                        <span className="font-mono text-[#F3F4F6] text-2xl font-bold tracking-[0.15em]">
                          {result?.code}
                        </span>
                        <span className="w-2 h-2 rounded-full bg-[#22C55E] animate-pulse ml-3 shrink-0" />
                      </div>
                      <p className="text-[#9CA3AF] text-xs">
                        Comparte este código para que los participantes puedan unirse.
                      </p>
                    </div>

                    {/* Divider */}
                    <div className="h-px bg-white/4" />

                    {/* Admin Token */}
                    <div className="flex flex-col gap-2">
                      <div className="flex items-center justify-between">
                        <label className="text-[#9CA3AF] text-xs uppercase tracking-wider font-semibold">
                          Token de Administrador
                        </label>
                        <CopyButton value={result?.adminToken ?? ""} />
                      </div>
                      <div className="bg-[#0D0F14] border border-white/[0.07] rounded-xl px-4 py-3">
                        <span className="font-mono text-[#9CA3AF] text-xs tracking-wider break-all">
                          {result?.adminToken}
                        </span>
                      </div>
                      <div className="flex items-start gap-2 bg-[#22C55E]/5 border border-[#22C55E]/15 rounded-xl px-3.5 py-2.5">
                        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="shrink-0 mt-0.5">
                          <path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" />
                          <polyline points="20 6 9 17 4 12" />
                        </svg>
                        <p className="text-[#22C55E]/80 text-xs leading-relaxed">
                          Token guardado automáticamente en este navegador. Puedes copiarlo como respaldo.
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="flex gap-3 mt-8">
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
                        setName("");
                        setDisplayName("");
                        setRerolls(1);
                        setResult(null);
                        setErrors({});
                        setApiError("");
                      }}
                    >
                      Nuevo torneo
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
