"use client";

import { useState } from "react";
import { useDraggable, useDroppable } from "@dnd-kit/core";
import type { LineupPlayer } from "./FormationPitch";

type PosFilter = "Todos" | "POR" | "DEF" | "MED" | "DEL";

const POS_GROUPS: Record<PosFilter, string[]> = {
  Todos: [],
  POR: ["POR", "GK"],
  DEF: ["DFC", "CB", "LI", "LD", "LB", "RB", "SW", "WB", "LWB", "RWB"],
  MED: ["MCD", "MC", "MCO", "MI", "MD", "CM", "CDM", "CAM", "LM", "RM"],
  DEL: ["DC", "SD", "EI", "ED", "CF", "ST", "LW", "RW", "SS"],
};

function ovrColor(ovr: number): string {
  if (ovr >= 90) return "#8B5CF6";
  if (ovr >= 85) return "#22C55E";
  if (ovr >= 80) return "#F59E0B";
  return "#6B7280";
}

function ovrRingClass(ovr: number): string {
  if (ovr >= 90) return "ring-[#8B5CF6]/50";
  if (ovr >= 85) return "ring-[#22C55E]/50";
  if (ovr >= 80) return "ring-[#F59E0B]/50";
  return "ring-white/10";
}

/* ── Draggable player card (horizontal) ────────────────────── */
function DraggableCard({ player, locked }: { player: LineupPlayer; locked: boolean }) {
  const { setNodeRef, listeners, attributes, transform, isDragging } = useDraggable({
    id: `player-${player.id}`,
    data: { type: "player", player, fromSlot: null },
    disabled: locked,
  });

  const color = ovrColor(player.ovr);
  const ringClass = ovrRingClass(player.ovr);
  const isSuspended = (player.suspended ?? 0) > 0;

  const style: React.CSSProperties = transform
    ? { transform: `translate(${transform.x}px, ${transform.y}px)`, zIndex: 50 }
    : {};

  return (
    <div
      ref={setNodeRef}
      {...(locked ? {} : listeners)}
      {...attributes}
      className={`relative flex items-center gap-5 px-5 py-4 rounded-2xl border bg-[#0D0F14] transition-all duration-150 group ${
        locked ? "cursor-default" : "cursor-grab active:cursor-grabbing"
      } ${isDragging ? "opacity-30 scale-[0.97]" : "hover:bg-[#151A27] hover:border-[#8B5CF6]/15"} ${
        isSuspended ? "opacity-40 grayscale" : ""
      }`}
      style={{ ...style, borderColor: isDragging ? "transparent" : `rgba(255,255,255,0.04)` }}
    >
      {/* Headshot with OVR ring */}
      <div className="relative shrink-0">
        {player.headshotUrl ? (
          <img
            src={player.headshotUrl}
            alt=""
            className={`w-16 h-16 rounded-full object-cover object-top ring-[3px] ${ringClass}`}
            draggable={false}
          />
        ) : (
          <div className={`w-16 h-16 rounded-full bg-[#131722] ring-[3px] ${ringClass} flex items-center justify-center`}>
            <span className="text-xl font-bold text-[#9CA3AF]/50">
              {player.name.charAt(0)}
            </span>
          </div>
        )}
        {/* OVR badge overlapping bottom-right */}
        <div
          className="absolute -bottom-1 -right-1 min-w-[30px] h-[22px] rounded-full flex items-center justify-center text-xs font-black text-white px-1.5"
          style={{ background: color, boxShadow: `0 0 10px ${color}60` }}
        >
          {player.ovr}
        </div>
      </div>

      {/* Name + details */}
      <div className="flex-1 min-w-0">
        <p className="text-base font-semibold text-[#F3F4F6] truncate leading-tight">
          {player.name}
        </p>
        <div className="flex items-center gap-2 mt-1.5">
          <span
            className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded"
            style={{ color, background: `${color}15` }}
          >
            {player.position}
          </span>
          {player.countryName && (
            <span className="text-sm text-[#9CA3AF]/60 truncate">
              {player.countryName}
            </span>
          )}
        </div>
      </div>

      {/* Status badges */}
      {isSuspended && (
        <div className="shrink-0 w-7 h-7 rounded-full bg-[#EF4444]/15 flex items-center justify-center">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#EF4444" strokeWidth="3" strokeLinecap="round">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </div>
      )}
      {!isSuspended && (player.yellowCards ?? 0) >= 4 && (
        <div className="shrink-0 w-5 h-6 rounded-sm bg-[#F59E0B] shadow-sm shadow-[#F59E0B]/20" />
      )}
    </div>
  );
}

