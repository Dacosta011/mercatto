-- ─────────────────────────────────────────────────────────────────────────────
-- Actualiza price y clause de todos los jugadores según su OVR.
--
-- Escala de precios:
--   90–93 → 30M   clause = precio × 1.7
--   87–89 → 24M
--   84–86 → 18M
--   81–83 → 12M
--   78–80 →  8M
--   75–77 →  5M
--   ≤ 74  →  3M
--
-- Los valores se almacenan en unidades base (1M = 1_000_000).
-- ─────────────────────────────────────────────────────────────────────────────

update players
set
  price = case
    when ovr between 90 and 93 then 30000000
    when ovr between 87 and 89 then 24000000
    when ovr between 84 and 86 then 18000000
    when ovr between 81 and 83 then 12000000
    when ovr between 78 and 80 then  8000000
    when ovr between 75 and 77 then  5000000
    else                              3000000
  end,
  clause = case
    when ovr between 90 and 93 then round(30000000 * 1.7)
    when ovr between 87 and 89 then round(24000000 * 1.7)
    when ovr between 84 and 86 then round(18000000 * 1.7)
    when ovr between 81 and 83 then round(12000000 * 1.7)
    when ovr between 78 and 80 then round( 8000000 * 1.7)
    when ovr between 75 and 77 then round( 5000000 * 1.7)
    else                             round( 3000000 * 1.7)
  end;

-- Verificación rápida (ejecuta por separado si quieres revisar antes):
-- select ovr, count(*), min(price)/1e6 as price_m, min(clause)/1e6 as clause_m
-- from players
-- group by ovr order by ovr desc;
