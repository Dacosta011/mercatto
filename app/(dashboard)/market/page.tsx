"use client";

import { useState } from "react";
import PlayerCard from "../../Components/PlayerCard";
import Button from "../../Components/Button";

const MARKET_PLAYERS = [
  { id: 1, name: "Erling Haaland", position: "DC", club: "Man. City", ovr: 93, price: "€200M", clause: "€400M" },
  { id: 2, name: "Rodri", position: "MC", club: "Man. City", ovr: 91, price: "€120M", clause: "€240M" },
  { id: 3, name: "Bukayo Saka", position: "ED", club: "Arsenal", ovr: 89, price: "€130M", clause: "€260M" },
  { id: 4, name: "Pedri", position: "MC", club: "Barcelona", ovr: 88, price: "€100M", clause: "€200M" },
  { id: 5, name: "Gavi", position: "MC", club: "Barcelona", ovr: 87, price: "€90M", clause: "€180M" },
  { id: 6, name: "Lamine Yamal", position: "ED", club: "Barcelona", ovr: 86, price: "€95M", clause: "€190M" },
  { id: 7, name: "Leroy Sané", position: "ED", club: "Bayern", ovr: 85, price: "€50M", clause: "€100M" },
  { id: 8, name: "Marcus Rashford", position: "EI", club: "Man. Utd", ovr: 83, price: "€45M", clause: "€90M" },
  { id: 9, name: "Florian Wirtz", position: "MC", club: "Leverkusen", ovr: 88, price: "€120M", clause: "€240M" },
  { id: 10, name: "Julián Álvarez", position: "DC", club: "Atlético", ovr: 85, price: "€80M", clause: "€160M" },
  { id: 11, name: "Rúben Dias", position: "CB", club: "Man. City", ovr: 88, price: "€75M", clause: "€150M" },
  { id: 12, name: "Declan Rice", position: "MC", club: "Arsenal", ovr: 87, price: "€85M", clause: "€170M" },
];

const POSITIONS = ["Todos", "DC", "MC", "ED", "EI", "CB", "POR"];
const SORT_OPTIONS = ["OVR", "Precio", "Cláusula"];

