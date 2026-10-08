BEGIN;
-- CATALOG_FIXTURES
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.reject_it(command text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN BEGIN EXECUTE command; EXCEPTION WHEN OTHERS THEN RETURN; END; RAISE EXCEPTION 'Expected rejection'; END $$;
SELECT public.game_create_competition(gen_random_uuid(),'Sport edge cases','North','ba000000-0000-0000-0000-000000000001','ba000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],
 ARRAY['f2000000-0000-0000-0000-000000000005','f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002']::uuid[]) AS created \gset
SELECT :'created'::jsonb->>'id' AS tid,:'created'::jsonb->>'code' AS code \gset
SELECT id AS north FROM game.clubs WHERE tournament_id=:'tid' AND name='Prueba Norte' \gset
SELECT id AS south FROM game.clubs WHERE tournament_id=:'tid' AND name='Prueba Sur' \gset
SELECT id AS reserve FROM game.clubs WHERE tournament_id=:'tid' AND name='Prueba Reserva' \gset
SELECT public.game_join_tournament(:'code','South','ba000000-0000-0000-0000-000000000003',gen_random_uuid());
SELECT public.game_join_tournament(:'code','Reserve','ba000000-0000-0000-0000-000000000004',gen_random_uuid());
SELECT public.game_choose_club(:'code','ba000000-0000-0000-0000-000000000002',:'north',gen_random_uuid());
SELECT public.game_choose_club(:'code','ba000000-0000-0000-0000-000000000003',:'south',gen_random_uuid());
SELECT public.game_choose_club(:'code','ba000000-0000-0000-0000-000000000004',:'reserve',gen_random_uuid());
SET LOCAL ROLE service_role;
SELECT public.game_competition_command(:'code','ba000000-0000-0000-0000-000000000001',gen_random_uuid(),'configure','{"dailyBasic":0,"maxSquad":2}');
SELECT public.game_market_command(:'code','ba000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60) AS market \gset
SELECT pg_temp.reject_it(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','ba000000-0000-0000-0000-000000000002','sign','f2000000-0000-0000-0000-000000000005'));
SELECT pg_temp.reject_it(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','ba000000-0000-0000-0000-000000000004','sign','f2000000-0000-0000-0000-000000000005'));
SELECT public.game_activity_command(:'code','ba000000-0000-0000-0000-000000000001',gen_random_uuid(),'vote_open','{"minutes":1,"auctionMinutes":1}') AS ballot \gset
RESET ROLE;
UPDATE game.ballots SET ends_at=clock_timestamp()-interval '1 second' WHERE id=(:'ballot'::jsonb->>'ballotId')::uuid;
SET LOCAL ROLE service_role;
SELECT public.game_expire_markets();
SELECT pg_temp.check_it((SELECT status='chosen' FROM game.ballots WHERE id=(:'ballot'::jsonb->>'ballotId')::uuid),'worker opens auction on zero-vote tie');
SELECT public.game_market_command(:'code','ba000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT public.game_competition_command(:'code','ba000000-0000-0000-0000-000000000001',gen_random_uuid(),'league_start','{"legs":2}');
SELECT pg_temp.check_it((SELECT count(*)=6 FROM game.fixtures WHERE tournament_id=:'tid'),'odd league has every pair both ways');
SELECT pg_temp.check_it(NOT EXISTS(SELECT 1 FROM (SELECT round,club,count(*) n FROM (SELECT round,home_club_id club FROM game.fixtures WHERE tournament_id=:'tid' UNION ALL SELECT round,away_club_id FROM game.fixtures WHERE tournament_id=:'tid') x GROUP BY round,club) counts WHERE n>1),'at most one fixture per club per round');
SELECT id AS fixture,home_club_id AS home,away_club_id AS away FROM game.fixtures WHERE tournament_id=:'tid' AND round=1 \gset
-- Reduce budgets through balanced ledger operations, never by direct account writes.
SELECT game.cash(:'tid',:'north',-159999999,'test_charge','edge-budget');
SELECT CASE WHEN :'home'=:'north' THEN 'ba000000-0000-0000-0000-000000000002' WHEN :'home'=:'south' THEN 'ba000000-0000-0000-0000-000000000003' ELSE 'ba000000-0000-0000-0000-000000000004' END AS home_token,
 CASE WHEN :'away'=:'north' THEN 'ba000000-0000-0000-0000-000000000002' WHEN :'away'=:'south' THEN 'ba000000-0000-0000-0000-000000000003' ELSE 'ba000000-0000-0000-0000-000000000004' END AS away_token \gset
SELECT public.game_competition_command(:'code',:'home_token',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code',:'away_token',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
RESET ROLE;
CREATE FUNCTION pg_temp.fail_result() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected late sporting failure'; END $$;
CREATE TRIGGER injected_result BEFORE UPDATE ON game.fixtures FOR EACH ROW WHEN(NEW.status='finished') EXECUTE FUNCTION pg_temp.fail_result();
SET LOCAL ROLE service_role;
SELECT pg_temp.reject_it(format('SELECT public.game_competition_command(%L,%L,gen_random_uuid(),%L,%L::jsonb)',:'code','ba000000-0000-0000-0000-000000000001','result_force',jsonb_build_object('fixtureId',:'fixture','homeGoals',0,'awayGoals',0)));
SELECT pg_temp.check_it((SELECT count(*)=0 FROM game.expenses WHERE fixture_id=:'fixture'),'expense rollback');
SELECT pg_temp.check_it((SELECT count(*)=0 FROM game.releases WHERE tournament_id=:'tid'),'release rollback');
RESET ROLE;
DROP TRIGGER injected_result ON game.fixtures;
SET LOCAL ROLE service_role;
SELECT public.game_competition_command(:'code','ba000000-0000-0000-0000-000000000001',gen_random_uuid(),'result_force',jsonb_build_object('fixtureId',:'fixture','homeGoals',0,'awayGoals',0));
-- If North had a bye in round 1, target its first scheduled match after closing the round.
SELECT public.game_competition_command(:'code','ba000000-0000-0000-0000-000000000001',gen_random_uuid(),'round_close');
SELECT gen_random_uuid() AS leave_key \gset
SELECT public.game_competition_command(:'code','ba000000-0000-0000-0000-000000000004',:'leave_key','leave');
SELECT public.game_competition_command(:'code','ba000000-0000-0000-0000-000000000004',:'leave_key','leave');
SELECT public.game_join_tournament(:'code','Replacement','ba000000-0000-0000-0000-000000000005',gen_random_uuid()) AS replacement \gset
SELECT public.game_competition_command(:'code','ba000000-0000-0000-0000-000000000001',gen_random_uuid(),'replace',jsonb_build_object('clubId',:'reserve','memberId',:'replacement'::jsonb->>'memberId'));
SELECT pg_temp.check_it((SELECT balance=100000000 FROM game.accounts WHERE club_id=:'reserve'),'replacement inherits budget');
SELECT pg_temp.check_it((public.game_competition_state(:'code','ba000000-0000-0000-0000-000000000002')->>'enabled')::boolean,'read complete snapshot');
RESET ROLE;
SELECT public.game_create_competition(gen_random_uuid(),'Auto release test','North','bb000000-0000-0000-0000-000000000001','bb000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002']::uuid[],ARRAY[]::uuid[]) AS automatic \gset
SELECT :'automatic'::jsonb->>'id' AS auto_tid,:'automatic'::jsonb->>'code' AS auto_code \gset
SELECT id AS auto_north FROM game.clubs WHERE tournament_id=:'auto_tid' AND name='Prueba Norte' \gset
SELECT id AS auto_south FROM game.clubs WHERE tournament_id=:'auto_tid' AND name='Prueba Sur' \gset
SELECT public.game_join_tournament(:'auto_code','South','bb000000-0000-0000-0000-000000000003',gen_random_uuid());
SELECT public.game_choose_club(:'auto_code','bb000000-0000-0000-0000-000000000002',:'auto_north',gen_random_uuid());
SELECT public.game_choose_club(:'auto_code','bb000000-0000-0000-0000-000000000003',:'auto_south',gen_random_uuid());
UPDATE game.contracts SET acquired_price=0 WHERE tournament_id=:'auto_tid' AND club_id=:'auto_south';
SET LOCAL ROLE service_role;
SELECT game.cash(:'auto_tid',:'auto_north',-159999999,'test_charge','auto-budget-north');
SELECT game.cash(:'auto_tid',:'auto_south',-259999999,'test_charge','auto-budget-south');
SELECT public.game_competition_command(:'auto_code','bb000000-0000-0000-0000-000000000001',gen_random_uuid(),'league_start');
SELECT id AS auto_fixture FROM game.fixtures WHERE tournament_id=:'auto_tid' AND round=1 \gset
SELECT public.game_competition_command(:'auto_code','bb000000-0000-0000-0000-000000000002',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'auto_fixture'));
SELECT public.game_competition_command(:'auto_code','bb000000-0000-0000-0000-000000000003',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'auto_fixture'));
SELECT public.game_competition_command(:'auto_code','bb000000-0000-0000-0000-000000000001',gen_random_uuid(),'result_force',jsonb_build_object('fixtureId',:'auto_fixture','homeGoals',0,'awayGoals',0,'cards',jsonb_build_array(jsonb_build_object('playerId','f2000000-0000-0000-0000-000000000003','kind','red'))));
SELECT pg_temp.check_it((SELECT count(*)=1 AND sum(refund)=20000000 FROM game.releases WHERE tournament_id=:'auto_tid'),'most expensive released, half refunded');
SELECT pg_temp.check_it((SELECT balance=17000001 FROM game.accounts WHERE club_id=:'auto_north'),'auto release pays full salaries');
SELECT pg_temp.check_it((SELECT amount=1999999 FROM game.debts WHERE club_id=:'auto_south'),'uncovered mandatory charge becomes explicit debt');
SELECT pg_temp.check_it((SELECT count(*)=2 FROM game.lineups WHERE fixture_id=:'auto_fixture' AND club_id=:'auto_north'),'released player remains in match snapshot');
SELECT game.cash(:'auto_tid',:'auto_south',3000000,'test_income','auto-income');
SELECT public.game_competition_command(:'auto_code','bb000000-0000-0000-0000-000000000003',gen_random_uuid(),'pay_debt');
SELECT pg_temp.check_it((SELECT amount=0 FROM game.debts WHERE club_id=:'auto_south'),'debt payment clears outstanding balance');
SELECT pg_temp.check_it((SELECT balance=1000001 FROM game.accounts WHERE club_id=:'auto_south'),'debt payment has balanced ledger');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo Competition edge tests passed: odd schedule, daily limits, automatic voting, late rollback and replacements.
