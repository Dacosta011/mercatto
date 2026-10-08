\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.assert(p_ok boolean, p_message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %', p_message; END IF; END $$;
CREATE FUNCTION pg_temp.must_fail(p_query text, p_message text, p_state text DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN EXECUTE p_query;
  EXCEPTION WHEN OTHERS THEN
    IF p_state IS NOT NULL AND SQLSTATE <> p_state THEN RAISE; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FAILED (expected rejection): %', p_message;
END $$;

-- Synthetic catalogue, members and tournaments disappear with the final rollback.
INSERT INTO public.teams(id,name) VALUES
 ('10000000-0000-0000-0000-000000000001','__test_club_one'),
 ('10000000-0000-0000-0000-000000000002','__test_club_two');
INSERT INTO public.players(id,name,ovr,position,price,clause) VALUES
 ('20000000-0000-0000-0000-000000000001','__test_player',80,'ST',100,200);
INSERT INTO public.team_players(team_id,player_id) VALUES
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001');
INSERT INTO public.tournaments(id,name,code,admin_token_hash) VALUES
 ('30000000-0000-0000-0000-000000000001','__test_A','__test_A','test'),
 ('30000000-0000-0000-0000-000000000002','__test_B','__test_B','test');
INSERT INTO public.members(id,tournament_id,display_name,member_token_hash) VALUES
 ('40000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','one','test'),
 ('40000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000001','two','test'),
 ('40000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000002','three','test');
SELECT game.initialize('30000000-0000-0000-0000-000000000001',1000);
SELECT game.initialize('30000000-0000-0000-0000-000000000002',1000);
SELECT game.initialize('30000000-0000-0000-0000-000000000001',1000);
SELECT pg_temp.assert((SELECT count(*)=1 FROM game.operations WHERE tournament_id='30000000-0000-0000-0000-000000000001' AND kind='opening'), 'initialization retry');
SELECT pg_temp.must_fail($q$SELECT game.initialize('30000000-0000-0000-0000-000000000001',2000)$q$, 'changed initialization');

SELECT id AS club_a FROM game.clubs WHERE tournament_id='30000000-0000-0000-0000-000000000001' AND team_id='10000000-0000-0000-0000-000000000001' \gset
SELECT id AS club_b FROM game.clubs WHERE tournament_id='30000000-0000-0000-0000-000000000002' AND team_id='10000000-0000-0000-0000-000000000001' \gset
SELECT id AS club_a2 FROM game.clubs WHERE tournament_id='30000000-0000-0000-0000-000000000001' AND team_id='10000000-0000-0000-0000-000000000002' \gset
SELECT game.assign_club('30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001', :'club_a','choose-one') AS assignment \gset
SELECT pg_temp.assert(game.assign_club('30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001', :'club_a','choose-one')=:'assignment','assignment retry');
SELECT pg_temp.must_fail(format('SELECT game.assign_club(%L,%L,%L,%L)','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000003', :'club_a','cross-member'), 'cross tournament member');
SELECT pg_temp.must_fail(format('SELECT game.assign_club(%L,%L,%L,%L)','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001', :'club_b','cross-club'), 'cross tournament club');
SELECT pg_temp.must_fail(format('SELECT game.assign_club(%L,%L,%L,%L)','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002', :'club_a','taken'), 'occupied club');
SELECT pg_temp.must_fail(format('SELECT game.assign_club(%L,%L,%L,%L)','30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000001', :'club_a2','choose-one'), 'changed idempotency payload');

-- Simulate a contract move. This tests storage invariants, not a market business RPC.
UPDATE game.contracts SET ended_at=clock_timestamp() WHERE tournament_id='30000000-0000-0000-0000-000000000001' AND player_id='20000000-0000-0000-0000-000000000001';
INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause)
 VALUES('30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',:'club_a2',150,300);
SELECT pg_temp.assert((SELECT club_id=:'club_b' FROM game.contracts WHERE tournament_id='30000000-0000-0000-0000-000000000002' AND player_id='20000000-0000-0000-0000-000000000001' AND ended_at IS NULL),'tournament B ownership unchanged');
SELECT pg_temp.assert((SELECT team_id='10000000-0000-0000-0000-000000000001' FROM public.team_players WHERE player_id='20000000-0000-0000-0000-000000000001'),'catalogue unchanged');
SELECT pg_temp.must_fail(format('INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price) VALUES(%L,%L,%L,0)','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',:'club_a'),'duplicate ownership','23505');
SELECT pg_temp.must_fail(format('INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,ended_at) VALUES(%L,%L,%L,0,clock_timestamp())','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',:'club_b'),'cross tournament contract','23503');
SELECT pg_temp.must_fail(format('UPDATE game.accounts SET balance=-1 WHERE club_id=%L',:'club_a'),'negative spendable balance','23514');
SELECT pg_temp.must_fail(format('UPDATE game.accounts SET reserved=1001 WHERE club_id=%L',:'club_a'),'oversubscribed reservations','23514');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.operations o JOIN game.ledger l ON l.operation_id=o.id GROUP BY o.id HAVING sum(l.amount)<>0),'balanced opening ledger');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)),'balances equal ledger');
SELECT pg_temp.must_fail('UPDATE game.ledger SET amount=42','immutable ledger');
SELECT pg_temp.must_fail('DELETE FROM game.operations','immutable operations');
-- Force deferred constraints now, so rollback does not mask an invalid ledger.
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.must_fail(format('INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) SELECT tournament_id,gen_random_uuid(),id,1 FROM game.accounts WHERE club_id=%L',:'club_a'),'ledger foreign key');
DO $$ DECLARE v_op uuid; v_account uuid; BEGIN
  BEGIN
    INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES('30000000-0000-0000-0000-000000000001','test','unbalanced','{}','{}') RETURNING id INTO v_op;
    SELECT id INTO v_account FROM game.accounts WHERE tournament_id='30000000-0000-0000-0000-000000000001' LIMIT 1;
    INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES('30000000-0000-0000-0000-000000000001',v_op,v_account,1);
  EXCEPTION WHEN raise_exception THEN RETURN;
  END;
  RAISE EXCEPTION 'FAILED: unbalanced ledger accepted';
