"use client";

import { useDroppable, useDraggable } from "@dnd-kit/core";
import type { Formation, FormationSlot } from "../_lib/formations";

export interface LineupPlayer {
  id: string;
  name: string;
  ovr: number;
  position: string;
  countryName: string;
  headshotUrl?: string | null;
  price?: number;
  clause?: number;
  suspended?: number;
  yellowCards?: number;
  newSigning?: boolean;
}

function ovrColor(ovr: number): string {
  if (ovr >= 90) return "#8B5CF6";
  if (ovr >= 85) return "#22C55E";
  if (ovr >= 80) return "#F59E0B";
  return "#9CA3AF";
}

function lastName(name: string) {
  const parts = name.trim().split(" ");
  return parts.length > 1 ? parts[parts.length - 1] : name;
}

/* ── Empty slot (droppable only) ───────────────────────────── */
function EmptySlot({
  slot,
  isDragActive,
  isCompatible,
}: {
  slot: FormationSlot;
  isDragActive: boolean;
  isCompatible: boolean;
}) {
  const { setNodeRef, isOver } = useDroppable({
    id: `slot-${slot.id}`,
    data: { type: "slot", slotId: slot.id },
  });

  let borderClass = "border-white/[0.06]";
  let bgClass = "bg-[#131722]/40";
  let glowStyle = {};

  if (isDragActive) {
    if (isOver && isCompatible) {
      borderClass = "border-[#8B5CF6]/60";
      bgClass = "bg-[#8B5CF6]/10";
      glowStyle = { boxShadow: "0 0 24px rgba(139,92,246,0.3)" };
    } else if (isOver && !isCompatible) {
      borderClass = "border-[#EF4444]/40";
      bgClass = "bg-[#EF4444]/5";
    } else if (isCompatible) {
      borderClass = "border-[#8B5CF6]/25";
      bgClass = "bg-[#8B5CF6]/5";
    }
  }

  return (
    <div
      ref={setNodeRef}
      className="absolute -translate-x-1/2 -translate-y-1/2 z-10"
      style={{ left: `${slot.x}%`, top: `${slot.y}%` }}
    >
      <div
        className={`w-13 h-13 sm:w-20 sm:h-11 lg:w-32.5 lg:h-17 rounded-full sm:rounded-xl lg:rounded-2xl border-2 border-dashed flex flex-col items-center justify-center gap-0.5 lg:gap-1 transition-all duration-200 ${borderClass} ${bgClass}`}
        style={glowStyle}
      >
        <span className="text-[9px] sm:text-[9px] lg:text-[11px] font-semibold uppercase tracking-wider text-[#9CA3AF]/50">
          {slot.label}
        </span>
        {isDragActive && isCompatible && (
          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className="opacity-60 hidden sm:block">
            <line x1="12" y1="5" x2="12" y2="19" />
            <line x1="5" y1="12" x2="19" y2="12" />
          </svg>
        )}
      </div>
    </div>
  );
}

