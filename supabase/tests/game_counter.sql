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
SELECT public.game_create_tournament(gen_random_uuid(),'Counter','Buyer','b5000000-0000-0000-0000-000000000001','b5000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002']::uuid[],ARRAY[]::uuid[]) AS created \gset
SELECT :'created'::jsonb->>'code' AS code, :'created'::jsonb->>'id' AS tournament \gset
SELECT id AS north FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000001' \gset
SELECT id AS south FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000002' \gset
SELECT public.game_join_tournament(:'code','Seller','b5000000-0000-0000-0000-000000000003',gen_random_uuid());
SELECT public.game_choose_club(:'code','b5000000-0000-0000-0000-000000000002',:'north',gen_random_uuid());
SELECT public.game_choose_club(:'code','b5000000-0000-0000-0000-000000000003',:'south',gen_random_uuid());
SET LOCAL ROLE service_role;
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60) AS opened \gset
SELECT :'opened'::jsonb->>'windowId' AS window \gset
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000002',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000003',NULL,20000000) AS offered \gset
SELECT :'offered'::jsonb->>'offerId' AS offer \gset
SELECT gen_random_uuid() AS counter_key \gset
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000003',:'counter_key','counter',NULL,:'offer',180000000) AS countered \gset
SELECT pg_temp.assert(public.game_market_command(:'code','b5000000-0000-0000-0000-000000000003',:'counter_key','counter',NULL,:'offer',180000000)=:'countered'::jsonb,'counter retry returns same result');
SELECT pg_temp.assert((SELECT reserved=20000000 AND balance=160000000 FROM game.accounts WHERE club_id=:'north'),'seller cannot reserve extra buyer money');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,%L)',:'code','b5000000-0000-0000-0000-000000000003','accept',:'offer'),'28000');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,%L)',:'code','b5000000-0000-0000-0000-000000000002','accept',:'offer'),'GM001');
SELECT pg_temp.assert((SELECT reserved=20000000 AND balance=160000000 FROM game.accounts WHERE club_id=:'north'),'failed counter acceptance retains original hold');
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000002',gen_random_uuid(),'counter',NULL,:'offer',25000000);
SELECT pg_temp.assert((SELECT reserved=25000000 FROM game.accounts WHERE club_id=:'north'),'buyer counter resizes own hold');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,%L,30000000)',:'code','b5000000-0000-0000-0000-000000000002','counter',:'offer'),'28000');
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000003',gen_random_uuid(),'counter',NULL,:'offer',30000000);
SELECT pg_temp.assert((SELECT reserved=25000000 FROM game.accounts WHERE club_id=:'north'),'seller counter still requires buyer consent');
SELECT pg_temp.assert((SELECT buyer_club_id=:'north' AND seller_club_id=:'south' AND proposal_revision=3 FROM game.offers WHERE id=:'offer'),'negotiation preserves economic parties');
SELECT pg_temp.assert((SELECT count(*)=4 FROM game.offer_revisions WHERE offer_id=:'offer'),'history includes original and three proposals, no retry duplicate');
SELECT pg_temp.assert(jsonb_array_length(public.game_market_state(:'code','b5000000-0000-0000-0000-000000000002')->'offers'->0->'revisions')=4,'snapshot exposes history');
RESET ROLE;
CREATE FUNCTION pg_temp.fail_counter_contract() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected counter settlement failure' USING ERRCODE='ZX001'; END $$;
CREATE TRIGGER injected_counter_failure BEFORE INSERT ON game.contracts FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_counter_contract();
SET LOCAL ROLE service_role;
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,%L)',:'code','b5000000-0000-0000-0000-000000000002','accept',:'offer'),'ZX001');
SELECT pg_temp.assert((SELECT balance=160000000 AND reserved=25000000 FROM game.accounts WHERE club_id=:'north'),'late settlement failure restores previous committed hold');
SELECT pg_temp.assert((SELECT balance=260000000 FROM game.accounts WHERE club_id=:'south'),'late counter failure restores seller credit');
SELECT pg_temp.assert((SELECT status='pending' AND amount=25000000 AND proposed_amount=30000000 FROM game.offers WHERE id=:'offer'),'late failure restores negotiation');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.transfers WHERE tournament_id=:'tournament'),'late failure creates no transfer');
RESET ROLE;
DROP TRIGGER injected_counter_failure ON game.contracts;
SET LOCAL ROLE service_role;
SELECT gen_random_uuid() AS accept_key \gset
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000002',:'accept_key','accept',NULL,:'offer') AS accepted \gset
SELECT pg_temp.assert(public.game_market_command(:'code','b5000000-0000-0000-0000-000000000002',:'accept_key','accept',NULL,:'offer')=:'accepted'::jsonb,'buyer acceptance retry');
SELECT pg_temp.assert((SELECT balance=130000000 AND reserved=0 FROM game.accounts WHERE club_id=:'north'),'buyer pays final counter once');
SELECT pg_temp.assert((SELECT balance=290000000 FROM game.accounts WHERE club_id=:'south'),'seller receives final counter');
SELECT pg_temp.assert((SELECT club_id=:'north' AND acquired_price=30000000 FROM game.contracts WHERE tournament_id=:'tournament' AND player_id='f2000000-0000-0000-0000-000000000003' AND ended_at IS NULL),'counter transfers player to original buyer');
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000002',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,10000000) AS next_offer \gset
SELECT :'next_offer'::jsonb->>'offerId' AS next_id \gset
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000003',gen_random_uuid(),'counter',NULL,:'next_id',20000000);
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000002',gen_random_uuid(),'counter',NULL,:'next_id',15000000);
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000003',gen_random_uuid(),'accept',NULL,:'next_id');
SELECT pg_temp.assert((SELECT balance=115000000 AND reserved=0 FROM game.accounts WHERE club_id=:'north'),'seller accepts buyer counter');
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000003',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000001',NULL,10000000) AS expiring \gset
SELECT :'expiring'::jsonb->>'offerId' AS expiring_id \gset
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000002',gen_random_uuid(),'counter',NULL,:'expiring_id',20000000);
UPDATE game.market_windows SET opens_at=clock_timestamp()-interval '2 minutes',closes_at=clock_timestamp()-interval '1 minute' WHERE id=:'window';
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,%L)',:'code','b5000000-0000-0000-0000-000000000003','accept',:'expiring_id'),'GM001');
SELECT pg_temp.assert(public.game_expire_markets()->>'closed'='1','worker expires window');
SELECT pg_temp.assert(public.game_expire_markets()->>'closed'='0','worker retry is a no-op');
SELECT pg_temp.assert((SELECT count(*)=1 FROM game.operations WHERE tournament_id=:'tournament' AND kind='market_auto_close'),'one automatic closure');
SELECT pg_temp.assert((SELECT status='expired' FROM game.offers WHERE id=:'expiring_id'),'negotiated offer expires');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts WHERE tournament_id=:'tournament' AND reserved<>0),'worker releases committed money');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=:'window' AND purchases_held<>0),'worker releases held quota');
SELECT public.game_next_season(:'code','b5000000-0000-0000-0000-000000000001',gen_random_uuid());
SELECT public.game_market_command(:'code','b5000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60) AS future_window \gset
SELECT pg_temp.assert(public.game_expire_markets()->>'closed'='0','worker leaves unexpired windows open');
SELECT pg_temp.assert((SELECT status='open' FROM game.market_windows WHERE id=(:'future_window'::jsonb->>'windowId')::uuid),'future window remains open');
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)),'counter balances reconcile');
RESET ROLE;
SELECT pg_temp.must_fail(format('UPDATE game.offer_revisions SET amount=1 WHERE offer_id=%L',:'offer'),'P0001');
SELECT pg_temp.assert(NOT has_function_privilege('anon','public.game_expire_markets(integer)','EXECUTE'),'anonymous cannot run worker');
SELECT pg_temp.assert(NOT has_schema_privilege('authenticated','game','USAGE'),'private game history');
ROLLBACK;
\echo Counteroffers and automatic market closure tests passed.
