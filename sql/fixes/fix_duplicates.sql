-- ─── 1. Identificar el player canónico por grupo de duplicados ────────────────
CREATE TEMP TABLE player_mapping AS
SELECT
  id AS old_id,
  FIRST_VALUE(id) OVER (
    PARTITION BY name, ovr, COALESCE(position, '__NULL__')
    ORDER BY created_at ASC NULLS LAST
  ) AS keep_id
FROM players;

-- ─── 2. Para team_players: insertar fila con keep_id si no existe aún ─────────
INSERT INTO team_players (team_id, player_id)
SELECT tp.team_id, m.keep_id
FROM team_players tp
JOIN player_mapping m ON tp.player_id = m.old_id AND m.old_id <> m.keep_id
ON CONFLICT DO NOTHING;

-- ─── 3. Borrar las referencias a los player ids duplicados ────────────────────
DELETE FROM team_players
WHERE player_id IN (
  SELECT old_id FROM player_mapping WHERE old_id <> keep_id
);

-- ─── 4. Borrar los players duplicados ────────────────────────────────────────
DELETE FROM players
WHERE id IN (
  SELECT old_id FROM player_mapping WHERE old_id <> keep_id
);

DROP TABLE player_mapping;

-- ─── 5. Agregar unique constraint para evitar duplicados en el futuro ─────────
ALTER TABLE players
  ADD CONSTRAINT players_name_ovr_position_unique
  UNIQUE (name, ovr, position);
