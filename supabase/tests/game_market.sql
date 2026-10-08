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
INSERT INTO public.players(id,name,ovr,position,price,clause) VALUES
 ('f2000000-0000-0000-0000-000000000006','Libre Segundo',75,'CM',10000000,20000000),
 ('f2000000-0000-0000-0000-000000000007','Libre Tercero',75,'CM',1000000,2000000);
SELECT public.game_create_tournament(gen_random_uuid(),'Market A','Buyer','b4000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],
 ARRAY['f2000000-0000-0000-0000-000000000005','f2000000-0000-0000-0000-000000000006','f2000000-0000-0000-0000-000000000007']::uuid[]) AS created \gset
SELECT :'created'::jsonb->>'code' AS code, :'created'::jsonb->>'id' AS tournament \gset
SELECT public.game_create_tournament(gen_random_uuid(),'Market B','Other buyer','b4000000-0000-0000-0000-000000000011','b4000000-0000-0000-0000-000000000012',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],ARRAY['f2000000-0000-0000-0000-000000000005']::uuid[]) AS other \gset
SELECT :'other'::jsonb->>'id' AS other_tournament \gset
SELECT id AS north FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000001' \gset
SELECT id AS south FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000002' \gset
SELECT id AS reserve FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000003' \gset
SELECT public.game_join_tournament(:'code','Seller','b4000000-0000-0000-0000-000000000003',gen_random_uuid());
SELECT public.game_join_tournament(:'code','Rival','b4000000-0000-0000-0000-000000000004',gen_random_uuid());
SELECT public.game_choose_club(:'code','b4000000-0000-0000-0000-000000000002',:'north',gen_random_uuid());
SELECT public.game_choose_club(:'code','b4000000-0000-0000-0000-000000000003',:'south',gen_random_uuid());
SELECT public.game_choose_club(:'code','b4000000-0000-0000-0000-000000000004',:'reserve',gen_random_uuid());
SET LOCAL ROLE service_role;
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,NULL,NULL,%L,60)',:'code','b4000000-0000-0000-0000-000000000002','open','summer'),'28000');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60) AS opened \gset
SELECT :'opened'::jsonb->>'windowId' AS window \gset
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000002',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000003',NULL,20000000) AS offered \gset
SELECT :'offered'::jsonb->>'offerId' AS offer \gset
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000004',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000003',NULL,10000000) AS rival \gset
SELECT pg_temp.assert((SELECT balance=160000000 AND reserved=20000000 FROM game.accounts WHERE club_id=:'north'),'reserve money without paying seller');
SELECT pg_temp.assert((SELECT purchases_used=0 AND purchases_held=1 FROM game.market_limits WHERE window_id=:'window' AND club_id=:'north'),'reserve purchase slot');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,%L)',:'code','b4000000-0000-0000-0000-000000000002','accept',:'offer'),'28000');
SELECT gen_random_uuid() AS accept_key \gset
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000003',:'accept_key','accept',NULL,:'offer') AS accepted \gset
SELECT pg_temp.assert(public.game_market_command(:'code','b4000000-0000-0000-0000-000000000003',:'accept_key','accept',NULL,:'offer')=:'accepted'::jsonb,'accept retry');
SELECT pg_temp.assert((SELECT balance=140000000 AND reserved=0 FROM game.accounts WHERE club_id=:'north'),'buyer paid once');
SELECT pg_temp.assert((SELECT balance=280000000 FROM game.accounts WHERE club_id=:'south'),'seller received payment');
SELECT pg_temp.assert((SELECT reserved=0 FROM game.accounts WHERE club_id=:'reserve'),'competing hold released');
SELECT pg_temp.assert((SELECT status='stale' FROM game.offers WHERE id=(:'rival'::jsonb->>'offerId')::uuid),'competing offer invalidated');
SELECT pg_temp.assert((SELECT club_id=:'north' AND acquired_price=20000000 FROM game.contracts WHERE tournament_id=:'tournament' AND player_id='f2000000-0000-0000-0000-000000000003' AND ended_at IS NULL),'ownership moved');
SELECT pg_temp.assert((SELECT c.team_id='f1000000-0000-0000-0000-000000000002' FROM game.contracts ct JOIN game.clubs c ON c.id=ct.club_id WHERE ct.tournament_id=:'other_tournament' AND ct.player_id='f2000000-0000-0000-0000-000000000003' AND ct.ended_at IS NULL),'other tournament untouched');
SELECT pg_temp.assert((SELECT team_id='f1000000-0000-0000-0000-000000000002' FROM public.team_players WHERE player_id='f2000000-0000-0000-0000-000000000003'),'catalogue untouched');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000002',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,15000000) AS failing_offer \gset
-- Inject a failure AFTER account debit, credit and ledger insertion.
RESET ROLE;
CREATE FUNCTION pg_temp.fail_contract() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected storage failure' USING ERRCODE='ZX001'; END $$;
CREATE TRIGGER injected_failure BEFORE INSERT ON game.contracts FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_contract();
SET LOCAL ROLE service_role;
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,%L)',:'code','b4000000-0000-0000-0000-000000000003','accept',:'failing_offer'::jsonb->>'offerId'),'ZX001');
SELECT pg_temp.assert((SELECT balance=140000000 AND reserved=15000000 FROM game.accounts WHERE club_id=:'north'),'failed trade restored debit and hold');
SELECT pg_temp.assert((SELECT balance=280000000 FROM game.accounts WHERE club_id=:'south'),'failed trade restored seller credit');
SELECT pg_temp.assert((SELECT status='pending' FROM game.offers WHERE id=(:'failing_offer'::jsonb->>'offerId')::uuid),'failed acceptance restored offer');
SELECT pg_temp.assert((SELECT count(*)=1 FROM game.transfers WHERE tournament_id=:'tournament'),'failed transfer not recorded');
RESET ROLE;
DROP TRIGGER injected_failure ON game.contracts;
SET LOCAL ROLE service_role;
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000002',gen_random_uuid(),'cancel',NULL,(:'failing_offer'::jsonb->>'offerId')::uuid);
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000002',gen_random_uuid(),'sign','f2000000-0000-0000-0000-000000000005');
-- A free signing must also lock the player against another acquisition this session.
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L,NULL,5000000)',:'code','b4000000-0000-0000-0000-000000000003','offer','f2000000-0000-0000-0000-000000000005'),'GM001');
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b4000000-0000-0000-0000-000000000003','f2000000-0000-0000-0000-000000000005'),'GM001');
SELECT pg_temp.assert((SELECT count(*)=1 FROM game.transfers WHERE window_id=:'window' AND player_id='f2000000-0000-0000-0000-000000000005'),'blocked acquisitions leave one transfer');

