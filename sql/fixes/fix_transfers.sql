-- ============================================================================
-- Fix transfers incorrectos del torneo 5bd13f46-5ac5-4e04-a425-4ba20d7c4fe7
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════════════
-- PASO 1: PREVIEW — Ver transfers malos
-- ═══════════════════════════════════════════════════════════════════════════════

SELECT
  mt.id AS transfer_id,
  mt.created_at,
  p.name AS player_name,
  mt.amount,
  mb.display_name AS current_buyer,
  ms.display_name AS current_seller
FROM market_transfers mt
JOIN market_sessions mse ON mse.id = mt.session_id
JOIN players p ON p.id = mt.player_id
JOIN members mb ON mb.id = mt.buyer_id
JOIN members ms ON ms.id = mt.seller_id
JOIN assignments a_buyer ON a_buyer.member_id = mt.buyer_id
JOIN team_players tp ON tp.team_id = a_buyer.team_id AND tp.player_id = mt.player_id
WHERE mse.tournament_id = '5bd13f46-5ac5-4e04-a425-4ba20d7c4fe7'
ORDER BY mt.created_at DESC;


-- ═══════════════════════════════════════════════════════════════════════════════
-- PASO 2: FIX (seleccionar desde BEGIN hasta COMMIT y ejecutar)
-- ═══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- Guardar los IDs de transfers malos en una tabla temporal
CREATE TEMP TABLE bad_transfers AS
SELECT mt.id, mt.buyer_id, mt.seller_id, mt.amount, mt.player_id, a.team_id AS correct_seller_team
FROM market_transfers mt
JOIN market_sessions mse ON mse.id = mt.session_id
JOIN assignments a ON a.member_id = mt.buyer_id
JOIN team_players tp ON tp.team_id = a.team_id AND tp.player_id = mt.player_id
WHERE mse.tournament_id = '5bd13f46-5ac5-4e04-a425-4ba20d7c4fe7';

-- 2a. Corregir budget del "buyer" falso (+2*amount, -1 purchase)
UPDATE members m
SET
  budget = m.budget + (2 * bt.amount),
  market_purchases = GREATEST(0, m.market_purchases - 1)
FROM bad_transfers bt
WHERE m.id = bt.buyer_id;

-- 2b. Corregir budget del "seller" falso (-2*amount, +1 purchase)
UPDATE members m
SET
  budget = m.budget - (2 * bt.amount),
  market_purchases = m.market_purchases + 1
FROM bad_transfers bt
WHERE m.id = bt.seller_id;

-- 2c. Swap buyer/seller y corregir seller_team_id
UPDATE market_transfers mt2
SET
  buyer_id = bt.seller_id,
  seller_id = bt.buyer_id,
  seller_team_id = bt.correct_seller_team
FROM bad_transfers bt
WHERE mt2.id = bt.id;

DROP TABLE bad_transfers;

COMMIT;


-- ═══════════════════════════════════════════════════════════════════════════════
-- PASO 3: VERIFICACIÓN — Debe devolver 0 filas
-- ═══════════════════════════════════════════════════════════════════════════════

SELECT mt.id, p.name, mb.display_name AS buyer, ms.display_name AS seller
FROM market_transfers mt
JOIN market_sessions mse ON mse.id = mt.session_id
JOIN players p ON p.id = mt.player_id
JOIN members mb ON mb.id = mt.buyer_id
JOIN members ms ON ms.id = mt.seller_id
JOIN assignments a_buyer ON a_buyer.member_id = mt.buyer_id
JOIN team_players tp ON tp.team_id = a_buyer.team_id AND tp.player_id = mt.player_id
WHERE mse.tournament_id = '5bd13f46-5ac5-4e04-a425-4ba20d7c4fe7';
