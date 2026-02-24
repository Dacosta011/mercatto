"use client";

import { useEffect, useState, useMemo, useCallback } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  DndContext,
  DragOverlay,
  PointerSensor,
  useSensor,
  useSensors,
  pointerWithin,
  rectIntersection,
  type DragStartEvent,
  type DragEndEvent,
  type CollisionDetection,
} from "@dnd-kit/core";
import { getLastTournamentCode, getMemberToken } from "@/lib/tokenStorage";
import Button from "../../Components/Button";
import FormationPitch from "./_components/FormationPitch";
import type { LineupPlayer } from "./_components/FormationPitch";
import BenchPanel from "./_components/BenchPanel";
import formations, { FORMATION_IDS, type FormationId } from "./_lib/formations";

interface SquadData {
  team: {
    id: string;
    name: string;
    crestUrl: string | null;
    squadValue: number;
    budget: number;
  };
  players: LineupPlayer[];
  avgOvr: number;
}

function fmtMoney(cents: number) {
  if (!cents) return "—";
  if (cents >= 1_000_000) return `€${(cents / 1_000_000).toFixed(0)}M`;
  if (cents >= 1_000) return `€${(cents / 1_000).toFixed(0)}K`;
  return `€${cents}`;
}

function ovrColor(ovr: number) {
  if (ovr >= 90) return "#8B5CF6";
  if (ovr >= 85) return "#22C55E";
  if (ovr >= 80) return "#F59E0B";
  return "#9CA3AF";
}

