"use client";

import { useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import RouletteWheel, { Team } from "../../Components/RouletteWheel";
import TeamCard from "../../Components/TeamCard";
import Button from "../../Components/Button";

export default function RoulettePage() {
  const [result, setResult] = useState<Team | null>(null);

  const handleResult = (team: Team) => {
    setResult(team);
  };

  const reset = () => {
    setResult(null);
  };

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-8 relative">
      {/* Background glow */}
      <div
        className="absolute pointer-events-none"
        style={{
          width: 600,
          height: 600,
          background:
            "radial-gradient(circle, rgba(139,92,246,0.08) 0%, transparent 65%)",
          top: "50%",
          left: "50%",
          transform: "translate(-50%, -50%)",
        }}
      />

      {/* Page header */}
      <div className="text-center mb-10 z-10">
        <p className="text-[#9CA3AF] text-xs uppercase tracking-widest mb-2 font-medium">
          Draft · Asignación de equipos
        </p>
        <h1 className="text-[#F3F4F6] text-3xl font-bold tracking-tight">
          Ruleta de Equipos
        </h1>
        <p className="text-[#9CA3AF] text-sm mt-2">
          El destino elige. Tú decides cómo jugarlo.
        </p>
      </div>

      {/* Main area */}
      <div className="z-10 flex flex-col lg:flex-row items-center gap-16">
        {/* Wheel */}
        <RouletteWheel onResult={handleResult} />

        {/* Result panel */}
        <div className="w-full max-w-sm min-h-[200px] flex items-center justify-center">
          <AnimatePresence mode="wait">
            {result ? (
              <motion.div
                key={result.name}
                initial={{ opacity: 0, x: 20 }}
                animate={{ opacity: 1, x: 0 }}
                exit={{ opacity: 0, x: -20 }}
                transition={{ duration: 0.4 }}
                className="w-full flex flex-col gap-4"
              >
                <TeamCard
                  teamName={result.name}
                  squadValue={result.squadValue}
                  budget={result.budget}
                />
                <Button
                  variant="ghost"
                  size="sm"
                  className="w-full"
                  onClick={reset}
                >
                  Limpiar resultado
                </Button>
              </motion.div>
            ) : (
              <motion.div
                key="placeholder"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                className="flex flex-col items-center gap-3 text-center"
              >
                <div className="w-16 h-16 rounded-2xl bg-[#131722] border border-white/[0.04] flex items-center justify-center">
                  <svg
                    width="24"
                    height="24"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="#9CA3AF"
                    strokeWidth="1.5"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  >
                    <circle cx="12" cy="12" r="10" />
                    <polyline points="12 6 12 12 16 14" />
                  </svg>
                </div>
                <div>
                  <p className="text-[#F3F4F6] text-sm font-medium">
                    Tu equipo aparecerá aquí
                  </p>
                  <p className="text-[#9CA3AF] text-xs mt-1">
                    Presiona &ldquo;Girar&rdquo; para comenzar
                  </p>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>

      {/* Teams legend */}
      <div className="z-10 mt-12 bg-[#131722] rounded-2xl border border-white/[0.04] p-5 w-full max-w-2xl">
        <p className="text-[#9CA3AF] text-xs uppercase tracking-wider font-medium mb-4">
          Equipos disponibles
        </p>
        <div className="grid grid-cols-4 gap-2">
          {[
            "Real Madrid", "Barcelona", "Man. City", "Liverpool",
            "PSG", "Bayern", "Juventus", "Arsenal",
          ].map((team) => (
            <div
              key={team}
              className="bg-[#0D0F14] rounded-xl px-3 py-2 text-center"
            >
              <span className="text-[#F3F4F6] text-xs font-medium">
                {team}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
