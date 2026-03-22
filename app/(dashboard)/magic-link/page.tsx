"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { motion } from "motion/react";
import {
  getLastTournamentCode,
  getMemberToken,
  saveMemberToken,
} from "@/lib/tokenStorage";

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

    let hash = 0;
    for (let i = 0; i < url.length; i++) {
      hash = ((hash << 5) - hash + url.charCodeAt(i)) | 0;
    }

    ctx.fillStyle = "#0D0F14";
    ctx.fillRect(0, 0, size, size);
    ctx.fillStyle = "#F3F4F6";

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

    const seed = Math.abs(hash);
    for (let r = 0; r < moduleCount; r++) {
      for (let c = 0; c < moduleCount; c++) {
        const inFinder =
          (r < 8 && c < 8) ||
          (r < 8 && c > moduleCount - 9) ||
          (r > moduleCount - 9 && c < 8);
        if (inFinder) continue;
        if (((seed * (r * moduleCount + c + 1)) >> 3) & 1) {
          ctx.fillRect(c * cellSize, r * cellSize, cellSize, cellSize);
        }
      }
    }
  }, [url]);

  return (
    <canvas
      ref={canvasRef}
      className="rounded-xl border border-white/8"
      style={{ width: 180, height: 180 }}
    />
  );
}