export default function SquadPage() {
  const [squad, setSquad] = useState<SquadData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [formationId, setFormationId] = useState<FormationId>("4-3-3");
  const [lineup, setLineup] = useState<Record<string, LineupPlayer | null>>({});
  const [activeDragPlayer, setActiveDragPlayer] = useState<LineupPlayer | null>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [locked] = useState(false);
  const [savedLineupLoaded, setSavedLineupLoaded] = useState(false);

  const formation = formations[formationId];

  // ── Data fetching ──────────────────────────────────────────
  useEffect(() => {
    const code = getLastTournamentCode();
    const token = code ? getMemberToken(code) : null;

    if (!code || !token) {
      setError("No estás en ningún torneo activo.");
      setLoading(false);
      return;
    }

    const headers = { Authorization: `Bearer ${token}` };

    Promise.all([
      fetch(`/api/tournaments/${code}/squad`, { headers }).then((r) => r.json()),
      fetch(`/api/tournaments/${code}/squad/lineup`, { headers }).then((r) => r.json()),
    ])
      .then(([squadData, lineupData]) => {
        if (squadData.error) {
          setError(squadData.error);
          return;
        }
        const sq = squadData as SquadData;
        setSquad(sq);

        // Restore saved lineup if available
        if (lineupData.formation && lineupData.slots) {
          const savedFormation = lineupData.formation as string;
          if (["4-3-3", "4-4-2", "4-2-3-1", "3-5-2"].includes(savedFormation)) {
            setFormationId(savedFormation as FormationId);
            const savedSlots = lineupData.slots as Record<string, string | null>;
            const playerMap = new Map(sq.players.map((p) => [p.id, p]));
            const restoredLineup: Record<string, LineupPlayer | null> = {};
            const fm = formations[savedFormation as FormationId];
            for (const slot of fm.slots) {
              const playerId = savedSlots[slot.id];
              restoredLineup[slot.id] = playerId ? playerMap.get(playerId) ?? null : null;
            }
            setLineup(restoredLineup);
            setSavedLineupLoaded(true);
          }
        }
      })
      .catch(() => setError("Error al cargar la plantilla."))
      .finally(() => setLoading(false));
  }, []);

  // ── Initialize empty lineup on formation change (only if no saved lineup was loaded) ──
  useEffect(() => {
    if (savedLineupLoaded) {
      setSavedLineupLoaded(false);
      return;
    }
    const newLineup: Record<string, LineupPlayer | null> = {};
    formation.slots.forEach((slot) => {
      newLineup[slot.id] = null;
    });
    setLineup(newLineup);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [formationId]);

  // ── Derived state ──────────────────────────────────────────
  const lineupPlayerIds = useMemo(() => {
    const ids = new Set<string>();
    Object.values(lineup).forEach((p) => {
      if (p) ids.add(p.id);
    });
    return ids;
  }, [lineup]);

  const lineupCount = lineupPlayerIds.size;

  // ── DnD sensors ────────────────────────────────────────────
  const pointerSensor = useSensor(PointerSensor, {
    activationConstraint: { distance: 8 },
  });
  const sensors = useSensors(pointerSensor);

  // Prefer pointerWithin so the large bench panel is detected when the
  // cursor is anywhere inside it; fall back to rectIntersection.
  const collisionDetection: CollisionDetection = useCallback(
    (args) => {
      const pw = pointerWithin(args);
      if (pw.length > 0) return pw;
      return rectIntersection(args);
    },
    [],
  );

  // ── DnD handlers ───────────────────────────────────────────
  const handleDragStart = useCallback((event: DragStartEvent) => {
    const data = event.active.data.current as {
      player: LineupPlayer;
      fromSlot: string | null;
    };
    setActiveDragPlayer(data.player);
  }, []);

  const handleDragEnd = useCallback(
    (event: DragEndEvent) => {
      const { active, over } = event;

      // Always clear drag state first
      setActiveDragPlayer(null);

      if (!over) return;

      const activeData = active.data.current as {
        player: LineupPlayer;
        fromSlot: string | null;
      };
      const player = activeData.player;
      const fromSlot = activeData.fromSlot;
      const overData = over.data.current as
        | { type: "slot"; slotId: string }
        | { type: "bench" };

      // Defer lineup update so dnd-kit fully resets its internal drag
      // state before React re-renders with different component ownership
      // of the same draggable ID.
      requestAnimationFrame(() => {
        if (overData.type === "slot") {
          const targetSlotId = overData.slotId;

          if (fromSlot) {
            setLineup((prev) => ({
              ...prev,
              [fromSlot]: prev[targetSlotId] ?? null,
              [targetSlotId]: player,
            }));
          } else {
            setLineup((prev) => ({
              ...prev,
              [targetSlotId]: player,
            }));
          }
        } else if (overData.type === "bench") {
          if (fromSlot) {
            setLineup((prev) => ({
              ...prev,
              [fromSlot]: null,
            }));
          }
        }
      });
    },
    [],
  );

  const handleDragCancel = useCallback(() => {
    setActiveDragPlayer(null);
  }, []);

  // ── Auto fill best XI ─────────────────────────────────────
  const autoFill = useCallback(() => {
    if (!squad) return;
    const available = [...squad.players].sort((a, b) => b.ovr - a.ovr);
    const used = new Set<string>();
    const newLineup: Record<string, LineupPlayer | null> = {};

    // GK first
    const gkSlot = formation.slots.find((s) => s.id === "gk");
    if (gkSlot) {
      const gk = available.find(
        (p) =>
          !used.has(p.id) &&
          gkSlot.compatiblePositions.includes(p.position.toUpperCase())
      );
      if (gk) {
        newLineup[gkSlot.id] = gk;
        used.add(gk.id);
      }
    }

    // Position-compatible pass
    for (const slot of formation.slots) {
      if (newLineup[slot.id]) continue;
      const match = available.find(
        (p) =>
          !used.has(p.id) &&
          slot.compatiblePositions.includes(p.position.toUpperCase())
      );
      if (match) {
        newLineup[slot.id] = match;
        used.add(match.id);
      }
    }

    // Fill remaining with highest OVR regardless of position
    for (const slot of formation.slots) {
      if (newLineup[slot.id]) continue;
      const match = available.find((p) => !used.has(p.id));
      if (match) {
        newLineup[slot.id] = match;
        used.add(match.id);
      } else {
        newLineup[slot.id] = null;
      }
    }

    setLineup(newLineup);
  }, [squad, formation.slots]);

  // ── Reset lineup ───────────────────────────────────────────
  const resetLineup = useCallback(() => {
    const empty: Record<string, LineupPlayer | null> = {};
    formation.slots.forEach((s) => {
      empty[s.id] = null;
    });
    setLineup(empty);
  }, [formation.slots]);

  // ── Save lineup ────────────────────────────────────────────
  const saveLineup = useCallback(async () => {
    const code = getLastTournamentCode();
    const token = code ? getMemberToken(code) : null;
    if (!code || !token) return;

    setSaving(true);
    try {
      const slotsPayload: Record<string, string | null> = {};
      for (const [slotId, player] of Object.entries(lineup)) {
        slotsPayload[slotId] = player?.id ?? null;
      }

      const res = await fetch(`/api/tournaments/${code}/squad/lineup`, {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ formation: formationId, slots: slotsPayload }),
      });

      const data = await res.json();
      if (data.ok) {
        setToast("Alineación guardada");
      } else {
        setToast(data.error ?? "Error al guardar");
      }
    } catch {
      setToast("Error de conexión");
    } finally {
      setSaving(false);
      setTimeout(() => setToast(null), 2500);
    }
  }, [lineup, formationId]);

  // ── Loading ────────────────────────────────────────────────
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

  // ── Error ──────────────────────────────────────────────────
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
    <DndContext
      sensors={sensors}
      collisionDetection={collisionDetection}
      onDragStart={handleDragStart}
      onDragEnd={handleDragEnd}
      onDragCancel={handleDragCancel}
    >
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.3 }}
        className="flex h-full"
      >
        {/* ── Left: Header + Pitch ────────────────────────── */}
        <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
          {/* Header */}
          <div className="px-6 pt-5 pb-4 shrink-0">
            {/* Row 1: Team info + actions */}
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3.5">
                {team.crestUrl && (
                  <img
                    src={team.crestUrl}
                    alt={team.name}
                    className="w-10 h-10 object-contain"
                  />
                )}
                <div>
                  <p className="text-[10px] font-semibold uppercase tracking-[0.15em] text-[#9CA3AF]/60 mb-0.5">
                    Mi Equipo
                  </p>
                  <h1 className="text-[#F3F4F6] text-lg font-bold tracking-tight leading-tight">
                    {team.name}
                  </h1>
                </div>
              </div>

              <div className="flex items-center gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={resetLineup}
                  disabled={locked || lineupCount === 0}
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="1 4 1 10 7 10" />
                    <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10" />
                  </svg>
                  Resetear
                </Button>
                <Button
                  variant="primary"
                  size="sm"
                  onClick={saveLineup}
                  disabled={locked || lineupCount < 11 || saving}
                >
                  {saving ? (
                    <div className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  ) : (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z" />
                      <polyline points="17 21 17 13 7 13 7 21" />
                      <polyline points="7 3 7 8 15 8" />
                    </svg>
                  )}
                  {saving ? "Guardando…" : "Guardar alineación"}
                </Button>
              </div>
            </div>

            {/* Row 2: Stats + Formation selector */}
            <div className="flex items-center gap-3 flex-wrap">
              {/* Stat pills */}
              <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#131722] border border-white/4">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="opacity-50">
                  <line x1="12" y1="1" x2="12" y2="23" />
                  <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
                </svg>
                <span className="text-[10px] text-[#9CA3AF]/60 uppercase tracking-wide">Presupuesto</span>
                <span className="text-[12px] font-semibold text-[#F3F4F6]">
                  {fmtMoney(team.budget)}
                </span>
              </div>

              <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#131722] border border-white/4">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="opacity-50">
                  <polyline points="22 7 13.5 15.5 8.5 10.5 2 17" />
                  <polyline points="16 7 22 7 22 13" />
                </svg>
                <span className="text-[10px] text-[#9CA3AF]/60 uppercase tracking-wide">Valor</span>
                <span className="text-[12px] font-semibold text-[#F3F4F6]">
                  {fmtMoney(team.squadValue)}
                </span>
              </div>

              <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#131722] border border-white/4">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#9CA3AF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="opacity-50">
                  <path d="M18 20V10" /><path d="M12 20V4" /><path d="M6 20v-6" />
                </svg>
                <span className="text-[10px] text-[#9CA3AF]/60 uppercase tracking-wide">OVR</span>
                <span
                  className="text-[12px] font-bold"
                  style={{ color: ovrColor(avgOvr) }}
                >
                  {avgOvr || "—"}
                </span>
              </div>

              {/* Spacer */}
              <div className="flex-1" />

              {/* Formation selector */}
              <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-[#131722] border border-white/4">
                <span className="text-[10px] text-[#9CA3AF]/60 uppercase tracking-wide">
                  Formación
                </span>
                <select
                  value={formationId}
                  onChange={(e) => setFormationId(e.target.value as FormationId)}
                  disabled={locked}
                  className="bg-transparent text-[12px] font-bold text-[#8B5CF6] outline-none cursor-pointer appearance-none pr-4"
                  style={{
                    backgroundImage: `url("data:image/svg+xml,%3Csvg width='10' height='6' viewBox='0 0 10 6' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 1L5 5L9 1' stroke='%238B5CF6' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E")`,
                    backgroundRepeat: "no-repeat",
                    backgroundPosition: "right center",
                  }}
                >
                  {FORMATION_IDS.map((fId) => (
                    <option key={fId} value={fId} className="bg-[#131722] text-[#F3F4F6]">
                      {fId}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          </div>

          {/* Pitch */}
          <FormationPitch
            formation={formation}
            lineup={lineup}
            activeDragPlayer={activeDragPlayer}
            locked={locked}
          />
        </div>

        {/* ── Right: Bench panel ──────────────────────────── */}
        <BenchPanel
          allPlayers={squad.players}
          lineupPlayerIds={lineupPlayerIds}
          onAutoFill={autoFill}
          locked={locked}
        />
      </motion.div>

      {/* ── Drag overlay ──────────────────────────────────── */}
      <DragOverlay
        dropAnimation={{
          duration: 200,
          easing: "cubic-bezier(0.18, 0.67, 0.6, 1.22)",
        }}
      >
        {activeDragPlayer && (() => {
          const color = ovrColor(activeDragPlayer.ovr);
          const ringClass = activeDragPlayer.ovr >= 90 ? "ring-[#8B5CF6]/50" : activeDragPlayer.ovr >= 85 ? "ring-[#22C55E]/50" : activeDragPlayer.ovr >= 80 ? "ring-[#F59E0B]/50" : "ring-white/10";
          return (
            <div
              className="w-[320px] flex items-center gap-5 px-5 py-4 rounded-2xl border bg-[#0D0F14] pointer-events-none"
              style={{
                borderColor: `${color}40`,
                boxShadow: `0 0 30px ${color}25, 0 8px 24px rgba(0,0,0,0.6)`,
              }}
            >
              <div className="relative shrink-0">
                {activeDragPlayer.headshotUrl ? (
                  <img src={activeDragPlayer.headshotUrl} alt="" className={`w-16 h-16 rounded-full object-cover object-top ring-[3px] ${ringClass}`} draggable={false} />
                ) : (
                  <div className={`w-16 h-16 rounded-full bg-[#131722] ring-[3px] ${ringClass} flex items-center justify-center`}>
                    <span className="text-xl font-bold text-[#9CA3AF]/50">{activeDragPlayer.name.charAt(0)}</span>
                  </div>
                )}
                <div
                  className="absolute -bottom-1 -right-1 min-w-[30px] h-[22px] rounded-full flex items-center justify-center text-xs font-black text-white px-1.5"
                  style={{ background: color, boxShadow: `0 0 10px ${color}60` }}
                >
                  {activeDragPlayer.ovr}
                </div>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-base font-semibold text-[#F3F4F6] truncate leading-tight">{activeDragPlayer.name}</p>
                <div className="flex items-center gap-2 mt-1.5">
                  <span className="text-xs font-bold uppercase tracking-wider px-2 py-0.5 rounded" style={{ color, background: `${color}15` }}>{activeDragPlayer.position}</span>
                  {activeDragPlayer.countryName && (
                    <span className="text-sm text-[#9CA3AF]/60 truncate">{activeDragPlayer.countryName}</span>
                  )}
                </div>
              </div>
            </div>
          );
        })()}
      </DragOverlay>

      {/* ── Toast ─────────────────────────────────────────── */}
      <AnimatePresence>
        {toast && (
          <motion.div
            initial={{ opacity: 0, y: 20, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 10, scale: 0.95 }}
            transition={{ duration: 0.2 }}
            className="fixed bottom-6 right-6 z-50 flex items-center gap-2.5 px-5 py-3 rounded-xl bg-[#131722] border border-[#8B5CF6]/20 shadow-2xl shadow-[#8B5CF6]/10"
          >
            <div className="w-5 h-5 rounded-full bg-[#22C55E]/15 flex items-center justify-center shrink-0">
              <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="20 6 9 17 4 12" />
              </svg>
            </div>
            <span className="text-[13px] font-medium text-[#F3F4F6]">{toast}</span>
          </motion.div>
        )}
      </AnimatePresence>
    </DndContext>
  );
}
