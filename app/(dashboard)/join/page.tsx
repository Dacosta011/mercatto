"use client";

import { useState, useEffect, useRef } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { Suspense } from "react";
import { motion, AnimatePresence } from "motion/react";
import Link from "next/link";
import FormInput from "../../Components/FormInput";
import {
  saveMemberToken,
  saveMemberId,
  saveUserProfile,
} from "@/lib/tokenStorage";

type Phase = "form" | "magic-link";

interface JoinResult {
  memberId: string;
  memberToken: string;
  tournamentName: string;
  displayName: string;
  code: string;
}

function CopyButton({ value, label }: { value: string; label?: string }) {
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
        ${
          copied
            ? "bg-[#22C55E]/15 text-[#22C55E] border border-[#22C55E]/25"
            : "bg-[#131722] hover:bg-[#1A1F2E] text-[#9CA3AF] hover:text-[#F3F4F6] border border-white/8"
        }
      `}
    >
      {copied ? (
        <>
          <svg
            width="12"
            height="12"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2.5"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <polyline points="20 6 9 17 4 12" />
          </svg>
          Copiado
        </>
      ) : (
        <>
          <svg
            width="12"
            height="12"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            <rect x="9" y="9" width="13" height="13" rx="2" ry="2" />
            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
          </svg>
          {label ?? "Copiar"}
        </>
      )}
    </button>
  );
}

function QRCode({ url }: { url: string }) {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const size = 200;
    canvas.width = size;
    canvas.height = size;

    const moduleCount = 25;
    const cellSize = size / moduleCount;

    // Simple visual QR pattern (not scannable - we show the link for copying)
    // For a real QR we'd use a library, but this gives the visual cue
    ctx.fillStyle = "#0D0F14";
    ctx.fillRect(0, 0, size, size);

    // Generate deterministic pattern from URL
    let hash = 0;
    for (let i = 0; i < url.length; i++) {
      hash = ((hash << 5) - hash + url.charCodeAt(i)) | 0;
    }

    ctx.fillStyle = "#F3F4F6";

    // Position patterns (corners)
    const drawFinder = (x: number, y: number) => {
      for (let r = 0; r < 7; r++) {
        for (let c = 0; c < 7; c++) {
          const outer = r === 0 || r === 6 || c === 0 || c === 6;
          const inner = r >= 2 && r <= 4 && c >= 2 && c <= 4;
          if (outer || inner) {
            ctx.fillRect(
              (x + c) * cellSize,
              (y + r) * cellSize,
              cellSize,
              cellSize
            );
          }
        }
      }
    };

    drawFinder(0, 0);
    drawFinder(moduleCount - 7, 0);
    drawFinder(0, moduleCount - 7);

    // Data area
    const seed = Math.abs(hash);
    for (let r = 0; r < moduleCount; r++) {
      for (let c = 0; c < moduleCount; c++) {
        const inFinder =
          (r < 8 && c < 8) ||
          (r < 8 && c > moduleCount - 9) ||
          (r > moduleCount - 9 && c < 8);
        if (inFinder) continue;

        const val = ((seed * (r * moduleCount + c + 1)) >> 3) & 1;
        if (val) {
          ctx.fillRect(c * cellSize, r * cellSize, cellSize, cellSize);
        }
      }
    }
  }, [url]);

  return (
    <canvas
      ref={canvasRef}
      className="rounded-xl border border-white/8"
      style={{ width: 160, height: 160 }}
    />
  );
}

export default function JoinTournamentPage() {
  return (
    <Suspense>
      <JoinForm />
    </Suspense>
  );
}

function JoinForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [phase, setPhase] = useState<Phase>("form");
  const [code, setCode] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState<JoinResult | null>(null);
  const [errors, setErrors] = useState<{
    code?: string;
    displayName?: string;
    api?: string;
  }>({});

  useEffect(() => {
    const prefill = searchParams.get("code");
    if (prefill) setCode(prefill.toUpperCase());
  }, [searchParams]);

  const validate = () => {
    const errs: Omit<typeof errors, "api"> = {};
    if (!code.trim()) errs.code = "Ingresa el código del torneo.";
    else if (code.trim().length < 5) errs.code = "Código demasiado corto.";
    if (!displayName.trim())
      errs.displayName = "Ingresa tu nombre de jugador.";
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

      saveMemberToken(data.code, data.memberToken);
      if (data.memberId) saveMemberId(data.code, data.memberId);
      saveUserProfile(data.code, displayName.trim(), "member");

      setResult(data);
      setPhase("magic-link");
    } catch {
      setErrors({ api: "No se pudo conectar con el servidor." });
    } finally {
      setLoading(false);
    }
  };

  const magicLink = result
    ? `${typeof window !== "undefined" ? window.location.origin : ""}/rejoin?code=${result.code}&token=${result.memberToken}`
    : "";

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
        <AnimatePresence mode="wait">
          {phase === "form" ? (
            <motion.div
              key="form"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -16, scale: 0.98 }}
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
                <h1 className="text-[#F3F4F6] text-2xl sm:text-3xl font-bold tracking-tight mb-1.5 sm:mb-2">
                  Unirse al Torneo
                </h1>
                <p className="text-[#9CA3AF] text-sm">
                  Ingresá el código e identifica tu equipo.
                </p>
              </div>

              <form
                onSubmit={handleSubmit}
                className="bg-[#131722] rounded-2xl border border-white/5 overflow-hidden"
              >
                <div className="h-px w-full bg-linear-to-r from-transparent via-[#8B5CF6]/40 to-transparent" />

                <div className="p-5 sm:p-8 flex flex-col gap-5 sm:gap-6">
                  <FormInput
                    label="Código del Torneo"
                    placeholder="Ej. XYZ-1234-ABC"
                    value={code}
                    onChange={(e) => {
                      setCode(e.target.value.toUpperCase());
                      if (e.target.value.trim())
                        setErrors((er) => ({ ...er, code: undefined }));
                    }}
                    error={errors.code}
                    className="font-mono tracking-widest uppercase"
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
                        <rect
                          x="3"
                          y="11"
                          width="18"
                          height="11"
                          rx="2"
                          ry="2"
                        />
                        <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                      </svg>
                    }
                  />

                  <FormInput
                    label="Tu Nombre de Jugador"
                    placeholder="Ej. David García"
                    value={displayName}
                    onChange={(e) => {
                      setDisplayName(e.target.value);
                      if (e.target.value.trim())
                        setErrors((er) => ({
                          ...er,
                          displayName: undefined,
                        }));
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
                      Necesitas el código del torneo. Pídelo al administrador
                      que creó la partida.
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
                        Entrar
                      </>
                    )}
                  </button>

                  <div className="flex items-center justify-center gap-3 text-xs">
                    <Link
                      href="/create"
                      className="text-[#8B5CF6] hover:text-[#A78BFA] transition-colors duration-150"
                    >
                      Crear torneo
                    </Link>
                    <span className="text-[#9CA3AF]/30">·</span>
                    <Link
                      href="/rejoin"
                      className="text-[#9CA3AF] hover:text-[#F3F4F6] transition-colors duration-150"
                    >
                      Reingresar con enlace
                    </Link>
                  </div>
                </div>
              </form>
            </motion.div>
          ) : (
            /* ── MAGIC LINK SCREEN ─────────────────────────────── */
            <motion.div
              key="magic-link"
              initial={{ opacity: 0, scale: 0.96, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              transition={{ duration: 0.5, ease: "easeOut" }}
            >
              <div className="bg-[#131722] rounded-2xl border border-[#8B5CF6]/20 overflow-hidden shadow-2xl shadow-[#8B5CF6]/5">
                <div className="h-1 w-full bg-linear-to-r from-transparent via-[#8B5CF6]/60 to-transparent" />

                <div className="p-5 sm:p-8">
                  {/* Header */}
                  <div className="flex items-center gap-3 sm:gap-4 mb-5 sm:mb-6">
                    <div className="w-12 h-12 rounded-2xl bg-[#22C55E]/10 border border-[#22C55E]/20 flex items-center justify-center shrink-0">
                      <svg
                        width="22"
                        height="22"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="#22C55E"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                        <polyline points="22 4 12 14.01 9 11.01" />
                      </svg>
                    </div>
                    <div>
                      <h2 className="text-[#F3F4F6] text-lg sm:text-xl font-bold tracking-tight">
                        ¡Te uniste a {result?.tournamentName}!
                      </h2>
                      <p className="text-[#9CA3AF] text-sm mt-0.5">
                        Guarda tu enlace de acceso
                      </p>
                    </div>
                  </div>

                  {/* Warning */}
                  <div className="flex items-start gap-2.5 bg-[#F59E0B]/5 border border-[#F59E0B]/20 rounded-xl px-4 py-3 mb-6">
                    <svg
                      width="16"
                      height="16"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="#F59E0B"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      className="shrink-0 mt-0.5"
                    >
                      <path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z" />
                      <line x1="12" y1="9" x2="12" y2="13" />
                      <line x1="12" y1="17" x2="12.01" y2="17" />
                    </svg>
                    <div>
                      <p className="text-[#F59E0B] text-sm font-semibold">
                        Este enlace es tu llave
                      </p>
                      <p className="text-[#9CA3AF] text-xs mt-0.5 leading-relaxed">
                        Guárdalo para poder entrar desde otro dispositivo o
                        navegador. Si lo pierdes, no podrás recuperar tu cuenta.
                      </p>
                    </div>
                  </div>

                  {/* Magic Link */}
                  <div className="mb-6">
                    <div className="flex items-center justify-between mb-2">
                      <label className="text-[#9CA3AF] text-xs uppercase tracking-wider font-semibold">
                        Tu Enlace Mágico
                      </label>
                      <CopyButton value={magicLink} label="Copiar enlace" />
                    </div>
                    <div className="bg-[#0D0F14] border border-white/8 rounded-xl px-4 py-3">
                      <span className="font-mono text-[#8B5CF6] text-xs break-all leading-relaxed">
                        {magicLink}
                      </span>
                    </div>
                  </div>

                  {/* QR + Info */}
                  <div className="flex flex-col sm:flex-row gap-4 sm:gap-5 mb-5 sm:mb-6">
                    <div className="shrink-0 flex flex-col items-center sm:items-start">
                      <QRCode url={magicLink} />
                      <p className="text-[#6B7280] text-[10px] text-center mt-2">
                        Referencia visual
                      </p>
                    </div>
                    <div className="flex flex-col gap-3 flex-1 min-w-0">
                      {/* Player info */}
                      <div className="flex items-center gap-3 bg-[#0D0F14] rounded-xl px-4 py-3 border border-white/4">
                        <div className="w-8 h-8 rounded-full bg-linear-to-br from-[#8B5CF6]/30 to-[#6D28D9]/30 border border-[#8B5CF6]/20 flex items-center justify-center shrink-0">
                          <span className="text-[#8B5CF6] text-xs font-bold">
                            {result?.displayName.charAt(0).toUpperCase()}
                          </span>
                        </div>
                        <div className="min-w-0">
                          <p className="text-[#F3F4F6] text-sm font-medium truncate">
                            {result?.displayName}
                          </p>
                          <p className="text-[#9CA3AF] text-[10px]">
                            {result?.code}
                          </p>
                        </div>
                      </div>

                      {/* How to use */}
                      <div className="space-y-2 text-[#9CA3AF] text-xs">
                        <div className="flex items-start gap-2">
                          <span className="w-4 h-4 rounded-full bg-[#8B5CF6]/10 text-[#8B5CF6] text-[10px] font-bold flex items-center justify-center shrink-0 mt-0.5">
                            1
                          </span>
                          <span>Copia el enlace o compártelo contigo mismo</span>
                        </div>
                        <div className="flex items-start gap-2">
                          <span className="w-4 h-4 rounded-full bg-[#8B5CF6]/10 text-[#8B5CF6] text-[10px] font-bold flex items-center justify-center shrink-0 mt-0.5">
                            2
                          </span>
                          <span>Ábrelo en cualquier dispositivo o navegador</span>
                        </div>
                        <div className="flex items-start gap-2">
                          <span className="w-4 h-4 rounded-full bg-[#8B5CF6]/10 text-[#8B5CF6] text-[10px] font-bold flex items-center justify-center shrink-0 mt-0.5">
                            3
                          </span>
                          <span>Tu sesión se restaurará automáticamente</span>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Saved confirmation */}
                  <div className="flex items-start gap-2.5 bg-[#22C55E]/5 border border-[#22C55E]/15 rounded-xl px-3.5 py-3 mb-6">
                    <svg
                      width="13"
                      height="13"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="#22C55E"
                      strokeWidth="2"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      className="shrink-0 mt-0.5"
                    >
                      <path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" />
                      <polyline points="9 12 11 14 15 10" />
                    </svg>
                    <p className="text-[#22C55E]/80 text-xs leading-relaxed">
                      Sesión guardada automáticamente en este navegador. El
                      enlace es tu respaldo para otros dispositivos.
                    </p>
                  </div>

                  {/* Actions */}
                  <button
                    onClick={() =>
                      router.push(`/roulette/${result?.code}`)
                    }
                    className="w-full flex items-center justify-center gap-2.5 py-3.5 rounded-xl text-sm font-semibold text-white
                      bg-[#8B5CF6] hover:bg-[#7C3AED] active:bg-[#6D28D9]
                      shadow-lg shadow-[#8B5CF6]/20 hover:shadow-[#8B5CF6]/30
                      transition-all duration-200 cursor-pointer"
                  >
                    Continuar al Sorteo
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
                      <polyline points="9 18 15 12 9 6" />
                    </svg>
                  </button>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}