SELECT pg_temp.assert((SELECT balance=128000000 AND reserved=0 FROM game.accounts WHERE club_id=:'north'),'free player price charged');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','b4000000-0000-0000-0000-000000000004','sign','f2000000-0000-0000-0000-000000000005'),'GM001');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L,NULL,129000000)',:'code','b4000000-0000-0000-0000-000000000002','offer','f2000000-0000-0000-0000-000000000004'),'GM001');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000002',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,120000000) AS holding \gset
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','b4000000-0000-0000-0000-000000000002','sign','f2000000-0000-0000-0000-000000000006'),'GM001');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000003',gen_random_uuid(),'reject',NULL,(:'holding'::jsonb->>'offerId')::uuid);
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000002',gen_random_uuid(),'sign','f2000000-0000-0000-0000-000000000006');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','b4000000-0000-0000-0000-000000000002','sign','f2000000-0000-0000-0000-000000000007'),'GM001');
SELECT pg_temp.assert((SELECT purchases_used=3 AND purchases_held=0 FROM game.market_limits WHERE window_id=:'window' AND club_id=:'north'),'purchase quota cumulative, released holds do not count');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000004',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,5000000);
SELECT pg_temp.must_fail(format('SELECT public.game_next_season(%L,%L,gen_random_uuid())',:'code','b4000000-0000-0000-0000-000000000001'),'GM001');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts WHERE tournament_id=:'tournament' AND reserved<>0),'market closure releases money');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=:'window' AND purchases_held<>0),'market closure releases held slots');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'winter',60) AS winter \gset
SELECT pg_temp.assert((SELECT purchases_used=0 FROM game.market_limits WHERE club_id=:'north' AND window_id=(:'winter'::jsonb->>'windowId')::uuid),'winter has new quota');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000003',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000005',NULL,5000000);

SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000003',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000001',NULL,5000000) AS expired_offer \gset
UPDATE game.market_windows SET opens_at=clock_timestamp()-interval '2 minutes',closes_at=clock_timestamp()-interval '1 minute' WHERE id=(:'winter'::jsonb->>'windowId')::uuid;
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,NULL,%L)',:'code','b4000000-0000-0000-0000-000000000002','accept',:'expired_offer'::jsonb->>'offerId'),'GM001');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','b4000000-0000-0000-0000-000000000002','sign','f2000000-0000-0000-0000-000000000007'),'GM001');
SELECT public.game_market_command(:'code','b4000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT pg_temp.assert((SELECT status='expired' FROM game.offers WHERE id=(:'expired_offer'::jsonb->>'offerId')::uuid),'expired holds released with history');
SELECT public.game_next_season(:'code','b4000000-0000-0000-0000-000000000001',gen_random_uuid());
SELECT pg_temp.assert((SELECT balance=118000000 FROM game.accounts WHERE club_id=:'north'),'season retains new balance');
SELECT pg_temp.assert((SELECT count(*)=3 FROM game.transfers WHERE tournament_id=:'tournament'),'season retains transfers');
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.must_fail(format('UPDATE game.accounts SET balance=balance+1 WHERE club_id=%L',:'north'),'P0001');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)),'all balances match ledger');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.ledger GROUP BY operation_id HAVING sum(amount)<>0),'all operations balanced');
RESET ROLE;
SELECT pg_temp.assert(NOT has_function_privilege('anon','public.game_market_command(text,text,uuid,text,uuid,uuid,bigint,text,integer)','EXECUTE'),'market RPC server only');
ROLLBACK;
\echo Market integration tests passed, including rollback after a financial write.
