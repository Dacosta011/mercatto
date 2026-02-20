"use client";

import { useEffect, useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import { getLastTournamentCode, getMemberToken } from "@/lib/tokenStorage";
import StatCard from "../../Components/StatCard";
import Badge from "../../Components/Badge";

interface Player {
  id: string;
  name: string;
  ovr: number;
  position: string;
  countryName: string;
  price: number;
  clause: number;
}

interface SquadData {
  team: { id: string; name: string; squadValue: number; budget: number };
  players: Player[];
  avgOvr: number;
}

type PosFilter = "Todos" | "POR" | "DEF" | "MED" | "DEL";

const POS_GROUPS: Record<PosFilter, string[]> = {
  Todos: [],
  POR:   ["POR", "GK"],
  DEF:   ["DFC", "CB", "LI", "LD", "LB", "RB", "SW", "WB"],
  MED:   ["MCD", "MC", "MCO", "MI", "MD", "CM", "CDM", "CAM", "LM", "RM"],
  DEL:   ["DC", "SD", "EI", "ED", "CF", "ST", "LW", "RW", "SS"],
};

function ovrStyle(ovr: number) {
  if (ovr >= 90) return { bg: "bg-[#8B5CF6]/10", text: "text-[#8B5CF6]" };
  if (ovr >= 85) return { bg: "bg-[#22C55E]/10", text: "text-[#22C55E]" };
  if (ovr >= 80) return { bg: "bg-yellow-400/10", text: "text-yellow-400" };
  return { bg: "bg-[#9CA3AF]/10", text: "text-[#9CA3AF]" };
}

function fmtMoney(cents: number) {
  if (!cents) return "—";
  if (cents >= 1_000_000) return `€${(cents / 1_000_000).toFixed(0)}M`;
  if (cents >= 1_000) return `€${(cents / 1_000).toFixed(0)}K`;
  return `€${cents}`;
}

export default function SquadPage() {
  const [squad, setSquad] = useState<SquadData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<PosFilter>("Todos");

  useEffect(() => {
    const code = getLastTournamentCode();
    const token = code ? getMemberToken(code) : null;

    if (!code || !token) {
      setError("No estás en ningún torneo activo.");
      setLoading(false);
      return;
    }

    fetch(`/api/tournaments/${code}/squad`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then((r) => r.json())
      .then((data) => {
        if (data.error) { setError(data.error); return; }
        setSquad(data as SquadData);
      })
      .catch(() => setError("Error al cargar la plantilla."))
      .finally(() => setLoading(false));
  }, []);

  const filtered =
    filter === "Todos"
      ? squad?.players ?? []
      : (squad?.players ?? []).filter((p) =>
          POS_GROUPS[filter].includes((p.position ?? "").toUpperCase())
        );

  const totalClause = filtered.reduce((s, p) => s + (p.clause ?? 0), 0);

  // ── Loading ─────────────────────────────────────────────────────────────────
  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="flex flex-col items-center gap-4">
          <div className="w-8 h-8 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
          <p className="text-[#9CA3AF] text-sm">Cargando plantilla…</p>
        </div>
      </div>
    );
  }

  // ── Sin equipo ──────────────────────────────────────────────────────────────
  if (error) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="bg-[#131722] rounded-2xl border border-white/5 p-10 max-w-sm text-center flex flex-col items-center gap-4">
          <div className="w-12 h-12 rounded-2xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
            </svg>
          </div>
          <div>
            <p className="text-[#F3F4F6] font-medium mb-1">Sin equipo aún</p>
            <p className="text-[#9CA3AF] text-sm">{error}</p>
          </div>
        </div>
      </div>
    );
  }

  if (!squad) return null;

  const { team, avgOvr } = squad;

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.35 }}
      className="p-8 max-w-6xl mx-auto"
    >
      {/* Header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <p className="text-[#9CA3AF] text-xs uppercase tracking-widest font-medium mb-1">
            Mi Equipo
          </p>
          <h1 className="text-[#F3F4F6] text-2xl font-bold tracking-tight">
            {team.name}
          </h1>
        </div>
      </div>

      {/* Stat cards */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        <StatCard
          label="Equipo"
          value={team.name}
          accent
          icon={
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
            </svg>
          }
        />
        <StatCard
          label="Valor plantilla"
          value={fmtMoney(team.squadValue)}
          icon={
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" />
              <polyline points="16 7 22 7 22 13" />
            </svg>
          }
        />
        <StatCard
          label="Presupuesto"
          value={team.budget > 0 ? fmtMoney(team.budget) : "—"}
          icon={
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="12" y1="1" x2="12" y2="23" />
              <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
            </svg>
          }
        />
        <StatCard
          label="OVR Medio"
          value={avgOvr > 0 ? String(avgOvr) : "—"}
          trend={avgOvr >= 85 ? "up" : "neutral"}
          icon={
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M18 20V10" /><path d="M12 20V4" /><path d="M6 20v-6" />
            </svg>
          }
        />
      </div>

      {/* Squad table */}
      <div className="bg-[#131722] rounded-2xl border border-white/4 overflow-hidden">
        {/* Toolbar */}
        <div className="px-6 py-4 border-b border-white/4 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <h2 className="text-[#F3F4F6] text-sm font-semibold">Plantilla</h2>
            <span className="text-[#9CA3AF] text-xs bg-[#0D0F14] px-2 py-0.5 rounded-full">
              {filtered.length} jugadores
            </span>
          </div>
          <div className="flex items-center gap-1.5">
            {(["Todos", "POR", "DEF", "MED", "DEL"] as PosFilter[]).map((f) => (
              <button
                key={f}
                onClick={() => setFilter(f)}
                className={`px-3 py-1 rounded-lg text-xs font-medium transition-colors duration-150 cursor-pointer
                  ${filter === f
                    ? "bg-[#8B5CF6]/10 text-[#8B5CF6]"
                    : "text-[#9CA3AF] hover:text-[#F3F4F6] hover:bg-[#1A1F2E]"
                  }`}
              >
                {f}
              </button>
            ))}
          </div>
        </div>

        {/* Column headers */}
        <div className="grid grid-cols-[2.5fr_1fr_1fr_1fr_1fr] px-6 py-3 border-b border-white/4">
          {["Jugador", "OVR", "Precio", "Cláusula", "País"].map((col, i) => (
            <span key={i} className="text-[#9CA3AF] text-[11px] font-semibold uppercase tracking-wider">
              {col}
            </span>
          ))}
        </div>

        {/* Rows */}
        <AnimatePresence mode="popLayout">
          {filtered.length === 0 ? (
            <div className="px-6 py-12 text-center text-[#9CA3AF] text-sm">
              No hay jugadores en esta posición.
            </div>
          ) : (
            <div className="divide-y divide-white/3">
              {filtered.map((player, idx) => {
                const style = ovrStyle(player.ovr);
                return (
                  <motion.div
                    key={player.id}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.15, delay: idx * 0.02 }}
                    className="grid grid-cols-[2.5fr_1fr_1fr_1fr_1fr] px-6 py-3.5 hover:bg-[#1A1F2E]/50 transition-colors duration-150 items-center"
                  >
                    {/* Jugador */}
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 rounded-xl bg-[#0D0F14] border border-white/5 flex items-center justify-center shrink-0">
                        <span className="text-[#9CA3AF] text-[10px] font-mono font-bold">
                          {player.position?.slice(0, 2) ?? "—"}
                        </span>
                      </div>
                      <div>
                        <p className="text-[#F3F4F6] text-sm font-medium leading-tight">
                          {player.name}
                        </p>
                        <p className="text-[#9CA3AF] text-xs mt-0.5">{player.position}</p>
                      </div>
                    </div>

                    {/* OVR */}
                    <div>
                      <span className={`inline-flex items-center px-2 py-0.5 rounded-lg text-xs font-bold ${style.bg} ${style.text}`}>
                        {player.ovr}
                      </span>
                    </div>

                    {/* Precio */}
                    <span className="text-[#F3F4F6] text-sm">{fmtMoney(player.price)}</span>

                    {/* Cláusula */}
                    <span className="text-[#EF4444] text-sm">{fmtMoney(player.clause)}</span>

                    {/* País */}
                    <span className="text-[#9CA3AF] text-xs truncate">{player.countryName}</span>
                  </motion.div>
                );
              })}
            </div>
          )}
        </AnimatePresence>

        {/* Footer */}
        {filtered.length > 0 && (
          <div className="px-6 py-4 border-t border-white/4 flex items-center justify-between">
            <span className="text-[#9CA3AF] text-xs">
              Valor total de cláusulas:{" "}
              <span className="text-[#EF4444] font-medium">{fmtMoney(totalClause)}</span>
            </span>
            <Badge status="active" label="Plantilla activa" />
          </div>
        )}
      </div>
    </motion.div>
  );
}
