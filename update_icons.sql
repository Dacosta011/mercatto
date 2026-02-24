-- ============================================================================
-- Mercatto — Reemplazar íconos existentes
-- Corre este script si ya ejecutaste migration_icon_auction.sql antes.
-- ============================================================================

-- 1. Eliminar íconos anteriores (que no estén vinculados a ninguna subasta ganada)
DELETE FROM players
WHERE is_icon = true
  AND id NOT IN (
    SELECT winner_id FROM icon_auctions WHERE winner_id IS NOT NULL
  )
  AND id NOT IN (
    SELECT player_id FROM team_players
    WHERE player_id IN (SELECT id FROM players WHERE is_icon = true)
  );

-- 2. Insertar los nuevos íconos
INSERT INTO players (name, ovr, position, country_name, is_icon, price, clause) VALUES
  ('Ronaldo Nazário',       94, 'DC',  'Brasil',     true, 0, 0),
  ('Carles Puyol',          89, 'DFC', 'España',     true, 0, 0),
  ('Andrés Iniesta',        92, 'MCO', 'España',     true, 0, 0),
  ('Iván Córdoba',          87, 'DFC', 'Colombia',   true, 0, 0),
  ('Thierry Henry',         91, 'EI',  'Francia',    true, 0, 0),
  ('Andrea Pirlo',          90, 'MCD', 'Italia',     true, 0, 0),
  ('Xabi Alonso',           87, 'MC',  'España',     true, 0, 0),
  ('Steven Gerrard',        88, 'MC',  'Inglaterra', true, 0, 0),
  ('Zlatan Ibrahimović',    91, 'DC',  'Suecia',     true, 0, 0),
  ('Lilian Thuram',         88, 'DFC', 'Francia',    true, 0, 0),
  ('Agáchate y conócelo',   89, 'MC',  'Colombia',   true, 0, 0),
  ('Samuel Eto''o',         89, 'DC',  'Camerún',    true, 0, 0),
  ('Patrick Vieira',        88, 'MC',  'Francia',    true, 0, 0)
ON CONFLICT (name, ovr, position) DO NOTHING;
