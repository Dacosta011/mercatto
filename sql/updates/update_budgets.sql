-- ─────────────────────────────────────────────────────────────────────────────
-- Calcula y actualiza el presupuesto (budget) de cada equipo de forma
-- inversamente proporcional a su OVR medio.
--
-- Fórmula:
--   avg_ovr  = media OVR de los jugadores del equipo
--   budget   = 100M + (OVR_REF - avg_ovr) × STEP_M
--   budget   = CLAMP(budget, MIN_BUDGET, MAX_BUDGET)
--   budget   = redondeado al múltiplo de 5M más cercano (limpieza visual)
--
-- Parámetros ajustables:
--   OVR_REF    = 88   → OVR de referencia del equipo más fuerte
--   STEP_M     = 20M  → presupuesto extra por cada punto de OVR por debajo
--   MIN_BUDGET = 100M → presupuesto mínimo (equipo más fuerte)
--   MAX_BUDGET = 400M → presupuesto máximo (equipo más débil)
-- ─────────────────────────────────────────────────────────────────────────────

-- Paso 1: Ver la distribución antes de aplicar (opcional, no modifica nada)
select
  t.name                                          as team,
  round(avg(p.ovr), 1)                            as avg_ovr,
  round(
    greatest(
      100000000,
      least(
        400000000,
        round(
          (100000000 + (88.0 - avg(p.ovr)) * 20000000) / 5000000.0
        ) * 5000000
      )
    ) / 1000000.0
  , 0) || 'M'                                     as budget_calculado
from teams t
join team_players tp on tp.team_id = t.id
join players      p  on p.id = tp.player_id
group by t.id, t.name
order by avg(p.ovr) desc;


-- Paso 2: Aplicar el presupuesto calculado
update teams t
set budget = sub.budget
from (
  select
    t2.id,
    greatest(
      100000000,            -- mínimo 100M
      least(
        400000000,          -- máximo 400M
        -- redondear al múltiplo de 5M más cercano
        round(
          (100000000 + (88.0 - avg(p.ovr)) * 20000000) / 5000000.0
        ) * 5000000
      )
    )::bigint as budget
  from teams t2
  join team_players tp on tp.team_id = t2.id
  join players      p  on p.id = tp.player_id
  group by t2.id
) sub
where t.id = sub.id;


-- Verificación final
select
  name,
  budget / 1000000 || 'M' as budget
from teams
order by budget asc;
