BEGIN;
-- CATALOG_FIXTURES
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; END $$;
CREATE FUNCTION pg_temp.reject_it(command text,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN BEGIN EXECUTE command; EXCEPTION WHEN SQLSTATE 'GM001' OR SQLSTATE '28000' OR SQLSTATE 'P0001' THEN RETURN; END; RAISE EXCEPTION 'Expected rejection: %',label; END $$;
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

RESET ROLE;
INSERT INTO public.players(id,name,ovr,position,price,clause,is_icon)
 SELECT ('f3000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid,'Voting icon '||n,90,'ST',30000000,39000000,true FROM generate_series(3,9) n;
INSERT INTO game.players(tournament_id,player_id,name,ovr,position,is_icon,reference_price,reference_clause)
 SELECT :'tid',id,name,ovr,position,is_icon,price,clause FROM public.players WHERE name LIKE 'Voting icon %';
SET LOCAL ROLE service_role;
SELECT gen_random_uuid() AS vote_key \gset
SELECT public.game_activity_command(:'code','b9000000-0000-0000-0000-000000000001',:'vote_key','vote_open','{"minutes":2,"auctionMinutes":10}') AS voted \gset
SELECT :'voted'::jsonb->>'ballotId' AS ballot \gset
SELECT pg_temp.check_it((SELECT count(*)=5 FROM game.ballot_options WHERE ballot_id=:'ballot'),'exactly five options from nine eligible icons');
SELECT pg_temp.check_it(public.game_activity_command(:'code','b9000000-0000-0000-0000-000000000001',:'vote_key','vote_open','{"minutes":2,"auctionMinutes":10}')=:'voted'::jsonb,'replay retains the same ballot');
SELECT pg_temp.check_it((SELECT count(*)=5 FROM game.ballot_options WHERE ballot_id=:'ballot'),'replay does not add or reroll candidates');
SELECT player_id AS excluded FROM game.players WHERE tournament_id=:'tid' AND is_icon AND player_id NOT IN(SELECT player_id FROM game.ballot_options WHERE ballot_id=:'ballot') LIMIT 1 \gset
SELECT pg_temp.reject_it(format('SELECT public.game_activity_command(%L,%L,gen_random_uuid(),%L,%L::jsonb)',:'code','b9000000-0000-0000-0000-000000000002','vote',jsonb_build_object('ballotId',:'ballot','playerId',:'excluded')),'cannot vote for an icon outside the five');
ROLLBACK;
\echo Five random icon options regression passed.
