"use client";
import { useEffect, useState, useCallback } from "react";
import { getLastTournamentCode, getMemberToken, getMemberId, getDisplayName } from "@/lib/tokenStorage";
import { getBrowserClient } from "@/lib/supabase-browser";
import SlotMachine from "@/app/Components/SlotMachine";
import type { RealtimeChannel } from "@supabase/supabase-js";

export interface PoolSlot {
  id: string;
  player_id: string;
  ovr: number;
  is_premium: boolean;
  status: "available" | "claimed" | "empty";
  claimed_by_name: string | null;
  claimed_at: string | null;
  players: {
    id: string; name: string; ovr: number; position: string;
    headshot_url: string | null; price: number | null; clause: number | null; is_icon: boolean;
  } | null;
}

export default function SlotsPage() {
  const [pool, setPool] = useState<PoolSlot[]>([]);
  const [poolDate, setPoolDate] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [budget, setBudget] = useState(0);
  const [code, setCode] = useState("");
  const [memberToken, setMemberToken] = useState("");
  const [freeSpins, setFreeSpins] = useState(0);

  const fetchPool = useCallback(async (tournamentCode: string, token: string) => {
    const res = await fetch(`/api/tournaments/${tournamentCode}/slot-machine/pool`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    const data = await res.json();
    if (data.pool) { setPool(data.pool); setPoolDate(data.poolDate ?? ""); }
    setLoading(false);
  }, []);

  useEffect(() => {
    const tournamentCode = getLastTournamentCode();
    if (!tournamentCode) { setError("No hay torneo activo."); setLoading(false); return; }
    setCode(tournamentCode);

    const token = getMemberToken(tournamentCode) ?? "";
    setMemberToken(token);

    fetchPool(tournamentCode, token);

    // Budget
    const memberId = getMemberId(tournamentCode);
    if (memberId) {
      getBrowserClient().from("members").select("budget").eq("id", memberId).single()
        .then(({ data }) => { if (data?.budget) setBudget(data.budget as number); });
    }

    // Free spins from localStorage
    const stored = localStorage.getItem(`mercatto:slots:free-spins:${tournamentCode}`);
    if (stored) setFreeSpins(parseInt(stored, 10));

    // Realtime pool updates
    let channel: RealtimeChannel;
    getBrowserClient()
      .channel(`slot-pool-${tournamentCode}`)
      .on("postgres_changes", {
        event: "*",
        schema: "public",
        table: "slot_machine_pool",
        filter: `pool_date=eq.${new Date().toISOString().slice(0, 10)}`,
      }, () => {
        fetchPool(tournamentCode, token);
      })
      .subscribe((status) => {
        if (status === "SUBSCRIBED") console.log("[Slots] Realtime connected");
      });

    return () => { getBrowserClient().removeChannel(getBrowserClient().channel(`slot-pool-${tournamentCode}`)); };
  }, [fetchPool]);

  const availablePrizes = pool
    .filter(s => s.status === "available" && s.players)
    .map(s => ({
      id: s.players!.id,
      name: s.players!.name,
      ovr: s.players!.ovr,
      position: s.players!.position,
      headshotUrl: s.players!.headshot_url,
      salary: s.players!.price ?? s.players!.clause ?? 0,
      type: (s.players!.is_icon ? "icon" : "player") as "icon" | "player",
    }));

  return (
    <main className="flex-1 overflow-y-auto p-4 md:p-6" style={{ background: "#0D0F14", minHeight: "100vh" }}>
      <div className="max-w-5xl mx-auto">
        <div className="mb-6 text-center">
          <h1 className="text-3xl font-black text-[#F3F4F6] tracking-tight mb-1">Slots 🎰</h1>
          <p className="text-[#9CA3AF] text-sm">Consigue 3 iguales para ganar • Pool diaria decidida por el servidor</p>
        </div>

        {loading && (
          <div className="flex flex-col items-center gap-4 py-24">
            <div className="w-10 h-10 rounded-full border-2 border-[#8B5CF6] border-t-transparent animate-spin" />
            <p className="text-[#9CA3AF] text-sm">Generando pool del día...</p>
          </div>
        )}
        {error && <div className="text-center py-24"><p className="text-[#EF4444] font-semibold">{error}</p></div>}
        {!loading && !error && (
          <SlotMachine
            prizes={availablePrizes}
            budget={budget}
            tournamentCode={code}
            memberToken={memberToken}
            poolDate={poolDate}
            pool={pool}
          />
        )}
      </div>
    </main>
  );
}