export default function MagicLinkPage() {
  const [code, setCode] = useState<string | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);
  const [regenerating, setRegenerating] = useState(false);
  const [showConfirmRegen, setShowConfirmRegen] = useState(false);

  useEffect(() => {
    const c = getLastTournamentCode();
    if (c) {
      setCode(c);
      setToken(getMemberToken(c));
    }
  }, []);

  const magicLink =
    code && token
      ? `${typeof window !== "undefined" ? window.location.origin : ""}/rejoin?code=${code}&token=${token}`
      : null;

  const handleCopy = useCallback(async () => {
    if (!magicLink) return;
    await navigator.clipboard.writeText(magicLink);
    setCopied(true);
    setTimeout(() => setCopied(false), 2500);
  }, [magicLink]);

  const handleShare = useCallback(async () => {
    if (!magicLink) return;
    if (navigator.share) {
      try {
        await navigator.share({
          title: "Mi enlace Mercatto",
          text: "Enlace para reingresar al torneo",
          url: magicLink,
        });
      } catch {
        handleCopy();
      }
    } else {
      handleCopy();
    }
  }, [magicLink, handleCopy]);

  const handleRegenerate = async () => {
    if (!code || !token) return;
    setRegenerating(true);
    try {
      const res = await fetch(
        `/api/tournaments/${code}/regenerate-token`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
        }
      );
      const data = await res.json();
      if (res.ok && data.newToken) {
        saveMemberToken(code, data.newToken);
        setToken(data.newToken);
        setShowConfirmRegen(false);
      }
    } catch {
      // silent
    } finally {
      setRegenerating(false);
    }
  };

  if (!code || !token) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <div className="w-14 h-14 rounded-2xl bg-[#131722] border border-white/8 flex items-center justify-center mx-auto mb-4">
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="#9CA3AF"
              strokeWidth="1.75"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
              <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
            </svg>
          </div>
          <p className="text-[#F3F4F6] font-semibold">Sin sesión activa</p>
          <p className="text-[#9CA3AF] text-sm mt-1">
            Únete a un torneo para obtener tu enlace mágico
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-dvh flex items-center justify-center p-4 sm:p-6">
      <div
        className="fixed pointer-events-none"
        style={{
          width: 500,
          height: 500,
          background:
            "radial-gradient(circle, rgba(139,92,246,0.06) 0%, transparent 65%)",
          top: "50%",
          left: "50%",
          transform: "translate(-50%, -50%)",
        }}
      />

      <motion.div
        initial={{ opacity: 0, y: 16 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.4 }}
        className="w-full max-w-lg z-10"
      >
        {/* Header */}
        <div className="mb-5 sm:mb-6">
          <h1 className="text-[#F3F4F6] text-xl sm:text-2xl font-bold tracking-tight flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center shrink-0">
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
                <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71" />
                <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71" />
              </svg>
            </div>
            Tu Acceso al Torneo
          </h1>
          <p className="text-[#9CA3AF] text-sm mt-2 ml-13">
            Usa este enlace para entrar desde cualquier dispositivo
          </p>
        </div>

        <div className="bg-[#131722] rounded-2xl border border-white/5 overflow-hidden">
          <div className="h-px w-full bg-linear-to-r from-transparent via-[#8B5CF6]/30 to-transparent" />

          <div className="p-4 sm:p-6 space-y-5 sm:space-y-6">
            {/* Magic Link */}
            <div>
              <label className="text-[#9CA3AF] text-xs uppercase tracking-wider font-semibold mb-2 block">
                Enlace Mágico
              </label>
              <div className="bg-[#0D0F14] border border-white/8 rounded-xl px-4 py-3 mb-3">
                <span className="font-mono text-[#8B5CF6] text-xs break-all leading-relaxed">
                  {magicLink}
                </span>
              </div>
              <div className="flex gap-2">
                <button
                  onClick={handleCopy}
                  className={`flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-medium transition-all cursor-pointer ${
                    copied
                      ? "bg-[#22C55E]/10 text-[#22C55E] border border-[#22C55E]/25"
                      : "bg-[#8B5CF6] hover:bg-[#7C3AED] text-white shadow-lg shadow-[#8B5CF6]/20"
                  }`}
                >
                  {copied ? (
                    <>
                      <svg
                        width="14"
                        height="14"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2.5"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <polyline points="20 6 9 17 4 12" />
                      </svg>
                      Enlace copiado
                    </>
                  ) : (
                    <>
                      <svg
                        width="14"
                        height="14"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="2"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <rect
                          x="9"
                          y="9"
                          width="13"
                          height="13"
                          rx="2"
                          ry="2"
                        />
                        <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
                      </svg>
                      Copiar enlace
                    </>
                  )}
                </button>
                <button
                  onClick={handleShare}
                  className="px-4 py-2.5 rounded-xl border border-white/10 text-[#9CA3AF] hover:text-[#F3F4F6] hover:border-white/20 transition-all cursor-pointer"
                  title="Compartir"
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
                    <circle cx="18" cy="5" r="3" />
                    <circle cx="6" cy="12" r="3" />
                    <circle cx="18" cy="19" r="3" />
                    <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
                    <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
                  </svg>
                </button>
              </div>
            </div>

            <div className="h-px bg-white/4" />

            {/* QR Code */}
            <div className="flex flex-col items-center gap-3">
              <QRCode url={magicLink!} />
              <p className="text-[#6B7280] text-xs">Referencia visual</p>
            </div>

            <div className="h-px bg-white/4" />

            {/* Warning */}
            <div className="flex items-start gap-2.5 bg-[#F59E0B]/5 border border-[#F59E0B]/20 rounded-xl px-3.5 py-3">
              <svg
                width="14"
                height="14"
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
              <p className="text-[#9CA3AF] text-xs leading-relaxed">
                <strong className="text-[#F59E0B]">No compartas</strong> este
                enlace con otros jugadores. Es tu identidad única en el torneo.
              </p>
            </div>

            {/* Regenerate */}
            <div className="rounded-xl border border-white/6 bg-[#0D0F14]/50 p-3 sm:p-4">
              <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                <div>
                  <p className="text-[#F3F4F6] text-sm font-medium">
                    Regenerar enlace
                  </p>
                  <p className="text-[#6B7280] text-xs mt-0.5">
                    Invalida el enlace anterior y genera uno nuevo
                  </p>
                </div>
                {!showConfirmRegen ? (
                  <button
                    onClick={() => setShowConfirmRegen(true)}
                    className="px-3 py-1.5 rounded-lg border border-[#EF4444]/20 text-[#EF4444] text-xs font-medium hover:bg-[#EF4444]/10 transition-colors cursor-pointer"
                  >
                    Regenerar
                  </button>
                ) : (
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => setShowConfirmRegen(false)}
                      className="px-3 py-1.5 rounded-lg border border-white/10 text-[#9CA3AF] text-xs font-medium hover:text-[#F3F4F6] transition-colors cursor-pointer"
                    >
                      Cancelar
                    </button>
                    <button
                      onClick={handleRegenerate}
                      disabled={regenerating}
                      className="px-3 py-1.5 rounded-lg bg-[#EF4444] text-white text-xs font-semibold hover:bg-[#DC2626] transition-colors cursor-pointer disabled:opacity-50 flex items-center gap-1.5"
                    >
                      {regenerating ? (
                        <>
                          <span className="w-3 h-3 border border-white/30 border-t-white rounded-full animate-spin" />
                          Regenerando…
                        </>
                      ) : (
                        "Confirmar"
                      )}
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </motion.div>
    </div>
  );
}
