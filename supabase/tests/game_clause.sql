\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.assert(p_ok boolean,p_message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',p_message; END IF; END $$;
CREATE FUNCTION pg_temp.must_fail(p_query text,p_state text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_query; EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>p_state THEN RAISE; END IF; RETURN; END;
 RAISE EXCEPTION 'FAILED: expected rejection %',p_state;
END $$;
-- Test-only deterministic PRNG seed. The public command exposes no roll or seed argument.
CREATE FUNCTION pg_temp.seed_clause(p_rejected boolean) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n integer; s double precision;
BEGIN
 FOR n IN 0..100 LOOP
  s:=n::double precision/100; PERFORM setseed(s);
  IF (random()<0.25)=p_rejected THEN PERFORM setseed(s); RETURN; END IF;
 END LOOP;
 RAISE EXCEPTION 'No deterministic seed found';
END $$;
-- CATALOG_FIXTURES
SELECT public.game_create_tournament(gen_random_uuid(),'Clauses','Buyer','b6000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],ARRAY['f2000000-0000-0000-0000-000000000005']::uuid[]) AS created \gset
SELECT :'created'::jsonb->>'code' AS code, :'created'::jsonb->>'id' AS tournament \gset
SELECT id AS north FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000001' \gset
SELECT id AS south FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000002' \gset
SELECT id AS reserve FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000003' \gset
SELECT public.game_join_tournament(:'code','Seller','b6000000-0000-0000-0000-000000000003',gen_random_uuid());
SELECT public.game_join_tournament(:'code','Rival','b6000000-0000-0000-0000-000000000004',gen_random_uuid());
SELECT public.game_choose_club(:'code','b6000000-0000-0000-0000-000000000002',:'north',gen_random_uuid());
SELECT public.game_choose_club(:'code','b6000000-0000-0000-0000-000000000003',:'south',gen_random_uuid());
SELECT public.game_choose_club(:'code','b6000000-0000-0000-0000-000000000004',:'reserve',gen_random_uuid());
UPDATE public.tournaments SET max_transfers=1 WHERE id=:'tournament';
SET LOCAL ROLE service_role;
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000001','f2000000-0000-0000-0000-000000000004'),'28000');
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60) AS summer \gset
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000001'),'GM001');
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000005'),'GM001');
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000002',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,140000000);
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000004',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,10000000);
SELECT pg_temp.seed_clause(true);
SELECT gen_random_uuid() AS rejected_key \gset
SELECT public.game_pay_clause(:'code','b6000000-0000-0000-0000-000000000002',:'rejected_key','f2000000-0000-0000-0000-000000000004') AS rejected \gset
SELECT pg_temp.assert((:'rejected'::jsonb->>'rejected')::boolean,'deterministic rejection');
SELECT pg_temp.assert(public.game_pay_clause(:'code','b6000000-0000-0000-0000-000000000002',:'rejected_key','f2000000-0000-0000-0000-000000000004')=:'rejected'::jsonb,'rejection replay does not reroll');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,%L,%L,%L,NULL,1000000)',:'code','b6000000-0000-0000-0000-000000000002',:'rejected_key','offer','f2000000-0000-0000-0000-000000000003'),'P0001');
SELECT pg_temp.assert((SELECT balance=160000000 AND reserved=140000000 FROM game.accounts WHERE club_id=:'north'),'rejected clause leaves existing hold and money');
SELECT pg_temp.assert((SELECT purchases_used=0 AND purchases_held=1 FROM game.market_limits WHERE club_id=:'north' AND window_id=(:'summer'::jsonb->>'windowId')::uuid),'rejection consumes no quota');
SELECT pg_temp.assert((SELECT count(*)=1 FROM game.clause_attempts WHERE tournament_id=:'tournament'),'rejected retry records one attempt');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.ledger WHERE operation_id=(:'rejected'::jsonb->>'operationId')::uuid),'rejection creates no money movement');
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000004'),'GM001');
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'winter',60) AS winter \gset
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000002',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,140000000);
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000004',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,10000000);
RESET ROLE;
CREATE FUNCTION pg_temp.fail_clause_contract() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected clause failure' USING ERRCODE='ZX001'; END $$;
CREATE TRIGGER injected_clause_failure BEFORE INSERT ON game.contracts FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_clause_contract();
SET LOCAL ROLE service_role;
SELECT pg_temp.seed_clause(false);
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000004'),'ZX001');
SELECT pg_temp.assert((SELECT balance=160000000 AND reserved=140000000 FROM game.accounts WHERE club_id=:'north'),'late clause failure restores buyer and hold');
SELECT pg_temp.assert((SELECT balance=260000000 FROM game.accounts WHERE club_id=:'south'),'late clause failure restores seller');
SELECT pg_temp.assert((SELECT reserved=10000000 FROM game.accounts WHERE club_id=:'reserve'),'late clause failure restores rival hold');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.clause_attempts WHERE window_id=(:'winter'::jsonb->>'windowId')::uuid),'failure leaves no attempt or random outcome');
RESET ROLE;
DROP TRIGGER injected_clause_failure ON game.contracts;
SET LOCAL ROLE service_role;
SELECT pg_temp.seed_clause(false);
SELECT gen_random_uuid() AS accepted_key \gset
SELECT public.game_pay_clause(:'code','b6000000-0000-0000-0000-000000000002',:'accepted_key','f2000000-0000-0000-0000-000000000004') AS accepted \gset
SELECT pg_temp.assert(NOT (:'accepted'::jsonb->>'rejected')::boolean,'deterministic acceptance in new window');
SELECT pg_temp.assert(public.game_pay_clause(:'code','b6000000-0000-0000-0000-000000000002',:'accepted_key','f2000000-0000-0000-0000-000000000004')=:'accepted'::jsonb,'accepted retry pays once');
SELECT pg_temp.assert((SELECT balance=130000000 AND reserved=0 FROM game.accounts WHERE club_id=:'north'),'server contract clause paid, replaces own hold');
SELECT pg_temp.assert((SELECT balance=290000000 FROM game.accounts WHERE club_id=:'south'),'seller paid current clause');
SELECT pg_temp.assert((SELECT reserved=0 FROM game.accounts WHERE club_id=:'reserve'),'rival hold released');
SELECT pg_temp.assert((SELECT purchases_used=1 AND purchases_held=0 FROM game.market_limits WHERE club_id=:'north' AND window_id=(:'winter'::jsonb->>'windowId')::uuid),'held offer replaced by one clause purchase');
SELECT pg_temp.assert((SELECT club_id=:'north' AND acquired_price=30000000 AND clause=30000000 FROM game.contracts WHERE tournament_id=:'tournament' AND player_id='f2000000-0000-0000-0000-000000000004' AND ended_at IS NULL),'new contract records clause payment');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L,NULL,1000000)',:'code','b6000000-0000-0000-0000-000000000004','offer','f2000000-0000-0000-0000-000000000004'),'GM001');
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000004'),'GM001');
UPDATE public.tournaments SET clause_protection_limit=0,max_transfers=3 WHERE id=:'tournament';
SELECT pg_temp.assert((SELECT clause_protection_limit=1 FROM game.market_windows WHERE id=(:'winter'::jsonb->>'windowId')::uuid),'active window rules do not change');
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000003'),'GM001');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','b6000000-0000-0000-0000-000000000002','sign','f2000000-0000-0000-0000-000000000005'),'GM001');
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT public.game_market_command(:'code','b6000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60) AS next_window \gset
SELECT pg_temp.assert((SELECT clause_protection_limit=0 AND purchase_limit=3 FROM game.market_windows WHERE id=(:'next_window'::jsonb->>'windowId')::uuid),'new window snapshots changed settings');
-- A future auction's owned icon uses its own tournament contract, never the global catalogue.
UPDATE game.players SET is_icon=true WHERE tournament_id=:'tournament' AND player_id='f2000000-0000-0000-0000-000000000001';
SELECT pg_temp.seed_clause(false);
SELECT public.game_pay_clause(:'code','b6000000-0000-0000-0000-000000000004',gen_random_uuid(),'f2000000-0000-0000-0000-000000000001');
SELECT pg_temp.assert((SELECT acquired_price=80000000 AND clause=104000000 AND club_id=:'reserve' FROM game.contracts WHERE tournament_id=:'tournament' AND player_id='f2000000-0000-0000-0000-000000000001' AND ended_at IS NULL),'icon clause rises 30 percent only in acquired contract');
SELECT pg_temp.assert((SELECT price=40000000 AND clause=80000000 FROM public.players WHERE id='f2000000-0000-0000-0000-000000000001'),'global catalogue unchanged');
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000004','f2000000-0000-0000-0000-000000000002'),'GM001');
SELECT pg_temp.assert((SELECT count(*)=3 FROM game.clause_attempts WHERE tournament_id=:'tournament'),'insufficient funds do not record an attempt');
UPDATE game.market_windows SET opens_at=clock_timestamp()-interval '2 minutes',closes_at=clock_timestamp()-interval '1 minute' WHERE id=(:'next_window'::jsonb->>'windowId')::uuid;
SELECT pg_temp.must_fail(format('SELECT public.game_pay_clause(%L,%L,gen_random_uuid(),%L)',:'code','b6000000-0000-0000-0000-000000000002','f2000000-0000-0000-0000-000000000003'),'GM001');
-- A committed attempt in the previous migration's format must remain replayable after expiration.
SELECT gen_random_uuid() AS legacy_key,gen_random_uuid() AS legacy_op \gset
SELECT jsonb_build_object('operationId',:'legacy_op','playerId','f2000000-0000-0000-0000-000000000003','amount',20000000,'rejected',true) AS legacy_result \gset
INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result)
 VALUES(:'legacy_op',:'tournament','market_clause','clause:'||(SELECT member_id::text FROM game.assignments WHERE club_id=:'reserve' AND ended_at IS NULL)||':'||:'legacy_key',jsonb_build_object('player','f2000000-0000-0000-0000-000000000003'),:'legacy_result'::jsonb);
