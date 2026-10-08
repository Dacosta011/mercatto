BEGIN;
-- CATALOG_FIXTURES
CREATE FUNCTION pg_temp.check_it(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF; END $$;
SELECT public.game_create_competition(gen_random_uuid(),'Pool test','North','bc000000-0000-0000-0000-000000000001','bc000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002']::uuid[],ARRAY[]::uuid[]) AS created \gset
SELECT :'created'::jsonb->>'id' AS tid,:'created'::jsonb->>'code' AS code \gset
SELECT id AS north FROM game.clubs WHERE tournament_id=:'tid' AND name='Prueba Norte' \gset
SELECT id AS south FROM game.clubs WHERE tournament_id=:'tid' AND name='Prueba Sur' \gset
SELECT public.game_choose_club(:'code','bc000000-0000-0000-0000-000000000002',:'north',gen_random_uuid());
SET LOCAL ROLE service_role;
SELECT public.game_market_command(:'code','bc000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60);
SELECT pg_temp.check_it(jsonb_array_length(public.game_market_state(:'code','bc000000-0000-0000-0000-000000000002')->'freePlayers')=2,'unmanaged roster supplies daily pool');
SELECT gen_random_uuid() AS claim_key \gset
SELECT public.game_market_command(:'code','bc000000-0000-0000-0000-000000000002',:'claim_key','sign','f2000000-0000-0000-0000-000000000003');
SELECT public.game_market_command(:'code','bc000000-0000-0000-0000-000000000002',:'claim_key','sign','f2000000-0000-0000-0000-000000000003');
SELECT pg_temp.check_it((SELECT count(*)=1 FROM game.operations WHERE tournament_id=:'tid' AND kind='unmanaged_source'),'unmanaged origin retained once');
SELECT pg_temp.check_it((SELECT club_id=:'north' FROM game.contracts WHERE tournament_id=:'tid' AND player_id='f2000000-0000-0000-0000-000000000003' AND ended_at IS NULL),'only tournament ownership moved');
SELECT pg_temp.check_it((SELECT balance=260000000 FROM game.accounts WHERE club_id=:'south'),'unmanaged club budget preserved');
SELECT pg_temp.check_it(EXISTS(SELECT 1 FROM public.team_players WHERE team_id='f1000000-0000-0000-0000-000000000002' AND player_id='f2000000-0000-0000-0000-000000000003'),'catalogue roster preserved');
SELECT public.game_social_command(:'code','bc000000-0000-0000-0000-000000000002',gen_random_uuid(),'post','Private test post') AS posted \gset
SELECT public.game_social_command(:'code','bc000000-0000-0000-0000-000000000002',gen_random_uuid(),'like',NULL,(:'posted'::jsonb->>'postId')::uuid);
SELECT pg_temp.check_it((public.game_social_state(:'code','bc000000-0000-0000-0000-000000000002')->0->>'likes')::integer=1,'social state');
SELECT pg_temp.check_it(NOT has_table_privilege('anon','public.members','UPDATE') AND NOT has_table_privilege('anon','public.tournaments','UPDATE'),'browser cannot replace credentials');
SELECT pg_temp.check_it(NOT has_table_privilege('anon','public.team_players','DELETE'),'browser cannot mutate catalogue');
SELECT pg_temp.check_it(NOT has_function_privilege('anon','public.game_competition_command(text,text,uuid,text,jsonb)','EXECUTE'),'RPC server only');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo Pool, social isolation and browser privilege tests passed.
