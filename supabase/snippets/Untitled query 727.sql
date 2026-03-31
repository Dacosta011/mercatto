-- ============================================================================
-- Mercatto — Player price & clause update based on OVR
-- Run once to populate all existing players with realistic market values.
-- ============================================================================

-- 91+ : Elite stars
UPDATE players SET
  price  = 120000000 + (ovr - 91) * 20000000 + floor(random() * 15000000),
  clause = 200000000 + (ovr - 91) * 25000000 + floor(random() * 20000000)
WHERE ovr >= 91;

-- 88-90 : World class
UPDATE players SET
  price  = 70000000 + (ovr - 88) * 15000000 + floor(random() * 10000000),
  clause = 120000000 + (ovr - 88) * 15000000 + floor(random() * 15000000)
WHERE ovr BETWEEN 88 AND 90;

-- 85-87 : Top tier
UPDATE players SET
  price  = 40000000 + (ovr - 85) * 10000000 + floor(random() * 8000000),
  clause = 70000000 + (ovr - 85) * 12000000 + floor(random() * 10000000)
WHERE ovr BETWEEN 85 AND 87;

-- 82-84 : Quality starters
UPDATE players SET
  price  = 20000000 + (ovr - 82) * 6000000 + floor(random() * 5000000),
  clause = 35000000 + (ovr - 82) * 8000000 + floor(random() * 7000000)
WHERE ovr BETWEEN 82 AND 84;

-- 79-81 : Solid squad players
UPDATE players SET
  price  = 10000000 + (ovr - 79) * 3000000 + floor(random() * 3000000),
  clause = 18000000 + (ovr - 79) * 4000000 + floor(random() * 4000000)
WHERE ovr BETWEEN 79 AND 81;

-- 76-78 : Rotation / depth
UPDATE players SET
  price  = 5000000 + (ovr - 76) * 1500000 + floor(random() * 2000000),
  clause = 9000000 + (ovr - 76) * 2500000 + floor(random() * 3000000)
WHERE ovr BETWEEN 76 AND 78;

-- 73-75 : Bench / youth
UPDATE players SET
  price  = 2000000 + (ovr - 73) * 800000 + floor(random() * 1000000),
  clause = 4000000 + (ovr - 73) * 1200000 + floor(random() * 1500000)
WHERE ovr BETWEEN 73 AND 75;

-- <73 : Reserves
UPDATE players SET
  price  = 500000 + greatest(ovr - 65, 0) * 150000 + floor(random() * 500000),
  clause = 1500000 + greatest(ovr - 65, 0) * 250000 + floor(random() * 800000)
WHERE ovr < 73;

-- Round everything to nearest 500K for cleaner numbers
UPDATE players SET
  price  = round(price  / 500000.0) * 500000,
  clause = round(clause / 500000.0) * 500000;

-- Sanity: clause must always be >= price * 1.4
UPDATE players SET clause = round((price * 1.5) / 500000.0) * 500000
WHERE clause < price * 1.4;
