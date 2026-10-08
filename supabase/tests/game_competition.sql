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
SELECT public.game_activity_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'spin') AS spun \gset
SELECT public.game_activity_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'spin_claim',jsonb_build_object('spinId',:'spun'::jsonb->>'spinId'));
SELECT pg_temp.check_it((SELECT count(*)=1 FROM game.daily_claims WHERE tournament_id=:'tid'),'one daily claim');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'release','{"playerId":"f2000000-0000-0000-0000-000000000005"}');
SELECT pg_temp.reject_it(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','b9000000-0000-0000-0000-000000000002','sign','f2000000-0000-0000-0000-000000000005'),'cannot recycle release');
SELECT public.game_market_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'league_start','{"legs":2}');
SELECT pg_temp.check_it((SELECT count(*)=2 FROM game.fixtures WHERE tournament_id=:'tid'),'two legs');
SELECT id AS fixture FROM game.fixtures WHERE tournament_id=:'tid' AND round=1 \gset
SELECT pg_temp.reject_it(format('SELECT public.game_choose_club(%L,%L,%L,gen_random_uuid())',:'code','b9000000-0000-0000-0000-000000000002',:'north'),'cannot change club in league');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'result_submit',jsonb_build_object('fixtureId',:'fixture','homeGoals',2,'awayGoals',1,'cards',jsonb_build_array(jsonb_build_object('playerId','f2000000-0000-0000-0000-000000000001','kind','red'))));
SELECT gen_random_uuid() AS confirm_key \gset
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000003',:'confirm_key','result_confirm',jsonb_build_object('fixtureId',:'fixture'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000003',:'confirm_key','result_confirm',jsonb_build_object('fixtureId',:'fixture'));
SELECT pg_temp.check_it((SELECT count(*)=1 FROM game.suspensions WHERE tournament_id=:'tid'),'single red sanction');
SELECT pg_temp.check_it((SELECT count(*)=1 FROM game.operations WHERE tournament_id=:'tid' AND idempotency_key='fixture-finance:'||:'fixture'||':'||:'north'),'one salary debit');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'round_close');
SELECT public.game_market_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'winter',60) AS winter \gset
SELECT pg_temp.check_it((SELECT purchase_limit=2 FROM game.market_windows WHERE id=(:'winter'::jsonb->>'windowId')::uuid),'winter quota');
SELECT public.game_market_command(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000001',NULL,20000000) AS offer \gset
SELECT public.game_market_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'accept',NULL,(:'offer'::jsonb->>'offerId')::uuid);
SELECT pg_temp.check_it((SELECT price=40000000 FROM game.lineups WHERE fixture_id=:'fixture' AND player_id='f2000000-0000-0000-0000-000000000001'),'historical price unchanged');
SELECT public.game_market_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT id AS fixture2 FROM game.fixtures WHERE tournament_id=:'tid' AND round=2 \gset
SELECT pg_temp.reject_it(format('SELECT public.game_competition_command(%L,%L,gen_random_uuid(),%L,%L::jsonb)',:'code','b9000000-0000-0000-0000-000000000003','lineup',jsonb_build_object('fixtureId',:'fixture2','players',jsonb_build_array('f2000000-0000-0000-0000-000000000001'))),'sanction follows transferred player');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000002',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture2'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000003',gen_random_uuid(),'lineup',jsonb_build_object('fixtureId',:'fixture2'));
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'result_force',jsonb_build_object('fixtureId',:'fixture2','homeGoals',0,'awayGoals',0));
SELECT pg_temp.check_it((SELECT count(*)=1 FROM game.suspension_servings WHERE tournament_id=:'tid'),'suspension served at new club');
SELECT public.game_competition_command(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid(),'round_close');
SELECT pg_temp.check_it((SELECT bool_and(expired_at IS NOT NULL) FROM game.suspensions WHERE tournament_id=:'tid'),'sanctions expire at season end');
SELECT public.game_next_season(:'code','b9000000-0000-0000-0000-000000000001',gen_random_uuid());
SELECT pg_temp.check_it((SELECT count(*)=2 FROM game.operations WHERE tournament_id=:'tid' AND kind='match_expenses' AND payload->>'fixture'=:'fixture'),'retries did not double charge');
SELECT pg_temp.check_it((SELECT count(*)=2 FROM game.seasons WHERE tournament_id=:'tid'),'new season with history');
SELECT public.game_competition_state(:'code','b9000000-0000-0000-0000-000000000002') AS snapshot \gset
SELECT pg_temp.check_it(jsonb_array_length(:'snapshot'::jsonb->'fixtures')=2,'sport history available');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo Complete competition tests passed; fixtures rolled back.
