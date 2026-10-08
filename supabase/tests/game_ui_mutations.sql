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
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'configure','{"dailyBasic":1,"seasonIncome":10000000}');
SELECT pg_temp.reject_it(format('SELECT public.game_next_season(%L,%L,gen_random_uuid())',:'code','b9000000-0000-0000-0000-000000000001'),'cannot skip season');
SELECT pg_temp.reject_it(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,NULL,NULL,%L,60)',:'code','b9000000-0000-0000-0000-000000000001','open','winter'),'winter before league');
SELECT public.game_market_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60) AS opened \gset
SELECT pg_temp.reject_it(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,%L,NULL,NULL,10)',:'code','b9000000-0000-0000-0000-000000000001','auction_open','f3000000-0000-0000-0000-000000000001'),'vote required');
SELECT public.game_activity_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'vote_open','{"minutes":2,"auctionMinutes":10}') AS voted \gset
SELECT :'voted'::jsonb->>'ballotId' AS ballot \gset
SELECT public.game_activity_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'vote',jsonb_build_object('ballotId',:'ballot','playerId','f3000000-0000-0000-0000-000000000001'));
SELECT pg_temp.reject_it(format('SELECT public.game_activity_command(%L,%L,gen_random_uuid(),%L,%L::jsonb)',:'code','b9000000-0000-0000-0000-000000000001','vote_close',jsonb_build_object('ballotId',:'ballot')),'early vote close');
SELECT public.game_activity_command(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),'vote',jsonb_build_object('ballotId',:'ballot','playerId','f3000000-0000-0000-0000-000000000002'));
SELECT public.game_activity_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'vote_close',jsonb_build_object('ballotId',:'ballot')) AS elected \gset
SELECT pg_temp.check_it((:'elected'::jsonb->>'playerId')='f3000000-0000-0000-0000-000000000001','deterministic tie');
SELECT public.game_auction_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'auction_bid',NULL,(:'elected'::jsonb->>'auctionId')::uuid,30000000);
SELECT gen_random_uuid() AS end_key \gset
SELECT pg_temp.reject_it(format('SELECT public.game_ui_end_auction(%L,%L,gen_random_uuid(),%L)',:'code','b9000000-0000-0000-0000-000000000002',:'elected'::jsonb->>'auctionId'),'member cannot close auction');
SELECT public.game_ui_end_auction(:'code','b9000000-0000-0000-0000-000000000001',:'end_key',(:'elected'::jsonb->>'auctionId')::uuid) AS closed \gset
SELECT pg_temp.check_it(public.game_ui_end_auction(:'code','b9000000-0000-0000-0000-000000000001',:'end_key',(:'elected'::jsonb->>'auctionId')::uuid)=:'closed'::jsonb,'admin close replay');
SELECT pg_temp.check_it((SELECT balance=130000000 AND reserved=0 FROM game.accounts WHERE club_id=:'north'),'auction paid once and hold released');
SELECT public.game_market_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'league_start','{"legs":2}');
SELECT pg_temp.check_it((SELECT count(*)=2 FROM game.fixtures WHERE tournament_id=:'tid'),'two legs');
SELECT id AS fixture FROM game.fixtures WHERE tournament_id=:'tid' AND round=1 \gset
SELECT pg_temp.reject_it(format('SELECT public.game_choose_club(%L,%L,%L,gen_random_uuid())',:'code','b9000000-0000-0000-0000-000000000002',:'north'),'cannot change club in league');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'result_submit',jsonb_build_object('fixtureId',:'fixture','homeGoals',2,'awayGoals',1,'cards',jsonb_build_array(jsonb_build_object('playerId','f2000000-0000-0000-0000-000000000001','kind','red'))));
SELECT gen_random_uuid() AS confirm_key \gset
SELECT public.game_ui_confirm_result(:'code','b9000000-0000-0000-0000-000000000003',:'confirm_key',:'fixture','[{"playerId":"f2000000-0000-0000-0000-000000000003","kind":"yellow"},{"playerId":"f2000000-0000-0000-0000-000000000001","kind":"yellow"}]');
SELECT public.game_ui_confirm_result(:'code','b9000000-0000-0000-0000-000000000003',:'confirm_key',:'fixture','[{"playerId":"f2000000-0000-0000-0000-000000000003","kind":"yellow"},{"playerId":"f2000000-0000-0000-0000-000000000001","kind":"yellow"}]');
SELECT pg_temp.check_it((SELECT count(*)=1 FROM game.suspensions WHERE tournament_id=:'tid'),'single red sanction');
SELECT pg_temp.check_it((SELECT count(*)=1 FROM game.operations WHERE tournament_id=:'tid' AND idempotency_key='fixture-finance:'||:'fixture'||':'||:'north'),'one salary debit');
SELECT pg_temp.check_it((SELECT count(*)=2 AND jsonb_agg(jsonb_build_object('playerId',player_id,'kind',kind)) @> '[{"playerId":"f2000000-0000-0000-0000-000000000001","kind":"red"},{"playerId":"f2000000-0000-0000-0000-000000000003","kind":"yellow"}]'::jsonb FROM game.cards WHERE fixture_id=:'fixture'),'each manager owns their cards; rival red preserved');
SELECT pg_temp.check_it((SELECT count(*)=2 FROM game.operations WHERE tournament_id=:'tid' AND kind='match_expenses' AND payload->>'fixture'=:'fixture'),'confirmation replay does not double charge');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo Original UI mutation regressions passed: admin close, replay, card ownership and financial atomicity.

