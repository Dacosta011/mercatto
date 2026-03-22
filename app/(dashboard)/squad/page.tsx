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

/* ── Types & helpers ───────────────────────────────────────── */

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

type PosFilter = "Todos" | "POR" | "DEF" | "MED" | "DEL";
type ActiveTab = "lineup" | "squad";

const POS_GROUPS: Record<PosFilter, string[]> = {
  Todos: [],
  POR: ["POR", "GK"],
  DEF: ["DFC", "CB", "LI", "LD", "LB", "RB", "SW", "WB", "LWB", "RWB"],
  MED: ["MCD", "MC", "MCO", "MI", "MD", "CM", "CDM", "CAM", "LM", "RM"],
  DEL: ["DC", "SD", "EI", "ED", "CF", "ST", "LW", "RW", "SS"],
};

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

function lastName(name: string) {
  const parts = name.trim().split(" ");
  return parts.length > 1 ? parts[parts.length - 1] : name;
}

/* ── Page ──────────────────────────────────────────────────── */

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

  const [activeTab, setActiveTab] = useState<ActiveTab>("lineup");
  const [squadSearch, setSquadSearch] = useState("");
  const [squadFilter, setSquadFilter] = useState<PosFilter>("Todos");

  const formation = formations[formationId];

  /* ── Data fetching ───────────────────────────────────────── */
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

  /* ── Initialize empty lineup on formation change ─────────── */
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

  /* ── Derived state ───────────────────────────────────────── */
  const lineupPlayerIds = useMemo(() => {
    const ids = new Set<string>();
    Object.values(lineup).forEach((p) => {
      if (p) ids.add(p.id);
    });
    return ids;
  }, [lineup]);

  const lineupCount = lineupPlayerIds.size;

  /* ── DnD sensors ─────────────────────────────────────────── */
  const pointerSensor = useSensor(PointerSensor, {
    activationConstraint: { distance: 8 },
  });
  const sensors = useSensors(pointerSensor);

  const collisionDetection: CollisionDetection = useCallback(
    (args) => {
      const pw = pointerWithin(args);
      if (pw.length > 0) return pw;
      return rectIntersection(args);
    },
    [],
  );

  /* ── DnD handlers ────────────────────────────────────────── */
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

  /* ── Auto fill best XI ───────────────────────────────────── */
  const autoFill = useCallback(() => {
    if (!squad) return;
    const available = [...squad.players].sort((a, b) => b.ovr - a.ovr);
    const used = new Set<string>();
    const newLineup: Record<string, LineupPlayer | null> = {};

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

  /* ── Reset lineup ────────────────────────────────────────── */
  const resetLineup = useCallback(() => {
    const empty: Record<string, LineupPlayer | null> = {};
    formation.slots.forEach((s) => {
      empty[s.id] = null;
    });
    setLineup(empty);
  }, [formation.slots]);

  /* ── Save lineup ─────────────────────────────────────────── */
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

  /* ── Assign player to lineup (Plantilla tab) ─────────────── */
  const assignToLineup = useCallback(
    (player: LineupPlayer) => {
      const pos = player.position.toUpperCase();
      const compatibleSlot = formation.slots.find(
        (slot) => !lineup[slot.id] && slot.compatiblePositions.includes(pos)
      );
      if (compatibleSlot) {
        setLineup((prev) => ({ ...prev, [compatibleSlot.id]: player }));
        setToast(`${lastName(player.name)} añadido`);
        setTimeout(() => setToast(null), 2000);
        return;
      }
      const anySlot = formation.slots.find((slot) => !lineup[slot.id]);
      if (anySlot) {
        setLineup((prev) => ({ ...prev, [anySlot.id]: player }));
        setToast(`${lastName(player.name)} añadido`);
        setTimeout(() => setToast(null), 2000);
        return;
      }
      setToast("Alineación completa");
      setTimeout(() => setToast(null), 2000);
    },
    [formation.slots, lineup],
  );

  /* ── Remove player from lineup ───────────────────────────── */
  const removeFromLineup = useCallback((playerId: string) => {
    setLineup((prev) => {
      const next = { ...prev };
      for (const [slotId, p] of Object.entries(next)) {
        if (p?.id === playerId) next[slotId] = null;
      }
      return next;
    });
  }, []);

  /* ── Get slot label for lineup player ────────────────────── */
  const getSlotLabel = useCallback(
    (playerId: string): string | null => {
      for (const [slotId, p] of Object.entries(lineup)) {
        if (p?.id === playerId) {
          const slot = formation.slots.find((s) => s.id === slotId);
          return slot?.label ?? null;
        }
      }
      return null;
    },
    [lineup, formation.slots],
  );

  /* ── Filtered squad list for Plantilla tab ───────────────── */
  const squadFiltered = useMemo(() => {
    return (squad?.players ?? [])
      .filter((p) => {
        const matchSearch =
          squadSearch.length === 0 ||
          p.name.toLowerCase().includes(squadSearch.toLowerCase());
        const matchFilter =
          squadFilter === "Todos" ||
          POS_GROUPS[squadFilter].includes(p.position.toUpperCase());
        return matchSearch && matchFilter;
      })
      .sort((a, b) => {
        const aIn = lineupPlayerIds.has(a.id) ? 0 : 1;
        const bIn = lineupPlayerIds.has(b.id) ? 0 : 1;
        if (aIn !== bIn) return aIn - bIn;
        return b.ovr - a.ovr;
      });
  }, [squad?.players, squadSearch, squadFilter, lineupPlayerIds]);

  /* ── Loading ─────────────────────────────────────────────── */
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

  /* ── Error ───────────────────────────────────────────────── */
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
        className="flex flex-col h-full"
      >
        {/* ── Compact header ──────────────────────────── */}
        <div className="px-4 lg:px-6 pt-3 lg:pt-5 pb-2 lg:pb-4 shrink-0">
          {/* Row 1: Team + desktop actions */}
          <div className="flex items-center justify-between mb-2 lg:mb-3 gap-2">
            <div className="flex items-center gap-2.5 min-w-0">
              {team.crestUrl && (
                <img
                  src={team.crestUrl}
                  alt={team.name}
                  className="w-8 h-8 lg:w-10 lg:h-10 object-contain shrink-0"
                />
              )}
              <div className="min-w-0">
                <p className="text-[9px] lg:text-[10px] font-semibold uppercase tracking-[0.15em] text-[#9CA3AF]/60 mb-0.5 hidden lg:block">
                  Mi Equipo
                </p>
                <h1 className="text-[#F3F4F6] text-base lg:text-lg font-bold tracking-tight leading-tight truncate">
                  {team.name}
                </h1>
              </div>
            </div>

            <div className="hidden lg:flex items-center gap-2 shrink-0">
              <Button variant="ghost" size="sm" onClick={resetLineup} disabled={locked || lineupCount === 0}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="1 4 1 10 7 10" />
                  <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10" />
                </svg>
                Resetear
              </Button>
              <Button variant="primary" size="sm" onClick={saveLineup} disabled={locked || lineupCount < 11 || saving}>
                {saving ? (
                  <div className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                ) : (
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z" />
                    <polyline points="17 21 17 13 7 13 7 21" />
                    <polyline points="7 3 7 8 15 8" />
                  </svg>
                )}
                {saving ? "Guardando…" : "Guardar"}
              </Button>
            </div>
          </div>

          {/* Row 2: Stats pills + Formation */}
          <div className="flex items-center gap-1.5 lg:gap-3">
            <div className="flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-[#131722] border border-white/4 shrink-0">
              <span className="text-[9px] text-[#9CA3AF]/60 uppercase tracking-wide">€</span>
              <span className="text-[11px] font-semibold text-[#F3F4F6]">{fmtMoney(team.budget)}</span>
            </div>
            <div className="hidden sm:flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-[#131722] border border-white/4 shrink-0">
              <span className="text-[9px] text-[#9CA3AF]/60 uppercase tracking-wide">Val</span>
              <span className="text-[11px] font-semibold text-[#F3F4F6]">{fmtMoney(team.squadValue)}</span>
            </div>
            <div className="flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-[#131722] border border-white/4 shrink-0">
              <span className="text-[9px] text-[#9CA3AF]/60 uppercase tracking-wide">OVR</span>
              <span className="text-[11px] font-bold" style={{ color: ovrColor(avgOvr) }}>{avgOvr || "—"}</span>
            </div>
            <div className="flex-1" />
            <div className="flex items-center gap-1 px-2.5 py-1.5 rounded-xl bg-[#131722] border border-white/4 shrink-0">
              <span className="text-[9px] text-[#9CA3AF]/60 uppercase tracking-wide">Form.</span>
              <select
                value={formationId}
                onChange={(e) => setFormationId(e.target.value as FormationId)}
                disabled={locked}
                className="bg-transparent text-[11px] font-bold text-[#8B5CF6] outline-none cursor-pointer appearance-none pr-4"
                style={{
                  backgroundImage: `url("data:image/svg+xml,%3Csvg width='10' height='6' viewBox='0 0 10 6' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 1L5 5L9 1' stroke='%238B5CF6' stroke-width='1.5' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E")`,
                  backgroundRepeat: "no-repeat",
                  backgroundPosition: "right center",
                }}
              >
                {FORMATION_IDS.map((fId) => (
                  <option key={fId} value={fId} className="bg-[#131722] text-[#F3F4F6]">{fId}</option>
                ))}
              </select>
            </div>
          </div>
        </div>

        {/* ── Mobile tab bar ──────────────────────────── */}
        <div className="lg:hidden px-4 pb-3 shrink-0">
          <div className="flex bg-[#131722] rounded-xl p-1 gap-1">
            <button
              onClick={() => setActiveTab("lineup")}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2.5 rounded-lg text-xs font-semibold transition-all duration-200 cursor-pointer ${
                activeTab === "lineup"
                  ? "bg-[#8B5CF6]/15 text-[#8B5CF6] shadow-sm"
                  : "text-[#9CA3AF] active:bg-white/5"
              }`}
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <rect x="2" y="2" width="20" height="20" rx="2" />
                <line x1="2" y1="12" x2="22" y2="12" />
                <circle cx="12" cy="12" r="3" />
              </svg>
              Alineación
              <span className={`text-[10px] font-bold tabular-nums ${lineupCount === 11 ? "text-[#22C55E]" : ""}`}>
                {lineupCount}/11
              </span>
            </button>
            <button
              onClick={() => setActiveTab("squad")}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2.5 rounded-lg text-xs font-semibold transition-all duration-200 cursor-pointer ${
                activeTab === "squad"
                  ? "bg-[#8B5CF6]/15 text-[#8B5CF6] shadow-sm"
                  : "text-[#9CA3AF] active:bg-white/5"
              }`}
            >
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                <circle cx="9" cy="7" r="4" />
                <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
                <path d="M16 3.13a4 4 0 0 1 0 7.75" />
              </svg>
              Plantilla
              <span className="text-[10px] text-[#9CA3AF]/60">{squad.players.length}</span>
            </button>
          </div>
        </div>

        {/* ── Content area ────────────────────────────── */}
        <div className="flex-1 flex flex-col lg:flex-row min-h-0 overflow-hidden">
          {/* ── Lineup view (pitch) ──── */}
          <div className={`${activeTab === "lineup" ? "flex" : "hidden"} lg:flex flex-1 flex-col min-h-0`}>
            <FormationPitch
              formation={formation}
              lineup={lineup}
              activeDragPlayer={activeDragPlayer}
              locked={locked}
            />

            {/* Mobile action bar */}
            <div className="lg:hidden shrink-0 px-4 py-3 border-t border-white/6 bg-[#0D0F14]/90 backdrop-blur-sm">
              <div className="flex items-center gap-2">
                <button
                  onClick={autoFill}
                  disabled={locked}
                  className="px-3.5 py-2.5 rounded-xl bg-[#131722] border border-white/6 text-xs font-semibold text-[#8B5CF6] active:bg-[#1A1F2E] transition-colors duration-150 cursor-pointer disabled:opacity-40"
                >
                  Auto XI
                </button>
                <button
                  onClick={resetLineup}
                  disabled={locked || lineupCount === 0}
                  className="p-2.5 rounded-xl bg-[#131722] border border-white/6 text-[#9CA3AF] active:bg-[#1A1F2E] transition-colors duration-150 cursor-pointer disabled:opacity-40"
                >
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="1 4 1 10 7 10" />
                    <path d="M3.51 15a9 9 0 1 0 2.13-9.36L1 10" />
                  </svg>
                </button>
                <div className="flex-1" />
                <button
                  onClick={saveLineup}
                  disabled={locked || lineupCount < 11 || saving}
                  className="flex items-center justify-center gap-2 px-5 py-2.5 rounded-xl bg-[#8B5CF6] active:bg-[#7C3AED] text-white text-xs font-semibold transition-colors duration-150 cursor-pointer disabled:opacity-40 shadow-lg shadow-[#8B5CF6]/20"
                >
                  {saving ? (
                    <div className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
                  ) : (
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                      <polyline points="20 6 9 17 4 12" />
                    </svg>
                  )}
                  {saving ? "Guardando…" : "Guardar alineación"}
                </button>
              </div>
            </div>
          </div>

          {/* ── Squad list (mobile Plantilla tab) ──── */}
          <div className={`${activeTab === "squad" ? "flex" : "hidden"} lg:hidden flex-1 flex-col min-h-0`}>
            {/* Search + filter chips */}
            <div className="px-4 pb-3 shrink-0">
              <div className="relative mb-2.5">
                <svg
                  width="14" height="14" viewBox="0 0 24 24" fill="none"
                  stroke="#9CA3AF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
                  className="absolute left-3 top-1/2 -translate-y-1/2 opacity-40"
                >
                  <circle cx="11" cy="11" r="8" />
                  <line x1="21" y1="21" x2="16.65" y2="16.65" />
                </svg>
                <input
                  type="text"
                  placeholder="Buscar jugador…"
                  value={squadSearch}
                  onChange={(e) => setSquadSearch(e.target.value)}
                  className="w-full bg-[#131722] border border-white/4 rounded-xl pl-9 pr-3 py-2.5 text-sm text-[#F3F4F6] placeholder-[#9CA3AF]/40 outline-none focus:border-[#8B5CF6]/30 transition-colors duration-150"
                />
              </div>
              <div className="flex items-center gap-1.5">
                {(["Todos", "POR", "DEF", "MED", "DEL"] as PosFilter[]).map((f) => (
                  <button
                    key={f}
                    onClick={() => setSquadFilter(f)}
                    className={`px-3 py-1.5 rounded-lg text-xs font-semibold transition-colors duration-150 cursor-pointer shrink-0 ${
                      squadFilter === f
                        ? "bg-[#8B5CF6]/10 text-[#8B5CF6]"
                        : "text-[#9CA3AF]/60 active:text-[#9CA3AF] active:bg-[#1A1F2E]"
                    }`}
                  >
                    {f}
                  </button>
                ))}
              </div>
            </div>

            {/* Player list */}
            <div className="flex-1 overflow-y-auto px-4 pb-4 flex flex-col gap-1.5">
              {squadFiltered.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-16 text-center">
                  <p className="text-[#9CA3AF]/40 text-sm">Sin resultados</p>
                </div>
              ) : (
                squadFiltered.map((player) => {
                  const inLineup = lineupPlayerIds.has(player.id);
                  const slotLabel = inLineup ? getSlotLabel(player.id) : null;
                  const color = ovrColor(player.ovr);
                  const isSuspended = (player.suspended ?? 0) > 0;
                  const ringClass =
                    player.ovr >= 90 ? "ring-[#8B5CF6]/50"
                    : player.ovr >= 85 ? "ring-[#22C55E]/50"
                    : player.ovr >= 80 ? "ring-[#F59E0B]/50"
                    : "ring-white/10";

                  return (
                    <div
                      key={player.id}
                      className={`flex items-center gap-3 px-3 py-2.5 rounded-2xl border transition-all duration-150 ${
                        inLineup
                          ? "bg-[#8B5CF6]/4 border-[#8B5CF6]/15"
                          : "bg-[#0D0F14] border-white/4"
                      } ${isSuspended ? "opacity-40 grayscale" : ""}`}
                    >
                      {/* Avatar + OVR */}
                      <div className="relative shrink-0">
                        {player.headshotUrl ? (
                          <img
                            src={player.headshotUrl}
                            alt=""
                            className={`w-10 h-10 rounded-full object-cover object-top ring-2 ${ringClass}`}
                          />
                        ) : (
                          <div
                            className={`w-10 h-10 rounded-full ring-2 ${ringClass} flex items-center justify-center`}
                            style={{ background: `${color}15` }}
                          >
                            <span className="text-sm font-bold" style={{ color }}>
                              {player.name.charAt(0)}
                            </span>
                          </div>
                        )}
                        <div
                          className="absolute -bottom-0.5 -right-0.5 min-w-5 h-4 rounded-full flex items-center justify-center text-[9px] font-black text-white px-0.5"
                          style={{ background: color, boxShadow: `0 0 6px ${color}50` }}
                        >
                          {player.ovr}
                        </div>
                      </div>

                      {/* Info */}
                      <div className="flex-1 min-w-0">
                        <p className="text-[13px] font-semibold text-[#F3F4F6] truncate leading-tight">
                          {player.name}
                        </p>
                        <div className="flex items-center gap-1.5 mt-0.5">
                          <span
                            className="text-[9px] font-bold uppercase tracking-wider px-1.5 py-px rounded"
                            style={{ color, background: `${color}15` }}
                          >
                            {player.position}
                          </span>
                          {player.price ? (
                            <span className="text-[9px] text-[#9CA3AF]/70">{fmtMoney(player.price)}</span>
                          ) : null}
                          {player.clause ? (
                            <span className="text-[9px] text-[#F59E0B]/60">Cl {fmtMoney(player.clause)}</span>
                          ) : null}
                        </div>
                      </div>

                      {/* Action */}
                      {isSuspended ? (
                        <div className="shrink-0 px-2 py-1 rounded-lg bg-[#EF4444]/10 text-[9px] font-semibold text-[#EF4444]">
                          Sanción
                        </div>
                      ) : inLineup ? (
                        <button
                          onClick={() => removeFromLineup(player.id)}
                          className="shrink-0 flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-[#22C55E]/10 text-[#22C55E] text-[10px] font-semibold cursor-pointer transition-colors duration-150 active:bg-[#EF4444]/10 active:text-[#EF4444]"
                        >
                          <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                            <polyline points="20 6 9 17 4 12" />
                          </svg>
                          {slotLabel ?? "XI"}
                        </button>
                      ) : (
                        <button
                          onClick={() => assignToLineup(player)}
                          disabled={lineupCount >= 11}
                          className="shrink-0 px-2.5 py-1.5 rounded-lg bg-[#8B5CF6]/10 text-[#8B5CF6] text-[10px] font-semibold cursor-pointer transition-colors duration-150 active:bg-[#8B5CF6]/20 disabled:opacity-30"
                        >
                          + Añadir
                        </button>
                      )}
                    </div>
                  );
                })
              )}
            </div>
          </div>

          {/* ── Desktop bench panel ──── */}
          <div className="hidden lg:flex">
            <BenchPanel
              allPlayers={squad.players}
              lineupPlayerIds={lineupPlayerIds}
              onAutoFill={autoFill}
              locked={locked}
            />
          </div>
        </div>
      </motion.div>

      {/* ── Drag overlay ──────────────────────────────── */}
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
              className="w-50 sm:w-65 lg:w-80 flex items-center gap-3 lg:gap-5 px-3 lg:px-5 py-2.5 lg:py-4 rounded-xl lg:rounded-2xl border bg-[#0D0F14] pointer-events-none"
              style={{
                borderColor: `${color}40`,
                boxShadow: `0 0 30px ${color}25, 0 8px 24px rgba(0,0,0,0.6)`,
              }}
            >
              <div className="relative shrink-0">
                {activeDragPlayer.headshotUrl ? (
                  <img src={activeDragPlayer.headshotUrl} alt="" className={`w-10 h-10 sm:w-12 sm:h-12 lg:w-16 lg:h-16 rounded-full object-cover object-top ring-2 lg:ring-[3px] ${ringClass}`} draggable={false} />
                ) : (
                  <div className={`w-10 h-10 sm:w-12 sm:h-12 lg:w-16 lg:h-16 rounded-full bg-[#131722] ring-2 lg:ring-[3px] ${ringClass} flex items-center justify-center`}>
                    <span className="text-sm lg:text-xl font-bold text-[#9CA3AF]/50">{activeDragPlayer.name.charAt(0)}</span>
                  </div>
                )}
                <div
                  className="absolute -bottom-1 -right-1 min-w-5.5 lg:min-w-7.5 h-4.5 lg:h-5.5 rounded-full flex items-center justify-center text-[10px] lg:text-xs font-black text-white px-1"
                  style={{ background: color, boxShadow: `0 0 10px ${color}60` }}
                >
                  {activeDragPlayer.ovr}
                </div>
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm lg:text-base font-semibold text-[#F3F4F6] truncate leading-tight">{activeDragPlayer.name}</p>
                <div className="flex items-center gap-1.5 lg:gap-2 mt-1">
                  <span className="text-[10px] lg:text-xs font-bold uppercase tracking-wider px-1.5 lg:px-2 py-0.5 rounded" style={{ color, background: `${color}15` }}>{activeDragPlayer.position}</span>
                  {activeDragPlayer.countryName && (
                    <span className="text-xs lg:text-sm text-[#9CA3AF]/60 truncate hidden sm:inline">{activeDragPlayer.countryName}</span>
                  )}
                </div>
              </div>
            </div>
          );
        })()}
      </DragOverlay>

      {/* ── Toast ─────────────────────────────────────── */}
      <AnimatePresence>
        {toast && (
          <motion.div
            initial={{ opacity: 0, y: 20, scale: 0.95 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: 10, scale: 0.95 }}
            transition={{ duration: 0.2 }}
            className="fixed bottom-32 lg:bottom-6 left-1/2 lg:left-auto lg:right-6 -translate-x-1/2 lg:translate-x-0 z-50 flex items-center gap-2.5 px-5 py-3 rounded-xl bg-[#131722] border border-[#8B5CF6]/20 shadow-2xl shadow-[#8B5CF6]/10"
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
