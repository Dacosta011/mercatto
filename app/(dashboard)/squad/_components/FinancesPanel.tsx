"use client";

import { useEffect, useState, type ReactNode } from "react";
import { motion, AnimatePresence } from "motion/react";

interface PlayerSalary {
  playerId: string;
  playerName: string;
  price: number;
  ovr: number;
  position: string;
  headshotUrl: string | null;
  salaryPerMatch: number;
  salaryPerSeason: number;
}

interface LedgerEntry {
  id: string;
  fixtureId: string | null;
  matchday: number | null;
  expenseType: "salary" | "yellow_card" | "red_card" | "auto_release";
  playerId: string | null;
  playerName: string | null;
  amount: number;
  isCredit: boolean;
  createdAt: string;
}

interface ExpensesData {
  budget: number;
  budgetReserved: number;
  league: { totalMatchdays: number; currentMatchday: number; status: string | null };
  salaries: { perMatchTotal: number; perSeasonTotal: number; players: PlayerSalary[] };
  fines: { yellowFee: number; redFee: number };
  totals: {
    salaryPaid: number;
    yellowFines: number;
    redFines: number;
    autoReleaseRecovered: number;
    netSpent: number;
  };
  ledger: LedgerEntry[];
}

interface Props {
  code: string;
  token: string;
  onClose: () => void;
}

function fmt(n: number) {
  if (!n) return "$0";
  const abs = Math.abs(n);
  const sign = n < 0 ? "-" : "";
  if (abs >= 1_000_000) return `${sign}$${(abs / 1_000_000).toFixed(1)}M`;
  if (abs >= 1_000) return `${sign}$${(abs / 1_000).toFixed(0)}K`;
  return `${sign}$${abs}`;
}

function timeAgo(iso: string) {
  const diff = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (diff < 60) return "ahora";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  return `${Math.floor(diff / 86400)}d`;
}

const TYPE_META: Record<LedgerEntry["expenseType"], { label: string; color: string; icon: ReactNode }> = {
  salary: {
    label: "Salario",
    color: "#8B5CF6",
    icon: (
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
        <line x1="12" y1="1" x2="12" y2="23" />
        <path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
      </svg>
    ),
  },
  yellow_card: {
    label: "Tarjeta amarilla",
    color: "#F59E0B",
    icon: (
      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
        <rect x="6" y="3" width="12" height="18" rx="1.5" />
      </svg>
    ),
  },
  red_card: {
    label: "Tarjeta roja",
    color: "#EF4444",
    icon: (
      <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor">
        <rect x="6" y="3" width="12" height="18" rx="1.5" />
      </svg>
    ),
  },
  auto_release: {
    label: "Liberación forzosa",
    color: "#22C55E",
    icon: (
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="20 6 9 17 4 12" />
      </svg>
    ),
  },
};

