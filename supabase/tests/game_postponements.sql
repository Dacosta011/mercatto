BEGIN;
-- CATALOG_FIXTURES
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.reject_it(command text,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN BEGIN EXECUTE command; EXCEPTION WHEN SQLSTATE 'GM001' OR SQLSTATE '28000' THEN RETURN; END; RAISE EXCEPTION 'Expected rejection: %',label; END $$;
SELECT public.game_create_competition(gen_random_uuid(),'Complete test','North','b9000000-0000-0000-0000-000000000001','b9000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],
 ARRAY['f2000000-0000-0000-0000-000000000005','f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002']::uuid[]) AS created \gset
SELECT :'created'::jsonb->>'id' AS tid, :'created'::jsonb->>'code' AS code \gset
SELECT id AS north FROM game.clubs WHERE tournament_id=:'tid' AND name='Prueba Norte' \gset
SELECT id AS south FROM game.clubs WHERE tournament_id=:'tid' AND name='Prueba Sur' \gset
SELECT public.game_join_tournament(:'code','South','b9000000-0000-0000-0000-000000000003',gen_random_uuid());
SELECT public.game_choose_club(:'code','b9000000-0000-0000-0000-000000000002',:'north',gen_random_uuid());
SELECT public.game_choose_club(:'code','b9000000-0000-0000-0000-000000000003',:'south',gen_random_uuid());
SET LOCAL ROLE service_role;
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'league_start','{"legs":2}');
SELECT id AS fixture FROM game.fixtures WHERE tournament_id=:'tid' AND round=1 \gset
SELECT public.game_join_tournament(:'code','Observer','b9000000-0000-0000-0000-000000000004',gen_random_uuid());
SELECT pg_temp.reject_it(format('SELECT public.game_fixture_schedule(%L,%L,gen_random_uuid(),%L,%L)',:'code','b9000000-0000-0000-0000-000000000004',:'fixture','postpone'),'spectator cannot request');
SELECT public.game_create_competition(gen_random_uuid(),'Other tournament','Other','b9000000-0000-0000-0000-000000000005','b9000000-0000-0000-0000-000000000006',ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002']::uuid[],'{}'::uuid[]) AS other \gset
SELECT pg_temp.reject_it(format('SELECT public.game_fixture_schedule(%L,%L,gen_random_uuid(),%L,%L,false,true)',:'other'::jsonb->>'code','b9000000-0000-0000-0000-000000000005',:'fixture','postpone'),'cannot target another tournament fixture');
SELECT gen_random_uuid() AS request_key \gset
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000002',:'request_key',:'fixture','postpone');
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000002',:'request_key',:'fixture','postpone');
SELECT pg_temp.check_it((SELECT status='scheduled' AND postpone_requested_club_id=:'north' FROM game.fixtures WHERE id=:'fixture'),'request replay cannot accept itself');
SELECT pg_temp.reject_it(format('SELECT public.game_fixture_schedule(%L,%L,gen_random_uuid(),%L,%L,true)',:'code','b9000000-0000-0000-0000-000000000003',:'fixture','postpone'),'rival cannot cancel');
SELECT pg_temp.reject_it(format('SELECT public.game_fixture_schedule(%L,%L,gen_random_uuid(),%L,%L,false,true)',:'code','b9000000-0000-0000-0000-000000000002',:'fixture','postpone'),'member cannot force');
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),:'fixture','postpone',true);
SELECT pg_temp.check_it((SELECT postpone_requested_club_id IS NULL FROM game.fixtures WHERE id=:'fixture'),'cancel request');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),:'fixture','postpone');
SELECT gen_random_uuid() AS accept_key \gset
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000003',:'accept_key',:'fixture','postpone');
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000003',:'accept_key',:'fixture','postpone');
SELECT pg_temp.check_it((SELECT status='postponed' AND proposal IS NULL FROM game.fixtures WHERE id=:'fixture'),'postponed');
SELECT pg_temp.check_it((SELECT count(*)=6 FROM game.postponed_lineup_archive WHERE fixture_id=:'fixture'),'four players and two confirmations archived');
SELECT pg_temp.check_it(NOT EXISTS(SELECT 1 FROM game.lineups WHERE fixture_id=:'fixture') AND NOT EXISTS(SELECT 1 FROM game.lineup_confirmations WHERE fixture_id=:'fixture'),'clear unfinished frozen lineups');
SELECT pg_temp.reject_it(format('SELECT public.game_competition_command(%L,%L,gen_random_uuid(),%L,%L::jsonb)',:'code','b9000000-0000-0000-0000-000000000001','result_force',jsonb_build_object('fixtureId',:'fixture','homeGoals',1,'awayGoals',0)),'force result while postponed');
SELECT pg_temp.reject_it(format('SELECT public.game_competition_command(%L,%L,gen_random_uuid(),%L)',:'code','b9000000-0000-0000-0000-000000000001','round_close'),'cannot close round with postponement');
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),:'fixture','reactivate');
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),:'fixture','reactivate',true);
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),:'fixture','reactivate');
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),:'fixture','reactivate');
SELECT pg_temp.check_it((SELECT status='scheduled' AND reactivate_requested_club_id IS NULL FROM game.fixtures WHERE id=:'fixture'),'reactivated with new confirmations required');
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),:'fixture','postpone',false,true);
SELECT public.game_fixture_schedule(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),:'fixture','reactivate',false,true);
SELECT pg_temp.check_it(NOT EXISTS(SELECT 1 FROM game.expenses WHERE fixture_id=:'fixture'),'postponing has no charges');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'result_force',jsonb_build_object('fixtureId',:'fixture','homeGoals',1,'awayGoals',0));
SELECT pg_temp.reject_it(format('SELECT public.game_fixture_schedule(%L,%L,gen_random_uuid(),%L,%L,false,true)',:'code','b9000000-0000-0000-0000-000000000001',:'fixture','postpone'),'finished match immutable');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo Postponement tests passed: request, cancel, rival accept, force, retry, financial guards and replay after reactivation.
