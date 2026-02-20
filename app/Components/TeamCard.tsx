import { motion } from "motion/react";

interface TeamCardProps {
  teamName: string;
  squadValue: string;
  budget: string;
  league?: string;
}

export default function TeamCard({
  teamName,
  squadValue,
  budget,
  league = "Primera División",
}: TeamCardProps) {
  return (
    <motion.div
      initial={{ opacity: 0, scale: 0.9, y: 20 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      transition={{ duration: 0.5, ease: "easeOut" }}
      className="bg-[#131722] rounded-2xl border border-[#8B5CF6]/30 shadow-2xl shadow-[#8B5CF6]/10 overflow-hidden w-full max-w-sm"
    >
      {/* Top accent bar */}
      <div className="h-1 w-full bg-gradient-to-r from-[#8B5CF6] via-[#7C3AED] to-[#6D28D9]" />

      <div className="p-6">
        {/* Badge */}
        <div className="flex items-center gap-2 mb-4">
          <span className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium bg-[#22C55E]/10 text-[#22C55E]">
            <span className="w-1.5 h-1.5 rounded-full bg-[#22C55E]" />
            Asignado
          </span>
          <span className="text-[#9CA3AF] text-xs">{league}</span>
        </div>

        {/* Team name */}
        <div className="mb-6">
          <p className="text-[#9CA3AF] text-xs uppercase tracking-widest mb-1">
            Tu Equipo
          </p>
          <h2 className="text-[#F3F4F6] text-2xl font-bold tracking-tight">
            {teamName}
          </h2>
        </div>

        {/* Stats grid */}
        <div className="grid grid-cols-2 gap-3">
          <div className="bg-[#0D0F14] rounded-xl p-3.5">
            <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mb-1">
              Valor Plantilla
            </p>
            <p className="text-[#F3F4F6] text-lg font-semibold">{squadValue}</p>
          </div>
          <div className="bg-[#0D0F14] rounded-xl p-3.5">
            <p className="text-[#9CA3AF] text-[10px] uppercase tracking-wider mb-1">
              Presupuesto
            </p>
            <p className="text-[#22C55E] text-lg font-semibold">{budget}</p>
          </div>
        </div>
      </div>
    </motion.div>
  );
}