/* ── Filled slot (droppable + draggable player inside) ───── */
function FilledSlot({
  slot,
  player,
  isDragActive,
  locked,
}: {
  slot: FormationSlot;
  player: LineupPlayer;
  isDragActive: boolean;
  locked: boolean;
}) {
  const { setNodeRef: setDropRef, isOver } = useDroppable({
    id: `slot-${slot.id}`,
    data: { type: "slot", slotId: slot.id },
  });

  const {
    setNodeRef: setDragRef,
    listeners,
    attributes,
    transform,
    isDragging,
  } = useDraggable({
    id: `player-${player.id}`,
    data: { type: "player", player, fromSlot: slot.id },
    disabled: locked,
  });

  const color = ovrColor(player.ovr);
  const isSuspended = (player.suspended ?? 0) > 0;

  const dragStyle: React.CSSProperties = transform
    ? { transform: `translate(${transform.x}px, ${transform.y}px)` }
    : {};

  return (
    <div
      ref={setDropRef}
      className="absolute -translate-x-1/2 -translate-y-1/2 z-10"
      style={{ left: `${slot.x}%`, top: `${slot.y}%` }}
    >
      <div
        ref={setDragRef}
        {...(locked ? {} : listeners)}
        {...attributes}
        className={`w-13 sm:w-20 lg:w-32.5 rounded-xl sm:rounded-xl lg:rounded-2xl border bg-[#131722] flex flex-col items-center py-1 sm:py-1.5 lg:py-2.5 px-0.5 sm:px-1.5 lg:px-2 select-none transition-all duration-200 ${
          isDragging ? "opacity-30 scale-95" : "opacity-100 scale-100"
        } ${
          locked ? "cursor-default" : "cursor-grab active:cursor-grabbing"
        } ${isOver && isDragActive ? "ring-2 ring-[#8B5CF6]/60" : ""} ${
          isSuspended ? "ring-1 ring-[#EF4444]/30" : ""
        }`}
        style={{
          borderColor: isSuspended ? "rgba(239,68,68,0.25)" : `${color}25`,
          boxShadow: isDragging ? "none" : `0 0 20px ${color}15, 0 4px 12px rgba(0,0,0,0.4)`,
          ...dragStyle,
        }}
      >
        <span className="text-[7px] sm:text-[8px] lg:text-[9px] font-bold uppercase tracking-widest text-[#9CA3AF]/40 mb-0.5 lg:mb-1.5">
          {slot.label}
        </span>
        {player.headshotUrl ? (
          <img
            src={player.headshotUrl}
            alt=""
            className="w-8 h-8 sm:w-9 sm:h-9 lg:w-12 lg:h-12 rounded-full sm:rounded-lg lg:rounded-xl object-cover object-top mb-0.5 lg:mb-1 border border-white/8 lg:border-2 shadow-lg"
            draggable={false}
          />
        ) : (
          <div
            className="w-8 h-8 sm:w-9 sm:h-9 lg:w-12 lg:h-12 rounded-full sm:rounded-lg lg:rounded-xl flex items-center justify-center mb-0.5 lg:mb-1 border border-white/8 lg:border-2"
            style={{ background: `${color}15` }}
          >
            <span className="text-xs sm:text-xs lg:text-sm font-bold" style={{ color }}>
              {player.ovr}
            </span>
          </div>
        )}
        <span className="text-[8px] sm:text-[10px] lg:text-[12px] font-semibold text-[#F3F4F6] truncate max-w-full leading-tight text-center">
          {lastName(player.name)}
        </span>
        <div className="hidden sm:flex items-center gap-1 lg:gap-1.5 mt-0.5 lg:mt-1">
          {player.headshotUrl && (
            <span className="text-[10px] lg:text-[12px] font-black leading-none" style={{ color }}>
              {player.ovr}
            </span>
          )}
          <span className="text-[8px] lg:text-[9px] text-[#9CA3AF]/60 uppercase">
            {player.position}
          </span>
        </div>

        {/* Fichado badge */}
        {player.newSigning && !isSuspended && (
          <div className="absolute -top-1 -left-1 lg:-top-1.5 lg:-left-1.5 w-4 h-4 lg:w-5 lg:h-5 rounded-full bg-[#22C55E] flex items-center justify-center shadow-md shadow-[#22C55E]/30">
            <svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round" className="lg:w-2.5 lg:h-2.5">
              <path d="M12 5v14M5 12h14" />
            </svg>
          </div>
        )}

        {/* Suspension / yellow badges */}
        {isSuspended && (
          <div className="absolute -top-1 -right-1 lg:-top-1.5 lg:-right-1.5 w-4 h-4 lg:w-5 lg:h-5 rounded-full bg-[#EF4444] flex items-center justify-center shadow-md shadow-[#EF4444]/30">
            <span className="text-[7px] lg:text-[9px] font-black text-white">!</span>
          </div>
        )}
        {!isSuspended && (player.yellowCards ?? 0) > 0 && (player.yellowCards ?? 0) % 3 === 2 && (
          <div className="absolute -top-1 -right-1 lg:-top-1.5 lg:-right-1.5 w-4 h-4 lg:w-5 lg:h-5 rounded-full bg-[#F59E0B] flex items-center justify-center shadow-md shadow-[#F59E0B]/30">
            <span className="text-[7px] lg:text-[9px] font-black text-white">{player.yellowCards}</span>
          </div>
        )}
      </div>
    </div>
  );
}

