-- Ejecutar despues de reset-production.sql con rol postgres.
-- Activa el cierre de mercados, subastas, votaciones y plazos cada minuto.
BEGIN;
DO $$ BEGIN
 IF to_regprocedure('public.game_expire_markets(integer)') IS NULL THEN
  RAISE EXCEPTION 'Primero aplicar las migraciones del modelo de clubes';
 END IF;
END $$;
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('mercatto-game-worker','* * * * *','SELECT public.game_expire_markets(100);');
COMMIT;
SELECT jobname,schedule,active FROM cron.job WHERE jobname='mercatto-game-worker';
