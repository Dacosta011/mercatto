\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.assert(p_ok boolean,p_message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',p_message; END IF; END $$;
CREATE FUNCTION pg_temp.must_fail(p_query text,p_state text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_query; EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>p_state THEN RAISE; END IF; RETURN; END;
  RAISE EXCEPTION 'FAILED: expected rejection %',p_state;
END $$;
-- CATALOG_FIXTURES
SET LOCAL ROLE service_role;
SELECT public.game_create_tournament('a3000000-0000-0000-0000-000000000001','Logic A','Admin',
 'a4000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],
 ARRAY['f2000000-0000-0000-0000-000000000005']::uuid[]) AS created \gset
SELECT :'created'::jsonb->>'code' AS code, :'created'::jsonb->>'id' AS tournament \gset
SELECT pg_temp.assert(public.game_create_tournament('a3000000-0000-0000-0000-000000000001','Logic A','Admin',
 'a4000000-0000-0000-0000-000000000099','a4000000-0000-0000-0000-000000000098',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],
 ARRAY['f2000000-0000-0000-0000-000000000005']::uuid[]) = :'created'::jsonb,'create retry recovers same credentials');
SELECT public.game_state(:'code','a4000000-0000-0000-0000-000000000002') AS initial \gset
SELECT pg_temp.assert((SELECT count(*)=3 FROM jsonb_array_elements(:'initial'::jsonb->'clubs')),'three scoped clubs');
SELECT pg_temp.assert((SELECT (c->>'budget')::bigint=160000000 FROM jsonb_array_elements(:'initial'::jsonb->'clubs') c WHERE c->>'name'='Prueba Norte'),'north OVR budget');
SELECT pg_temp.assert((SELECT (c->>'budget')::bigint=260000000 FROM jsonb_array_elements(:'initial'::jsonb->'clubs') c WHERE c->>'name'='Prueba Sur'),'south OVR budget');
SELECT pg_temp.assert((SELECT (c->>'budget')::bigint=100000000 FROM jsonb_array_elements(:'initial'::jsonb->'clubs') c WHERE c->>'name'='Prueba Reserva'),'empty squad budget');
SELECT id AS north FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000001' \gset
SELECT public.game_choose_club(:'code','a4000000-0000-0000-0000-000000000002',:'north','a5000000-0000-0000-0000-000000000001') AS chosen \gset
SELECT pg_temp.assert(public.game_choose_club(:'code','a4000000-0000-0000-0000-000000000002',:'north','a5000000-0000-0000-0000-000000000001')=:'chosen'::jsonb,'choose retry');
SELECT public.game_join_tournament(:'code','Other','a4000000-0000-0000-0000-000000000003','a5000000-0000-0000-0000-000000000002') AS joined \gset
SELECT pg_temp.assert(public.game_join_tournament(:'code','Other','a4000000-0000-0000-0000-000000000088','a5000000-0000-0000-0000-000000000002')=:'joined'::jsonb,'join retry recovers credentials');
SELECT pg_temp.must_fail(format('SELECT public.game_join_tournament(%L,%L,%L,%L)',:'code','other','a4000000-0000-0000-0000-000000000004','a5000000-0000-0000-0000-000000000003'),'P0001');
SELECT pg_temp.must_fail(format('SELECT public.game_choose_club(%L,%L,%L,%L)',:'code','a4000000-0000-0000-0000-000000000003',:'north','a5000000-0000-0000-0000-000000000004'),'P0001');
SELECT pg_temp.must_fail(format('SELECT public.game_state(%L,%L)',:'code','a4000000-0000-0000-0000-000000000099'),'28000');
SELECT pg_temp.must_fail(format('SELECT public.game_next_season(%L,%L,%L)',:'code','a4000000-0000-0000-0000-000000000003','a5000000-0000-0000-0000-000000000005'),'28000');
SELECT public.game_next_season(:'code','a4000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000006') AS advanced \gset
SELECT pg_temp.assert(public.game_next_season(:'code','a4000000-0000-0000-0000-000000000001','a5000000-0000-0000-0000-000000000006')=:'advanced'::jsonb,'next-season retry');
SELECT public.game_choose_club(:'code','a4000000-0000-0000-0000-000000000003',:'north','a5000000-0000-0000-0000-000000000007');
SELECT public.game_state(:'code','a4000000-0000-0000-0000-000000000003') AS inherited \gset
SELECT pg_temp.assert((:'inherited'::jsonb->>'season')::integer=2,'new season');
SELECT pg_temp.assert((SELECT (c->>'budget')::bigint=160000000 AND jsonb_array_length(c->'squad')=2 AND c->>'manager'='Other' FROM jsonb_array_elements(:'inherited'::jsonb->'clubs') c WHERE c->>'id'=:'north'),'new manager inherits budget and squad');
SELECT pg_temp.must_fail($q$SELECT public.game_create_tournament('a3000000-0000-0000-0000-000000000009','Must rollback','Admin','a4000000-0000-0000-0000-000000000001','a4000000-0000-0000-0000-000000000002',ARRAY['f1000000-0000-0000-0000-000000000099']::uuid[],ARRAY[]::uuid[])$q$,'P0001');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM public.tournaments WHERE name='Must rollback'),'failed create rolls back tournament and member');
SELECT pg_temp.assert((SELECT count(*)=1 FROM game.players p WHERE p.tournament_id=:'tournament' AND p.player_id='f2000000-0000-0000-0000-000000000005' AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p.tournament_id AND c.player_id=p.player_id AND c.ended_at IS NULL)),'free player has no contract');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id WHERE a.tournament_id=:'tournament' GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)),'opening balances match ledger');
RESET ROLE;
SELECT pg_temp.assert(NOT has_function_privilege('anon','public.game_state(text,text)','EXECUTE') AND NOT has_function_privilege('authenticated','public.game_create_tournament(uuid,text,text,text,text,uuid[],uuid[])','EXECUTE'),'public roles cannot call backend RPC');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo Local flow integration tests passed; fixtures rolled back.
