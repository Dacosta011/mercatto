"use client";

import { useEffect, useState, useCallback } from "react";
import { motion } from "motion/react";
import { getLastTournamentCode, getMemberToken } from "@/lib/tokenStorage";

interface TableRow {
  memberId: string; displayName: string; teamName: string;
  played: number; wins: number; draws: number; losses: number;
  gf: number; ga: number; gd: number; points: number;
}

interface DisciplineRow {
  playerId: string; playerName: string;
  memberId: string; displayName: string; teamName: string;
  yellows: number; reds: number; suspended: boolean; yellowsToSuspension: number;
}

interface LeagueTableState {
  status: string;
  session: { currentMatchday: number; totalMatchdays: number } | null;
  tournamentName: string;
  myMemberId: string;
  table: TableRow[];
  discipline: DisciplineRow[];
}

const MEDAL = ["🥇", "🥈", "🥉"];

function GdCell({ gd }: { gd: number }) {
  const color = gd > 0 ? "#22C55E" : gd < 0 ? "#EF4444" : "#9CA3AF";
  return <span style={{ color }} className="font-semibold tabular-nums">{gd > 0 ? `+${gd}` : gd}</span>;
}

export default function TablePage() {
  const [code, setCode] = useState<string | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [data, setData] = useState<LeagueTableState | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<"table" | "discipline">("table");

  useEffect(() => {
    const c = getLastTournamentCode();
    const t = c ? getMemberToken(c) : null;
    setCode(c); setToken(t);
  }, []);

  const fetchData = useCallback(async () => {
    if (!code || !token) return;
    setLoading(true);
    try {
      const res = await fetch(`/api/tournaments/${code}/league`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (res.ok) setData(await res.json());
    } finally { setLoading(false); }
  }, [code, token]);

  useEffect(() => { fetchData(); }, [fetchData]);

  if (!code || !token) return (
    <div className="min-h-screen flex items-center justify-center">
      <p className="text-[#9CA3AF] text-sm">Sin sesión activa.</p>
    </div>
  );

  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="flex flex-col items-center gap-4">
        <div className="w-8 h-8 border-2 border-[#8B5CF6]/30 border-t-[#8B5CF6] rounded-full animate-spin" />
        <p className="text-[#9CA3AF] text-sm">Cargando clasificación…</p>
      </div>
    </div>
  );

  if (!data?.session) return (
    <div className="min-h-screen flex items-center justify-center p-8">
      <div className="bg-[#131722] rounded-2xl border border-white/5 p-10 max-w-sm text-center flex flex-col items-center gap-4">
        <div className="w-14 h-14 rounded-2xl bg-[#8B5CF6]/10 border border-[#8B5CF6]/20 flex items-center justify-center">
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
          </svg>
        </div>
        <div>
          <p className="text-[#F3F4F6] font-semibold mb-1">Liga no iniciada</p>
          <p className="text-[#9CA3AF] text-sm">La clasificación estará disponible cuando empiece el torneo.</p>
        </div>
      </div>
    </div>
  );

  const { session, myMemberId, table, discipline, status } = data;
  const isFinished = status === "finished";
  const champion = isFinished ? table[0] : null;

  return (
    <motion.div initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.3 }}
      className="px-4 py-5 lg:p-8 max-w-5xl mx-auto">

      {/* Header */}
      <div className="mb-5 lg:mb-8">
        <p className="text-[#9CA3AF] text-[10px] lg:text-xs uppercase tracking-widest font-medium mb-0.5">Clasificación</p>
        <h1 className="text-[#F3F4F6] text-lg lg:text-2xl font-bold tracking-tight">{data.tournamentName}</h1>
        <p className="text-[#9CA3AF] text-xs lg:text-sm mt-1">
          Fecha {session.currentMatchday}/{session.totalMatchdays}
          {isFinished && <span className="ml-2 text-[10px] font-bold px-2 py-0.5 rounded-full bg-[#8B5CF6]/15 text-[#8B5CF6] uppercase">Finalizada</span>}
        </p>
      </div>

      {/* Champion reveal */}
      {isFinished && champion && (
        <motion.div initial={{ opacity: 0, scale: 0.95 }} animate={{ opacity: 1, scale: 1 }} transition={{ delay: 0.2 }}
          className="mb-5 lg:mb-8 rounded-2xl overflow-hidden relative"
          style={{ background: "linear-gradient(135deg, #4C1D95, #2D1B69)", border: "1px solid #8B5CF640", boxShadow: "0 0 40px #8B5CF630" }}>
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_30%_50%,#8B5CF620,transparent_60%)]" />
          <div className="relative p-5 lg:p-8 flex items-center gap-4 lg:gap-6">
            <div className="w-12 h-12 lg:w-16 lg:h-16 rounded-2xl flex items-center justify-center text-3xl lg:text-4xl shrink-0"
              style={{ background: "#8B5CF620", border: "1px solid #8B5CF640" }}>
              🏆
            </div>
            <div className="min-w-0">
              <p className="text-[#A78BFA] text-[10px] lg:text-xs uppercase tracking-widest font-bold mb-0.5">Campeón</p>
              <p className="text-white text-lg lg:text-2xl font-black truncate">{champion.displayName}</p>
              <p className="text-[#C4B5FD] text-xs lg:text-sm mt-0.5 truncate">{champion.teamName} · {champion.points} pts</p>
            </div>
          </div>
        </motion.div>
      )}

      {/* Tab switcher */}
      <div className="flex items-center gap-1 mb-6 bg-[#131722] rounded-xl p-1 w-fit">
        {(["table", "discipline"] as const).map((t) => (
          <button key={t} onClick={() => setTab(t)}
            className={`px-4 py-2 rounded-lg text-xs font-semibold transition-all duration-150 cursor-pointer
              ${tab === t ? "bg-[#8B5CF6]/15 text-[#8B5CF6]" : "text-[#9CA3AF] hover:text-[#F3F4F6]"}`}>
            {t === "table" ? "Tabla" : "Disciplina"}
          </button>
        ))}
      </div>

      {/* Table */}
      {tab === "table" && (
        <div className="bg-[#131722] rounded-2xl border border-white/4 overflow-hidden">
          {/* Mobile: compact ranking cards */}
          <div className="lg:hidden divide-y divide-white/3">
            {table.map((row, idx) => {
              const isMe = row.memberId === myMemberId;
              const isTop3 = idx < 3;
              const topColors = ["#F59E0B", "#9CA3AF", "#CD7C3F"];

              return (
                <motion.div key={row.memberId}
                  initial={{ opacity: 0, y: 4 }} animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: idx * 0.03 }}
                  className={`px-4 py-3 ${isMe ? "bg-[#8B5CF6]/5" : ""}`}
                  style={isTop3 ? { borderLeft: `3px solid ${topColors[idx]}` } : {}}>
                  <div className="flex items-center gap-3">
                    <div className="w-7 flex items-center justify-center shrink-0">
                      {isTop3
                        ? <span className="text-sm">{MEDAL[idx]}</span>
                        : <span className="text-[#9CA3AF] text-xs font-bold tabular-nums">{idx + 1}</span>
                      }
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className={`text-sm font-semibold truncate ${isMe ? "text-[#8B5CF6]" : "text-[#F3F4F6]"}`}>
                        {row.displayName}
                        {isMe && <span className="ml-1 text-[9px] text-[#8B5CF6]/60">(tú)</span>}
                      </p>
                      <p className="text-[#9CA3AF] text-[10px] truncate">{row.teamName}</p>
                    </div>
                    <div className="flex items-center gap-3 shrink-0">
                      <div className="flex items-center gap-1 text-[10px] font-medium">
                        <span className="text-[#22C55E]">{row.wins}V</span>
                        <span className="text-[#F59E0B]">{row.draws}E</span>
                        <span className="text-[#EF4444]">{row.losses}D</span>
                      </div>
                      <div className="text-[10px] tabular-nums"><GdCell gd={row.gd} /></div>
                      <span className={`text-base font-black tabular-nums min-w-[24px] text-right ${isTop3 ? "" : "text-[#F3F4F6]"}`}
                        style={isTop3 ? { color: topColors[idx] } : {}}>
                        {row.points}
                      </span>
                    </div>
                  </div>
                </motion.div>
              );
            })}
          </div>

          {/* Desktop: full table */}
          <div className="hidden lg:block">
            <div className="grid grid-cols-[2rem_2fr_1fr_1fr_1fr_1fr_1fr_1fr_1fr_1.5rem] gap-2 px-5 py-3 border-b border-white/4 text-[#9CA3AF] text-[10px] font-bold uppercase tracking-wider">
              <span>#</span><span>Equipo</span>
              <span className="text-center">PJ</span><span className="text-center">G</span>
              <span className="text-center">E</span><span className="text-center">P</span>
              <span className="text-center">GF</span><span className="text-center">GC</span>
              <span className="text-center">DG</span><span className="text-center">Pts</span>
            </div>

            <div className="divide-y divide-white/3">
              {table.map((row, idx) => {
                const isMe = row.memberId === myMemberId;
                const isTop3 = idx < 3;
                const topColors = ["#F59E0B", "#9CA3AF", "#CD7C3F"];

                return (
                  <motion.div key={row.memberId}
                    initial={{ opacity: 0, x: -8 }} animate={{ opacity: 1, x: 0 }}
                    transition={{ delay: idx * 0.04 }}
                    className={`grid grid-cols-[2rem_2fr_1fr_1fr_1fr_1fr_1fr_1fr_1fr_1.5rem] gap-2 px-5 py-3.5 items-center transition-colors duration-150
                      ${isMe ? "bg-[#8B5CF6]/5" : "hover:bg-[#1A1F2E]/40"}`}
                    style={isTop3 ? { borderLeft: `2px solid ${topColors[idx]}` } : {}}>
                    <div className="flex items-center justify-center">
                      {isTop3 ? <span className="text-sm">{MEDAL[idx]}</span> : <span className="text-[#9CA3AF] text-xs font-semibold tabular-nums">{idx + 1}</span>}
                    </div>
                    <div className="min-w-0">
                      <p className={`text-sm font-semibold truncate ${isMe ? "text-[#8B5CF6]" : "text-[#F3F4F6]"}`}>
                        {row.displayName}{isMe && <span className="ml-1 text-[9px] font-bold text-[#8B5CF6]/60">(tú)</span>}
                      </p>
                      <p className="text-[#9CA3AF] text-[10px] truncate">{row.teamName}</p>
                    </div>
                    <span className="text-center text-[#9CA3AF] text-xs tabular-nums">{row.played}</span>
                    <span className="text-center text-[#22C55E] text-xs font-semibold tabular-nums">{row.wins}</span>
                    <span className="text-center text-[#F59E0B] text-xs font-semibold tabular-nums">{row.draws}</span>
                    <span className="text-center text-[#EF4444] text-xs font-semibold tabular-nums">{row.losses}</span>
                    <span className="text-center text-[#F3F4F6] text-xs tabular-nums">{row.gf}</span>
                    <span className="text-center text-[#9CA3AF] text-xs tabular-nums">{row.ga}</span>
                    <div className="text-center text-xs tabular-nums"><GdCell gd={row.gd} /></div>
                    <div className="flex items-center justify-center">
                      <span className={`text-sm font-black tabular-nums ${isTop3 ? "" : "text-[#F3F4F6]"}`}
                        style={isTop3 ? { color: topColors[idx] } : {}}>{row.points}</span>
                    </div>
                  </motion.div>
                );
              })}
            </div>
          </div>

          {/* Legend */}
          <div className="px-4 lg:px-5 py-2.5 lg:py-3 border-t border-white/4 flex items-center gap-3 lg:gap-5 text-[9px] lg:text-[10px] text-[#9CA3AF]">
            <span><span className="font-bold text-[#22C55E]">G</span> = 3 pts</span>
            <span><span className="font-bold text-[#F59E0B]">E</span> = 1 pt</span>
            <span><span className="font-bold text-[#EF4444]">P</span> = 0 pts</span>
          </div>
        </div>
      )}

      {/* Discipline */}
      {tab === "discipline" && (() => {
        const visible = discipline.filter(d => d.yellows > 0 || d.reds > 0 || d.suspended);
        const grouped: Record<string, DisciplineRow[]> = {};
        for (const d of visible) {
          (grouped[d.memberId] ??= []).push(d);
        }

        return (
          <div className="flex flex-col gap-4">
            {visible.length === 0 && (
              <p className="text-[#9CA3AF] text-sm text-center py-12">Sin tarjetas registradas aún.</p>
            )}
            {Object.entries(grouped).map(([memberId, players], gIdx) => {
              const first = players[0];
              const isMe = memberId === myMemberId;
              return (
                <motion.div key={memberId}
                  initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: gIdx * 0.05 }}
                  className="bg-[#131722] rounded-2xl border border-white/5 overflow-hidden">

                  {/* Member header */}
                  <div className="px-4 py-3 border-b border-white/4 flex items-center gap-3">
                    <div className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 font-black text-xs ${isMe ? "bg-[#8B5CF6]/10 text-[#8B5CF6]" : "bg-[#1A1F2E] text-[#9CA3AF]"}`}>
                      {first.displayName.charAt(0).toUpperCase()}
                    </div>
                    <div className="min-w-0">
                      <p className={`text-sm font-semibold ${isMe ? "text-[#8B5CF6]" : "text-[#F3F4F6]"}`}>{first.displayName}</p>
                      <p className="text-[#9CA3AF] text-[10px]">{first.teamName}</p>
                    </div>
                  </div>

                  {/* Player rows */}
                  <div className="divide-y divide-white/3">
                    {players.map((d) => (
                      <div key={d.playerId} className={`px-4 py-3 flex items-center gap-3 ${d.suspended ? "bg-[#EF4444]/4" : ""}`}>
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <p className="text-[#F3F4F6] text-sm font-medium truncate">{d.playerName}</p>
                            {d.suspended && (
                              <span className="text-[9px] font-black px-2 py-0.5 rounded-full bg-[#EF4444]/15 text-[#EF4444] uppercase tracking-wide shrink-0">
                                Sancionado
                              </span>
                            )}
                          </div>
                        </div>
                        <div className="flex items-center gap-4 shrink-0">
                          {d.yellows > 0 && (
                            <div className="flex items-center gap-1.5">
                              <div className="flex items-center gap-0.5">
                                {Array.from({ length: Math.min(d.yellows, 6) }).map((_, i) => (
                                  <div key={i} className="w-2.5 h-3.5 bg-[#F59E0B] rounded-sm" />
                                ))}
                                {d.yellows > 6 && <span className="text-[#F59E0B] text-[10px] font-bold">+{d.yellows - 6}</span>}
                              </div>
                              <span className="text-[#9CA3AF] text-[9px]">{d.yellows}</span>
                            </div>
                          )}
                          {d.reds > 0 && (
                            <div className="flex items-center gap-1.5">
                              <div className="flex items-center gap-0.5">
                                {Array.from({ length: Math.min(d.reds, 4) }).map((_, i) => (
                                  <div key={i} className="w-2.5 h-3.5 bg-[#EF4444] rounded-sm" />
                                ))}
                              </div>
                              <span className="text-[#9CA3AF] text-[9px]">{d.reds}</span>
                            </div>
                          )}
                          {!d.suspended && d.yellows > 0 && (
                            <div className="text-center">
                              <p className="text-[#F59E0B] text-xs font-black">{d.yellowsToSuspension}</p>
                              <p className="text-[#9CA3AF] text-[8px]">p/sanción</p>
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </motion.div>
              );
            })}

            <div className="mt-2 px-4 py-3 rounded-xl bg-[#131722]/50 border border-white/4 text-[#9CA3AF] text-[11px] flex flex-col gap-1">
              <p>🟥 Tarjeta roja → 2 fechas de suspensión</p>
              <p>🟨 3 tarjetas amarillas → 1 fecha de suspensión</p>
            </div>
          </div>
        );
      })()}
    </motion.div>
  );
}
