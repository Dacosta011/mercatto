import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@/lib/supabase";

export interface SlotPrize {
  id: string;
  name: string;
  ovr: number;
  position: string;
  headshotUrl: string | null;
  type: "player" | "icon" | "free_spins";
  ovrRange?: string;
}

// ── Daily pool config ────────────────────────────────────────────────────────
const POOL_RANGES = [
  { label: "70–74",  min: 70, max: 74, count: 25 },
  { label: "75–79",  min: 75, max: 79, count: 22 },
  { label: "80–83",  min: 80, max: 83, count: 20 },
  { label: "84–86",  min: 84, max: 86, count: 16 },
  { label: "87–89",  min: 87, max: 89, count: 10 },
  { label: "90+",    min: 90, max: 99, count: 5  },
  { label: "Leyendas", min: 0, max: 99, count: 2, iconsOnly: true },
] as const;

// ── Seeded random (deterministic per date + tournament) ──────────────────────
function makeRng(seed: string) {
  let h = 0;
  for (let i = 0; i < seed.length; i++) {
    h = Math.imul(31, h) + seed.charCodeAt(i) | 0;
  }
  let s = h >>> 0;
  return () => {
    s ^= s << 13; s ^= s >> 17; s ^= s << 5;
    return (s >>> 0) / 0xffffffff;
  };
}

function seededShuffle<T>(arr: T[], rng: () => number): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function todayStr() {
  return new Date().toISOString().slice(0, 10); // YYYY-MM-DD UTC
}

export async function GET(req: NextRequest) {
  const code = req.nextUrl.searchParams.get("tournamentCode");
  if (!code) return NextResponse.json({ error: "tournamentCode requerido" }, { status: 400 });

  const supabase = createServerClient();

  const { data: tournament } = await supabase
    .from("tournaments")
    .select("id")
    .eq("code", code.toUpperCase())
    .single();
  if (!tournament) return NextResponse.json({ error: "Torneo no encontrado" }, { status: 404 });

  const tournamentId = tournament.id as string;
  const dateKey = todayStr();
  const rng = makeRng(`${tournamentId}-${dateKey}`);

  // ── Find eligible players ────────────────────────────────────────────────
  // Assigned team IDs for this tournament
  const { data: assignments } = await supabase
    .from("assignments")
    .select("team_id")
    .eq("tournament_id", tournamentId);
  const assignedTeamIds = (assignments ?? []).map((a: any) => a.team_id as string);

  // Players in UNASSIGNED teams (teams not in any assignment for this tournament)
  // + players with no team at all (not in team_players)
  // We'll get all players, then filter:

  // All players in team_players
  const { data: allTeamPlayers } = await supabase
    .from("team_players")
    .select("player_id, team_id");

  const playerInAssignedTeam = new Set(
    (allTeamPlayers ?? [])
      .filter((tp: any) => assignedTeamIds.includes(tp.team_id))
      .map((tp: any) => tp.player_id as string)
  );

  // Players from unassigned teams (in some team but not an assigned one)
  const freeFromTeams = new Set(
    (allTeamPlayers ?? [])
      .filter((tp: any) => !assignedTeamIds.includes(tp.team_id))
      .map((tp: any) => tp.player_id as string)
  );

  // All squad players (regular, non-icon)
  const { data: allPlayers } = await supabase
    .from("players")
    .select("id, name, ovr, position, headshot_url, is_icon")
    .eq("is_icon", false);

  const eligibleSquad = (allPlayers ?? []).filter((p: any) =>
    !playerInAssignedTeam.has(p.id)  // not in an assigned team's squad
  );

  // Icons not yet used in icon_auctions for this tournament's sessions
  const { data: usedIconAuctions } = await supabase
    .from("icon_auctions")
    .select("selected_icon_id, market_sessions(tournament_id)")
    .not("selected_icon_id", "is", null);

  const usedIconIds = new Set(
    (usedIconAuctions ?? [])
      .filter((ia: any) => ia.market_sessions?.tournament_id === tournamentId)
      .map((ia: any) => ia.selected_icon_id as string)
  );

  const { data: allIcons } = await supabase
    .from("players")
    .select("id, name, ovr, position, headshot_url")
    .eq("is_icon", true);

  const eligibleIcons = (allIcons ?? []).filter((p: any) => !usedIconIds.has(p.id));

  // ── Build today's pool by range ──────────────────────────────────────────
  const pool: SlotPrize[] = [];

  for (const range of POOL_RANGES) {
    if ((range as any).iconsOnly) {
      const shuffled = seededShuffle(eligibleIcons, rng);
      shuffled.slice(0, range.count).forEach((p: any) => {
        pool.push({ id: p.id, name: p.name, ovr: p.ovr, position: p.position, headshotUrl: p.headshot_url ?? null, type: "icon", ovrRange: range.label });
      });
    } else {
      const inRange = eligibleSquad.filter((p: any) => p.ovr >= range.min && p.ovr <= range.max);
      const shuffled = seededShuffle(inRange, rng);
      shuffled.slice(0, range.count).forEach((p: any) => {
        pool.push({ id: p.id, name: p.name, ovr: p.ovr, position: p.position, headshotUrl: p.headshot_url ?? null, type: "player", ovrRange: range.label });
      });
    }
  }

  // Shuffle the final pool (also seeded)
  const finalPool = seededShuffle(pool, rng);

  return NextResponse.json({
    prizes: finalPool,
    poolDate: dateKey,
    poolByRange: POOL_RANGES.map(r => ({
      label: r.label,
      count: pool.filter(p => p.ovrRange === r.label).length,
      players: pool.filter(p => p.ovrRange === r.label),
    })),
  });
}
