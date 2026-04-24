"use client";
import { useEffect, useState } from "react";
import { getLastTournamentCode, getMemberId } from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";
import SlotMachine from "@/app/Components/SlotMachine";
import type { SlotPrize } from "@/app/api/slot-machine/prizes/route";

interface PoolRange { label: string; count: number; players: SlotPrize[]; }

export default function TragaperrasPage() {
  const [prizes, setPrizes] = useState<SlotPrize[]>([]);
  const [poolDate, setPoolDate] = useState("");
  const [poolByRange, setPoolByRange] = useState<PoolRange[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [budget, setBudget] = useState(0);
  const [code, setCode] = useState("");

  useEffect(() => {
    const tournamentCode = getLastTournamentCode();
    if (!tournamentCode) { setError("No hay torneo activo."); setLoading(false); return; }
    setCode(tournamentCode);

    // Check localStorage cache for today's pool
    const today = new Date().toISOString().slice(0, 10);
    const cacheKey = `mercatto:pool:${tournamentCode}:${today}`;
    const cached = localStorage.getItem(cacheKey);

    if (cached) {
      try {
        const data = JSON.parse(cached);
        setPrizes(data.prizes); setPoolDate(data.poolDate); setPoolByRange(data.poolByRange ?? []);
        setLoading(false);
      } catch { localStorage.removeItem(cacheKey); }
    }

    if (!cached) {
      fetch(`/api/slot-machine/prizes?tournamentCode=${tournamentCode}`)
        .then(r => r.json())
        .then(data => {
          if (data.prizes) {
            setPrizes(data.prizes);
            setPoolDate(data.poolDate ?? today);
            setPoolByRange(data.poolByRange ?? []);
            localStorage.setItem(cacheKey, JSON.stringify(data));
          } else {
            setError(data.error ?? "Error cargando premios");
          }
        })
        .catch(() => setError("Error de red"))
        .finally(() => setLoading(false));
    }

    // Fetch budget
    const memberId = getMemberId(tournamentCode);
    if (memberId) {
      getBrowserClient().from("members").select("budget").eq("id", memberId).single()
        .then(({ data }) => { if (data?.budget) setBudget(data.budget as number); });
    }
  }, []);

  return (
    <main className="flex-1 overflow-y-auto p-4 md:p-6" style={{ background: "#0D0F14", minHeight: "100vh" }}>
      <div className="max-w-5xl mx-auto">
        <div className="mb-6 text-center">
          <h1 className="text-3xl font-black text-[#F3F4F6] tracking-tight mb-1">Tragaperras 🎰</h1>
          <p className="text-[#9CA3AF] text-sm">Consigue 3 iguales para ganar • Pool de 100 jugadores diaria</p>
        </div>

        {loading && (
          <div className="flex flex-col items-center gap-4 py-24">
            <div className="w-10 h-10 rounded-full border-2 border-[#8B5CF6] border-t-transparent animate-spin" />
            <p className="text-[#9CA3AF] text-sm">Generando pool del día...</p>
          </div>
        )}
        {error && <div className="text-center py-24"><p className="text-[#EF4444] font-semibold">{error}</p></div>}
        {!loading && !error && (
          <SlotMachine prizes={prizes} budget={budget} tournamentCode={code} poolDate={poolDate} poolByRange={poolByRange} />
        )}
      </div>
    </main>
  );
}