export default function MarketPage() {
  const [activePosition, setActivePosition] = useState("Todos");
  const [activeSort, setActiveSort] = useState("OVR");
  const [search, setSearch] = useState("");

  const filtered = MARKET_PLAYERS.filter((p) => {
    const matchPos = activePosition === "Todos" || p.position === activePosition;
    const matchSearch =
      !search ||
      p.name.toLowerCase().includes(search.toLowerCase()) ||
      p.club.toLowerCase().includes(search.toLowerCase());
    return matchPos && matchSearch;
  });

  return (
    <div className="p-8 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <p className="text-[#9CA3AF] text-xs uppercase tracking-widest font-medium mb-1">
            Transfer Market
          </p>
          <h1 className="text-[#F3F4F6] text-2xl font-bold tracking-tight">
            Mercado
          </h1>
          <p className="text-[#9CA3AF] text-sm mt-1">
            {MARKET_PLAYERS.length} jugadores disponibles
          </p>
        </div>

        <div className="flex items-center gap-3">
          <Button variant="secondary" size="sm">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polygon points="22 3 2 3 10 12.46 10 19 14 21 14 12.46 22 3" />
            </svg>
            Filtros avanzados
          </Button>
          <Button variant="primary" size="sm">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="12" y1="5" x2="12" y2="19" />
              <line x1="5" y1="12" x2="19" y2="12" />
            </svg>
            Listar jugador
          </Button>
        </div>
      </div>

      {/* Market stats bar */}
      <div className="grid grid-cols-4 gap-4 mb-8">
        {[
          { label: "Volumen 24h", value: "€1.2B", change: "+8.4%" },
          { label: "Operaciones", value: "34", change: "+3" },
          { label: "Precio medio", value: "€97M", change: "-2.1%" },
          { label: "Tu presupuesto", value: "€150M", change: null },
        ].map((stat) => (
          <div
            key={stat.label}
            className="bg-[#131722] rounded-2xl p-4 border border-white/[0.04] hover:bg-[#1A1F2E] transition-colors duration-200"
          >
            <p className="text-[#9CA3AF] text-[11px] uppercase tracking-wider font-medium mb-2">
              {stat.label}
            </p>
            <div className="flex items-end gap-2">
              <p className="text-[#F3F4F6] text-xl font-semibold leading-none">
                {stat.value}
              </p>
              {stat.change && (
                <span
                  className={`text-xs font-medium mb-0.5 ${
                    stat.change.startsWith("+")
                      ? "text-[#22C55E]"
                      : "text-[#EF4444]"
                  }`}
                >
                  {stat.change}
                </span>
              )}
            </div>
          </div>
        ))}
      </div>

      {/* Filters and search */}
      <div className="flex items-center gap-4 mb-6 flex-wrap">
        {/* Search */}
        <div className="relative flex-1 min-w-[200px] max-w-xs">
          <svg
            width="14"
            height="14"
            viewBox="0 0 24 24"
            fill="none"
            stroke="#9CA3AF"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="absolute left-3.5 top-1/2 -translate-y-1/2"
          >
            <circle cx="11" cy="11" r="8" />
            <line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <input
            type="text"
            placeholder="Buscar jugador o club..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full bg-[#131722] border border-white/[0.06] rounded-xl pl-10 pr-4 py-2.5 text-sm text-[#F3F4F6] placeholder-[#9CA3AF]/50 focus:outline-none focus:border-[#8B5CF6]/40 transition-colors duration-200"
          />
        </div>

        {/* Position filters */}
        <div className="flex items-center gap-1 bg-[#131722] rounded-xl p-1 border border-white/[0.04]">
          {POSITIONS.map((pos) => (
            <button
              key={pos}
              onClick={() => setActivePosition(pos)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all duration-150 cursor-pointer
                ${
                  activePosition === pos
                    ? "bg-[#8B5CF6] text-white shadow-lg shadow-[#8B5CF6]/20"
                    : "text-[#9CA3AF] hover:text-[#F3F4F6] hover:bg-[#1A1F2E]"
                }`}
            >
              {pos}
            </button>
          ))}
        </div>

        {/* Sort */}
        <div className="flex items-center gap-2 ml-auto">
          <span className="text-[#9CA3AF] text-xs">Ordenar:</span>
          {SORT_OPTIONS.map((opt) => (
            <button
              key={opt}
              onClick={() => setActiveSort(opt)}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-all duration-150 cursor-pointer border
                ${
                  activeSort === opt
                    ? "border-[#8B5CF6]/40 bg-[#8B5CF6]/10 text-[#8B5CF6]"
                    : "border-transparent text-[#9CA3AF] hover:text-[#F3F4F6]"
                }`}
            >
              {opt}
            </button>
          ))}
        </div>
      </div>

      {/* Players grid */}
      {filtered.length > 0 ? (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
          {filtered.map((player) => (
            <PlayerCard
              key={player.id}
              name={player.name}
              position={player.position}
              club={player.club}
              ovr={player.ovr}
              price={player.price}
              clause={player.clause}
              action="buy"
            />
          ))}
        </div>
      ) : (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <div className="w-16 h-16 rounded-2xl bg-[#131722] border border-white/[0.04] flex items-center justify-center mb-4">
            <svg
              width="24"
              height="24"
              viewBox="0 0 24 24"
              fill="none"
              stroke="#9CA3AF"
              strokeWidth="1.5"
              strokeLinecap="round"
              strokeLinejoin="round"
            >
              <circle cx="11" cy="11" r="8" />
              <line x1="21" y1="21" x2="16.65" y2="16.65" />
            </svg>
          </div>
          <p className="text-[#F3F4F6] text-sm font-medium">
            No se encontraron jugadores
          </p>
          <p className="text-[#9CA3AF] text-xs mt-1">
            Prueba ajustando los filtros
          </p>
        </div>
      )}
    </div>
  );
}