/* ── Pitch SVG field markings ──────────────────────────────── */
function PitchMarkings() {
  return (
    <svg
      viewBox="0 0 100 140"
      className="absolute inset-0 w-full h-full pointer-events-none"
      preserveAspectRatio="none"
    >
      <g stroke="rgba(139,92,246,0.05)" strokeWidth="0.35" fill="none">
        <rect x="5" y="5" width="90" height="130" rx="1.5" />
        <line x1="5" y1="70" x2="95" y2="70" />
        <circle cx="50" cy="70" r="12" />
        <circle cx="50" cy="70" r="0.6" fill="rgba(139,92,246,0.05)" />
        <rect x="22" y="110" width="56" height="25" rx="0.6" />
        <rect x="33" y="122" width="34" height="13" rx="0.6" />
        <circle cx="50" cy="118" r="0.5" fill="rgba(139,92,246,0.05)" />
        <rect x="22" y="5" width="56" height="25" rx="0.6" />
        <rect x="33" y="5" width="34" height="13" rx="0.6" />
        <circle cx="50" cy="22" r="0.5" fill="rgba(139,92,246,0.05)" />
        <path d="M 33 110 A 12 12 0 0 1 67 110" />
        <path d="M 33 30 A 12 12 0 0 0 67 30" />
      </g>
    </svg>
  );
}

/* ── Main Pitch Component ──────────────────────────────────── */
export default function FormationPitch({
  formation,
  lineup,
  activeDragPlayer,
  locked,
}: {
  formation: Formation;
  lineup: Record<string, LineupPlayer | null>;
  activeDragPlayer: LineupPlayer | null;
  locked: boolean;
}) {
  const isDragActive = activeDragPlayer !== null;

  return (
    <div className="flex-1 min-h-0 flex items-center justify-center px-2 sm:px-4 lg:px-6 py-2">
      <div
        className="relative h-full w-full"
        style={{ aspectRatio: "10 / 14", maxWidth: "720px" }}
      >
        {/* Pitch surface */}
        <div className="absolute inset-0 rounded-2xl bg-linear-to-b from-[#0A0D12] via-[#0D1117] to-[#0A0D12] border border-white/4 overflow-hidden">
          <PitchMarkings />

          <div
            className="absolute inset-0 pointer-events-none"
            style={{
              background: "radial-gradient(ellipse at 50% 50%, rgba(139,92,246,0.02) 0%, transparent 60%)",
            }}
          />

          {/* Formation slots */}
          {formation.slots.map((slot) => {
            const player = lineup[slot.id];
            if (player) {
              return (
                <FilledSlot
                  key={slot.id}
                  slot={slot}
                  player={player}
                  isDragActive={isDragActive}
                  locked={locked}
                />
              );
            }
            const isCompatible = activeDragPlayer
              ? slot.compatiblePositions.includes(
                  activeDragPlayer.position.toUpperCase()
                )
              : false;
            return (
              <EmptySlot
                key={slot.id}
                slot={slot}
                isDragActive={isDragActive}
                isCompatible={isCompatible}
              />
            );
          })}
        </div>

        {/* Locked overlay */}
        {locked && (
          <div className="absolute inset-0 rounded-2xl bg-[#0D0F14]/80 backdrop-blur-sm flex items-center justify-center z-30">
            <div className="flex flex-col items-center gap-3 text-center">
              <div className="w-12 h-12 rounded-2xl bg-[#1A1F2E] border border-white/6 flex items-center justify-center">
                <svg
                  width="20" height="20" viewBox="0 0 24 24" fill="none"
                  stroke="#9CA3AF" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round"
                >
                  <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                  <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                </svg>
              </div>
              <p className="text-[#9CA3AF] text-sm font-medium">
                Alineación bloqueada
              </p>
              <p className="text-[#9CA3AF]/50 text-xs max-w-55">
                No puedes modificar la alineación en esta fase del torneo
              </p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