/* ── Bench Panel ───────────────────────────────────────────── */
export default function BenchPanel({
  allPlayers,
  lineupPlayerIds,
  onAutoFill,
  locked,
}: {
  allPlayers: LineupPlayer[];
  lineupPlayerIds: Set<string>;
  onAutoFill: () => void;
  locked: boolean;
}) {
  const { setNodeRef, isOver } = useDroppable({
    id: "bench",
    data: { type: "bench" },
  });

  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<PosFilter>("Todos");

  const benchPlayers = allPlayers.filter((p) => !lineupPlayerIds.has(p.id));

  const filtered = benchPlayers.filter((p) => {
    const matchesSearch =
      search.length === 0 ||
      p.name.toLowerCase().includes(search.toLowerCase());
    const matchesFilter =
      filter === "Todos" ||
      POS_GROUPS[filter].includes(p.position.toUpperCase());
    return matchesSearch && matchesFilter;
  });

  const lineupCount = lineupPlayerIds.size;

  return (
    <div
      ref={setNodeRef}
      className={`w-[440px] border-l flex flex-col bg-[#131722] shrink-0 transition-colors duration-200 ${
        isOver ? "border-[#8B5CF6]/30 bg-[#8B5CF6]/2" : "border-white/4"
      }`}
    >
      {/* Panel header */}
      <div className="px-5 pt-5 pb-4 border-b border-white/4">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2.5">
            <h2 className="text-lg font-semibold text-[#F3F4F6]">Plantilla</h2>
            <span className="text-sm font-medium text-[#9CA3AF] bg-[#0D0F14] px-3 py-0.5 rounded-full">
              {benchPlayers.length}
            </span>
          </div>
          <div className="flex items-center gap-3">
            <span className={`text-base font-bold tabular-nums ${lineupCount === 11 ? "text-[#22C55E]" : "text-[#9CA3AF]"}`}>
              {lineupCount}/11
            </span>
            {!locked && (
              <button
                onClick={onAutoFill}
                className="text-sm font-semibold text-[#8B5CF6] hover:text-[#A78BFA] bg-[#8B5CF6]/10 hover:bg-[#8B5CF6]/15 px-4 py-2 rounded-lg transition-colors duration-150 cursor-pointer"
              >
                Auto XI
              </button>
            )}
          </div>
        </div>

        {/* Search */}
        <div className="relative mb-3">
          <svg
            width="16" height="16" viewBox="0 0 24 24" fill="none"
            stroke="#9CA3AF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
            className="absolute left-3.5 top-1/2 -translate-y-1/2 opacity-40"
          >
            <circle cx="11" cy="11" r="8" />
            <line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <input
            type="text"
            placeholder="Buscar jugador…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-[#0D0F14] border border-white/4 rounded-xl pl-10 pr-4 py-3 text-base text-[#F3F4F6] placeholder-[#9CA3AF]/40 outline-none focus:border-[#8B5CF6]/30 transition-colors duration-150"
          />
        </div>

        {/* Filter chips */}
        <div className="flex items-center gap-1.5">
          {(["Todos", "POR", "DEF", "MED", "DEL"] as PosFilter[]).map((f) => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className={`px-4 py-2 rounded-lg text-sm font-semibold transition-colors duration-150 cursor-pointer ${
                filter === f
                  ? "bg-[#8B5CF6]/10 text-[#8B5CF6]"
                  : "text-[#9CA3AF]/60 hover:text-[#9CA3AF] hover:bg-[#1A1F2E]"
              }`}
            >
              {f}
            </button>
          ))}
        </div>
      </div>

      {/* Player list */}
      <div className="flex-1 overflow-y-auto p-4 flex flex-col gap-2.5">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <p className="text-[#9CA3AF]/40 text-sm">
              {benchPlayers.length === 0
                ? "Todos los jugadores están alineados"
                : "Sin resultados"}
            </p>
          </div>
        ) : (
          filtered.map((player) => (
            <DraggableCard key={player.id} player={player} locked={locked} />
          ))
        )}
      </div>

      {/* Drop hint */}
      {isOver && (
        <div className="px-5 py-3 border-t border-[#8B5CF6]/20 text-center">
          <span className="text-xs text-[#8B5CF6] font-medium">
            Soltar para enviar a la banca
          </span>
        </div>
      )}
    </div>
  );
}