END $$;

SELECT game.advance_season('30000000-0000-0000-0000-000000000001','next-one') AS season \gset
SELECT pg_temp.assert(game.advance_season('30000000-0000-0000-0000-000000000001','next-one')=:'season','season retry');
SELECT game.assign_club('30000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000002',:'club_a','new-manager');
SELECT pg_temp.assert((SELECT balance=1000 FROM game.accounts WHERE club_id=:'club_a'),'club budget survives new manager');
SELECT pg_temp.assert((SELECT club_id=:'club_a2' FROM game.contracts WHERE tournament_id='30000000-0000-0000-0000-000000000001' AND player_id='20000000-0000-0000-0000-000000000001' AND ended_at IS NULL),'squad survives season');
SELECT pg_temp.assert((SELECT count(*)=1 FROM game.assignments WHERE id=:'assignment' AND ended_at IS NOT NULL),'assignment history retained');
SELECT pg_temp.must_fail($q$DELETE FROM public.members WHERE id='40000000-0000-0000-0000-000000000001'$q$,'historical member deletion');
UPDATE public.players SET name='__test_changed',price=999 WHERE id='20000000-0000-0000-0000-000000000001';
SELECT pg_temp.assert((SELECT name='__test_player' AND reference_price=100 FROM game.players WHERE tournament_id='30000000-0000-0000-0000-000000000001' AND player_id='20000000-0000-0000-0000-000000000001'),'catalogue updates do not change snapshot');
SELECT pg_temp.assert(NOT has_schema_privilege('anon','game','USAGE') AND NOT has_schema_privilege('authenticated','game','USAGE'),'browser cannot access private schema');
SELECT pg_temp.assert(NOT has_function_privilege('anon','game.initialize(uuid,bigint)','EXECUTE'),'browser cannot execute mutations');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM pg_tables WHERE schemaname='game' AND NOT rowsecurity),'all new tables use RLS');
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo Foundation integration tests passed; test fixtures rolled back.