INSERT INTO game.clause_attempts(tournament_id,window_id,buyer_club_id,seller_club_id,player_id,operation_id,amount,outcome)
 VALUES(:'tournament',(:'next_window'::jsonb->>'windowId')::uuid,:'reserve',:'south','f2000000-0000-0000-0000-000000000003',:'legacy_op',20000000,'rejected');
SELECT pg_temp.assert(public.game_pay_clause(:'code','b6000000-0000-0000-0000-000000000004',:'legacy_key','f2000000-0000-0000-0000-000000000003')=:'legacy_result'::jsonb,'legacy key replay preserves recorded outcome after expiration');
SELECT pg_temp.must_fail(format('UPDATE game.clause_attempts SET amount=1 WHERE tournament_id=%L',:'tournament'),'42501');
SELECT pg_temp.assert(jsonb_array_length(public.game_market_state(:'code','b6000000-0000-0000-0000-000000000002')->'clauseAttempts')=4,'snapshot exposes attempts');
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)),'clause balances reconcile');
RESET ROLE;
SELECT pg_temp.must_fail(format('DELETE FROM game.clause_attempts WHERE tournament_id=%L',:'tournament'),'P0001');
SELECT pg_temp.assert(NOT has_function_privilege('anon','public.game_pay_clause(text,text,uuid,uuid)','EXECUTE'),'clause command server only');
ROLLBACK;
\echo Clause tests passed: rejection/replay, hold replacement, quotas, protection, rollback and private icon clause.