export default function FinancesPanel({ code, token, onClose }: Props) {
  const [data, setData] = useState<ExpensesData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [tab, setTab] = useState<"summary" | "ledger" | "salaries">("summary");

  useEffect(() => {
    let cancelled = false;
    fetch(`/api/tournaments/${code}/expenses`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then((r) => r.json())
      .then((d) => {
        if (cancelled) return;
        if (d.error) setError(d.error);
        else setData(d as ExpensesData);
      })
      .catch(() => !cancelled && setError("No se pudieron cargar las finanzas."))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [code, token]);

  const inDebt = data ? data.budget < 0 : false;
  const matchesPlayed = data ? Math.max(0, data.league.currentMatchday - 1) : 0;
  const matchesRemaining = data ? Math.max(0, data.league.totalMatchdays - matchesPlayed) : 0;

  return (
    <AnimatePresence>
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-6 bg-black/60 backdrop-blur-sm"
        onClick={onClose}
      >
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          exit={{ opacity: 0, y: 24 }}
          transition={{ duration: 0.2 }}
          className="bg-[#131722] rounded-t-2xl sm:rounded-3xl border border-white/10 w-full max-w-2xl shadow-2xl max-h-[92vh] sm:max-h-[88vh] overflow-hidden flex flex-col"
          onClick={(e) => e.stopPropagation()}
        >
          {/* Header */}
          <div className="px-5 pt-5 pb-3 border-b border-white/6 shrink-0">
            <div className="flex items-start justify-between gap-3">
              <div>
                <p className="text-[10px] uppercase tracking-[0.18em] text-[#8B5CF6] font-bold mb-1">
                  Finanzas del club
                </p>
                <h2 className="text-[#F3F4F6] text-xl font-bold leading-tight">
                  Salarios, multas y deudas
                </h2>
              </div>
              <button
                onClick={onClose}
                className="p-2 rounded-xl hover:bg-white/5 text-[#9CA3AF] hover:text-[#F3F4F6] transition-colors cursor-pointer"
                aria-label="Cerrar"
              >
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                  <line x1="18" y1="6" x2="6" y2="18" />
                  <line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              </button>
            </div>
          </div>

          {/* Tabs */}
          <div className="px-5 pt-4 shrink-0">
            <div className="flex gap-1 p-1 bg-[#0D0F14] rounded-xl border border-white/6">
              {[
                { id: "summary" as const, label: "Resumen" },
                { id: "salaries" as const, label: "Salarios" },
                { id: "ledger" as const, label: "Movimientos" },
              ].map((t) => (
                <button
                  key={t.id}
                  onClick={() => setTab(t.id)}
                  className={`flex-1 py-2 px-3 rounded-lg text-sm font-semibold transition-colors cursor-pointer ${
                    tab === t.id
                      ? "bg-[#8B5CF6]/15 text-[#8B5CF6] border border-[#8B5CF6]/25"
                      : "text-[#9CA3AF] hover:text-[#F3F4F6]"
                  }`}
                >
                  {t.label}
                </button>
              ))}
            </div>
          </div>

          {/* Body */}
          <div className="flex-1 min-h-0 overflow-y-auto overscroll-contain p-5">
            {loading && (
              <div className="py-16 text-center text-[#9CA3AF] text-sm">Cargando finanzas…</div>
            )}
            {error && !loading && (
              <div className="py-16 text-center text-[#EF4444] text-sm">{error}</div>
            )}
            {data && !loading && tab === "summary" && (
              <div className="flex flex-col gap-4">
                {/* Budget banner */}
                <div
                  className={`rounded-2xl border p-4 ${
                    inDebt
                      ? "bg-[#EF4444]/10 border-[#EF4444]/30"
                      : "bg-[#22C55E]/8 border-[#22C55E]/20"
                  }`}
                >
                  <p className="text-[10px] uppercase tracking-widest font-semibold text-[#9CA3AF] mb-1">
                    Presupuesto actual
                  </p>
                  <p
                    className={`text-3xl font-black ${
                      inDebt ? "text-[#EF4444]" : "text-[#22C55E]"
                    }`}
                  >
                    {fmt(data.budget)}
                  </p>
                  {inDebt && (
                    <p className="text-[#EF4444] text-xs font-medium mt-2">
                      Estás en deuda. Tras el próximo partido, el sistema venderá fichajes para cubrir el déficit.
                    </p>
                  )}
                  {data.budgetReserved > 0 && (
                    <p className="text-[#9CA3AF] text-xs mt-2">
                      Reservado en ofertas activas: <span className="text-[#F3F4F6] font-semibold">{fmt(data.budgetReserved)}</span>
                    </p>
                  )}
                </div>

                {/* Salary commitments */}
                <div className="grid grid-cols-2 gap-3">
                  <StatCard
                    label="Salario por partido"
                    value={fmt(data.salaries.perMatchTotal)}
                    accent="#8B5CF6"
                  />
                  <StatCard
                    label="Salario por temporada"
                    value={fmt(data.salaries.perSeasonTotal)}
                    accent="#8B5CF6"
                  />
                  <StatCard
                    label="Salarios pagados"
                    value={fmt(data.totals.salaryPaid)}
                    accent="#9CA3AF"
                  />
                  <StatCard
                    label="Multas pagadas"
                    value={fmt(data.totals.yellowFines + data.totals.redFines)}
                    accent="#F59E0B"
                    sub={`${fmt(data.totals.yellowFines)} amar. · ${fmt(data.totals.redFines)} rojas`}
                  />
                </div>

                {/* League progress */}
                {data.league.totalMatchdays > 0 && (
                  <div className="rounded-2xl border border-white/6 bg-[#0D0F14] p-4">
                    <div className="flex items-center justify-between mb-3">
                      <p className="text-[10px] uppercase tracking-widest font-semibold text-[#9CA3AF]">
                        Compromiso restante
                      </p>
                      <span className="text-[#9CA3AF] text-xs">
                        Fecha {data.league.currentMatchday} / {data.league.totalMatchdays}
                      </span>
                    </div>
                    <p className="text-[#F3F4F6] text-base font-bold">
                      {fmt(data.salaries.perMatchTotal * matchesRemaining)}
                    </p>
                    <p className="text-[#9CA3AF] text-xs mt-1">
                      Salarios proyectados durante las {matchesRemaining} fechas restantes.
                    </p>
                  </div>
                )}

                {/* Card fees reference */}
                <div className="rounded-xl border border-white/6 bg-[#0D0F14] px-4 py-3 text-xs text-[#9CA3AF]">
                  <span className="font-semibold text-[#F3F4F6]">Multas oficiales</span>:
                  amarilla {fmt(data.fines.yellowFee)} · roja {fmt(data.fines.redFee)}.
                </div>

                {data.totals.autoReleaseRecovered > 0 && (
                  <div className="rounded-xl border border-[#22C55E]/20 bg-[#22C55E]/8 px-4 py-3 text-xs text-[#22C55E]">
                    Recuperaste {fmt(data.totals.autoReleaseRecovered)} por liberaciones forzosas.
                  </div>
                )}
              </div>
            )}

            {data && !loading && tab === "salaries" && (
              <div className="flex flex-col gap-2">
                {data.salaries.players.length === 0 ? (
                  <p className="py-12 text-center text-[#9CA3AF] text-sm">
                    Aún no tienes plantilla.
                  </p>
                ) : (
                  data.salaries.players.map((p) => <SalaryRow key={p.playerId} player={p} />)
                )}
              </div>
            )}

            {data && !loading && tab === "ledger" && (
              <div className="flex flex-col gap-2">
                {data.ledger.length === 0 ? (
                  <p className="py-12 text-center text-[#9CA3AF] text-sm">
                    Sin movimientos aún. Los salarios y multas aparecerán al finalizar partidos.
                  </p>
                ) : (
                  data.ledger.map((e) => {
                    const meta = TYPE_META[e.expenseType];
                    return (
                      <div
                        key={e.id}
                        className="rounded-xl border border-white/6 bg-[#0D0F14] px-3 py-2.5 flex items-center gap-3"
                      >
                        <div
                          className="w-8 h-8 rounded-lg flex items-center justify-center shrink-0"
                          style={{ background: `${meta.color}1A`, color: meta.color }}
                        >
                          {meta.icon}
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="text-[#F3F4F6] text-xs font-semibold truncate">
                            {meta.label}
                            {e.playerName && (
                              <span className="text-[#9CA3AF] font-normal"> · {e.playerName}</span>
                            )}
                          </p>
                          <p className="text-[#6B7280] text-[10px] mt-0.5">
                            {e.matchday ? `Fecha ${e.matchday} · ` : ""}
                            {timeAgo(e.createdAt)}
                          </p>
                        </div>
                        <p
                          className="text-sm font-bold shrink-0 tabular-nums"
                          style={{ color: e.isCredit ? "#22C55E" : "#EF4444" }}
                        >
                          {e.isCredit ? "+" : "-"}
                          {fmt(e.amount)}
                        </p>
                      </div>
                    );
                  })
                )}
              </div>
            )}
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}

function ovrColor(ovr: number) {
  if (ovr >= 90) return "#8B5CF6";
  if (ovr >= 85) return "#22C55E";
  if (ovr >= 80) return "#F59E0B";
  return "#9CA3AF";
}

function SalaryRow({ player }: { player: PlayerSalary }) {
  const [imgError, setImgError] = useState(false);
  const col = ovrColor(player.ovr);
  const showImg = player.headshotUrl && !imgError;

  return (
    <div className="rounded-xl border border-white/6 bg-[#0D0F14] px-3 py-2.5 flex items-center gap-3">
      <div
        className="w-12 h-12 rounded-xl overflow-hidden shrink-0 bg-[#131722] border flex items-center justify-center"
        style={{ borderColor: `${col}33` }}
      >
        {showImg ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={player.headshotUrl as string}
            alt={player.playerName}
            onError={() => setImgError(true)}
            className="w-full h-full object-contain object-bottom"
          />
        ) : (
          <span className="text-base font-black" style={{ color: col }}>
            {player.playerName.charAt(0)}
          </span>
        )}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5">
          <span
            className="px-1.5 py-0.5 rounded-md text-[10px] font-black tabular-nums"
            style={{ background: `${col}22`, color: col }}
          >
            {player.ovr || "—"}
          </span>
          <span className="px-1.5 py-0.5 rounded-md text-[10px] font-bold bg-white/6 text-[#F3F4F6]">
            {player.position}
          </span>
        </div>
        <p className="text-[#F3F4F6] text-sm font-semibold truncate mt-1">
          {player.playerName}
        </p>
        <p className="text-[#6B7280] text-[10px] mt-0.5">
          Precio {fmt(player.price)}
        </p>
      </div>
      <div className="text-right shrink-0">
        <p className="text-[#8B5CF6] text-sm font-bold tabular-nums">
          {fmt(player.salaryPerMatch)}
          <span className="text-[#9CA3AF] text-[10px] font-normal"> / partido</span>
        </p>
        <p className="text-[#9CA3AF] text-[10px] mt-0.5 tabular-nums">
          {fmt(player.salaryPerSeason)} / temporada
        </p>
      </div>
    </div>
  );
}

function StatCard({
  label,
  value,
  accent,
  sub,
}: {
  label: string;
  value: string;
  accent: string;
  sub?: string;
}) {
  return (
    <div className="rounded-2xl border border-white/6 bg-[#0D0F14] p-3">
      <p className="text-[10px] uppercase tracking-widest font-semibold text-[#9CA3AF] mb-1.5">
        {label}
      </p>
      <p className="text-lg font-bold tabular-nums" style={{ color: accent }}>
        {value}
      </p>
      {sub && (
        <p className="text-[#6B7280] text-[10px] mt-1.5">{sub}</p>
      )}
    </div>
  );
}
