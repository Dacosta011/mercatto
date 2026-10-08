\set ON_ERROR_STOP on
BEGIN;
CREATE FUNCTION pg_temp.assert(p_ok boolean,p_message text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAILED: %',p_message; END IF; END $$;
CREATE FUNCTION pg_temp.must_fail(p_query text,p_state text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 BEGIN EXECUTE p_query; EXCEPTION WHEN OTHERS THEN IF SQLSTATE<>p_state THEN RAISE; END IF;RETURN;END;
 RAISE EXCEPTION 'FAILED: expected rejection %',p_state;
END $$;
-- CATALOG_FIXTURES
INSERT INTO public.players(id,name,ovr,position,price,clause,is_icon) VALUES('f3000000-0000-0000-0000-000000000003','Unsold icon',90,'ST',10000000,13000000,true);
SELECT public.game_create_tournament(gen_random_uuid(),'Auctions','North','b7000000-0000-0000-0000-000000000001','b7000000-0000-0000-0000-000000000002',
 ARRAY['f1000000-0000-0000-0000-000000000001','f1000000-0000-0000-0000-000000000002','f1000000-0000-0000-0000-000000000003']::uuid[],
 ARRAY['f2000000-0000-0000-0000-000000000005','f3000000-0000-0000-0000-000000000001','f3000000-0000-0000-0000-000000000002','f3000000-0000-0000-0000-000000000003']::uuid[]) AS created \gset
SELECT :'created'::jsonb->>'id' AS tournament,:'created'::jsonb->>'code' AS code \gset
SELECT id AS north FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000001' \gset
SELECT id AS south FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000002' \gset
SELECT id AS reserve FROM game.clubs WHERE tournament_id=:'tournament' AND team_id='f1000000-0000-0000-0000-000000000003' \gset
SELECT public.game_join_tournament(:'code','South','b7000000-0000-0000-0000-000000000003',gen_random_uuid());
SELECT public.game_join_tournament(:'code','Reserve','b7000000-0000-0000-0000-000000000004',gen_random_uuid());
SELECT public.game_choose_club(:'code','b7000000-0000-0000-0000-000000000002',:'north',gen_random_uuid());
SELECT public.game_choose_club(:'code','b7000000-0000-0000-0000-000000000003',:'south',gen_random_uuid());
SELECT public.game_choose_club(:'code','b7000000-0000-0000-0000-000000000004',:'reserve',gen_random_uuid());
UPDATE public.tournaments SET max_transfers=1 WHERE id=:'tournament';
SET LOCAL ROLE service_role;
SELECT public.game_market_command(:'code','b7000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'summer',60) AS opened \gset
SELECT :'opened'::jsonb->>'windowId' AS window \gset
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,%L,NULL,NULL,10)',:'code','b7000000-0000-0000-0000-000000000002','auction_open','f3000000-0000-0000-0000-000000000001'),'28000');
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,%L,NULL,NULL,10)',:'code','b7000000-0000-0000-0000-000000000001','auction_open','f2000000-0000-0000-0000-000000000005'),'GM001');
SELECT gen_random_uuid() AS open_key \gset
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000001',:'open_key','auction_open','f3000000-0000-0000-0000-000000000001',NULL,NULL,10) AS auction_result \gset
SELECT :'auction_result'::jsonb->>'auctionId' AS auction \gset
SELECT pg_temp.assert(public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000001',:'open_key','auction_open','f3000000-0000-0000-0000-000000000001',NULL,NULL,10)=:'auction_result'::jsonb,'auction creation replay');
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,%L,NULL,NULL,10)',:'code','b7000000-0000-0000-0000-000000000001','auction_open','f3000000-0000-0000-0000-000000000002'),'GM001');
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L)',:'code','b7000000-0000-0000-0000-000000000002','sign','f3000000-0000-0000-0000-000000000001'),'GM001');
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,NULL,%L,29000000)',:'code','b7000000-0000-0000-0000-000000000002','auction_bid',:'auction'),'GM001');
SELECT gen_random_uuid() AS bid_key \gset
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000002',:'bid_key','auction_bid',NULL,:'auction',30000000) AS bid \gset
SELECT pg_temp.assert(public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000002',:'bid_key','auction_bid',NULL,:'auction',30000000)=:'bid'::jsonb,'bid replay');
SELECT pg_temp.assert((SELECT balance=160000000 AND reserved=30000000 FROM game.accounts WHERE club_id=:'north'),'winning bid reserves without paying');
SELECT pg_temp.assert((SELECT icons_held=1 AND icons_used=0 AND purchases_used=0 AND purchases_held=0 FROM game.market_limits WHERE window_id=:'window' AND club_id=:'north'),'independent icon hold');
SELECT pg_temp.assert((SELECT count(*)=1 FROM game.auction_bids WHERE auction_id=:'auction'),'bid replay records once');
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,NULL,%L,35000000)',:'code','b7000000-0000-0000-0000-000000000002','auction_bid',:'auction'),'GM001');
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000003',gen_random_uuid(),'auction_bid',NULL,:'auction',35000000);
SELECT pg_temp.assert((SELECT reserved=0 FROM game.accounts WHERE club_id=:'north'),'outbid club money released');
SELECT pg_temp.assert((SELECT icons_held=0 FROM game.market_limits WHERE window_id=:'window' AND club_id=:'north'),'outbid icon slot released');
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,NULL,%L,161000000)',:'code','b7000000-0000-0000-0000-000000000002','auction_bid',:'auction'),'GM001');
-- A failed bid write after changing reservations must roll the complete bid back.
RESET ROLE;
CREATE FUNCTION pg_temp.fail_bid() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected bid failure' USING ERRCODE='ZX001'; END $$;
CREATE TRIGGER injected_bid_failure BEFORE INSERT ON game.auction_bids FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_bid();
SET LOCAL ROLE service_role;
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,NULL,%L,40000000)',:'code','b7000000-0000-0000-0000-000000000004','auction_bid',:'auction'),'ZX001');
SELECT pg_temp.assert((SELECT reserved=35000000 FROM game.accounts WHERE club_id=:'south'),'failed outbid restores previous leader hold');
SELECT pg_temp.assert((SELECT reserved=0 FROM game.accounts WHERE club_id=:'reserve'),'failed outbid restores challenger');
RESET ROLE;DROP TRIGGER injected_bid_failure ON game.auction_bids;SET LOCAL ROLE service_role;
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000004',gen_random_uuid(),'auction_bid',NULL,:'auction',40000000);
SELECT pg_temp.must_fail(format('SELECT public.game_market_command(%L,%L,gen_random_uuid(),%L,%L,NULL,70000000)',:'code','b7000000-0000-0000-0000-000000000004','offer','f2000000-0000-0000-0000-000000000004'),'GM001');
SELECT public.game_market_command(:'code','b7000000-0000-0000-0000-000000000002',gen_random_uuid(),'offer','f2000000-0000-0000-0000-000000000004',NULL,150000000) AS held_offer \gset
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,NULL,%L,45000000)',:'code','b7000000-0000-0000-0000-000000000002','auction_bid',:'auction'),'GM001');
SELECT public.game_market_command(:'code','b7000000-0000-0000-0000-000000000002',gen_random_uuid(),'cancel',NULL,(:'held_offer'::jsonb->>'offerId')::uuid);
UPDATE game.auctions SET ends_at=clock_timestamp()+interval '30 seconds' WHERE id=:'auction';
UPDATE game.market_windows SET closes_at=clock_timestamp()+interval '90 seconds' WHERE id=:'window';
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000002',gen_random_uuid(),'auction_bid',NULL,:'auction',45000000);
SELECT pg_temp.assert((SELECT a.ends_at=w.closes_at AND a.ends_at>clock_timestamp()+interval '60 seconds' FROM game.auctions a JOIN game.market_windows w ON w.id=a.window_id WHERE a.id=:'auction'),'antisnipe extension capped at market deadline');
UPDATE game.market_windows SET closes_at=clock_timestamp()+interval '60 minutes' WHERE id=:'window';
SELECT pg_temp.assert(public.game_expire_markets()->>'settled'='0','worker leaves future auction untouched');
UPDATE game.auctions SET starts_at=clock_timestamp()-interval '2 minutes',ends_at=clock_timestamp()-interval '1 second' WHERE id=:'auction';
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,NULL,%L,50000000)',:'code','b7000000-0000-0000-0000-000000000003','auction_bid',:'auction'),'GM001');
RESET ROLE;
CREATE FUNCTION pg_temp.fail_auction_contract() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Injected auction settlement failure' USING ERRCODE='ZX001'; END $$;
CREATE TRIGGER injected_auction_failure BEFORE INSERT ON game.contracts FOR EACH ROW EXECUTE FUNCTION pg_temp.fail_auction_contract();
SET LOCAL ROLE service_role;
SELECT pg_temp.must_fail('SELECT public.game_expire_markets()','ZX001');
SELECT pg_temp.assert((SELECT balance=160000000 AND reserved=45000000 FROM game.accounts WHERE club_id=:'north'),'failed settlement restores balance and reservation');
SELECT pg_temp.assert((SELECT status='active' FROM game.auctions WHERE id=:'auction'),'failed settlement restores auction');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.operations WHERE tournament_id=:'tournament' AND idempotency_key='auction-settle:'||:'auction'),'failed settlement leaves no completed operation');
RESET ROLE;DROP TRIGGER injected_auction_failure ON game.contracts;SET LOCAL ROLE service_role;
SELECT pg_temp.assert(public.game_expire_markets()->>'settled'='1','worker adjudicates expired auction');
SELECT pg_temp.assert(public.game_expire_markets()->>'settled'='0','worker replay does not settle twice');
SELECT pg_temp.assert((SELECT balance=115000000 AND reserved=0 FROM game.accounts WHERE club_id=:'north'),'winner charged final bid once');
SELECT pg_temp.assert((SELECT acquired_price=45000000 AND clause=58500000 AND club_id=:'north' FROM game.contracts WHERE tournament_id=:'tournament' AND player_id='f3000000-0000-0000-0000-000000000001' AND ended_at IS NULL),'owned icon gets 130 percent clause');
SELECT pg_temp.assert((SELECT icons_used=1 AND icons_held=0 AND purchases_used=0 FROM game.market_limits WHERE window_id=:'window' AND club_id=:'north'),'auction does not consume ordinary purchase slot');
SELECT pg_temp.assert((SELECT clause=39000000 AND price=30000000 FROM public.players WHERE id='f3000000-0000-0000-0000-000000000001'),'global icon catalogue unchanged');
SELECT public.game_market_command(:'code','b7000000-0000-0000-0000-000000000004',gen_random_uuid(),'sign','f2000000-0000-0000-0000-000000000005');
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000001',gen_random_uuid(),'auction_open','f3000000-0000-0000-0000-000000000002',NULL,NULL,10) AS second \gset
SELECT :'second'::jsonb->>'auctionId' AS second_id \gset
SELECT pg_temp.must_fail(format('SELECT public.game_auction_command(%L,%L,gen_random_uuid(),%L,NULL,%L,35000000)',:'code','b7000000-0000-0000-0000-000000000002','auction_bid',:'second_id'),'GM001');
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000004',gen_random_uuid(),'auction_bid',NULL,:'second_id',35000000);
SELECT public.game_market_command(:'code','b7000000-0000-0000-0000-000000000001',gen_random_uuid(),'close');
SELECT pg_temp.assert((SELECT balance=53000000 AND reserved=0 FROM game.accounts WHERE club_id=:'reserve'),'manual market close settles leader');
SELECT pg_temp.assert((SELECT icons_used=1 AND purchases_used=1 FROM game.market_limits WHERE window_id=:'window' AND club_id=:'reserve'),'full normal quota permits independent icon purchase');
SELECT public.game_market_command(:'code','b7000000-0000-0000-0000-000000000001',gen_random_uuid(),'open',NULL,NULL,NULL,'winter',60) AS winter \gset
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=(:'winter'::jsonb->>'windowId')::uuid AND icons_used+icons_held<>0),'new window resets icon quota');
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000001',gen_random_uuid(),'auction_open','f3000000-0000-0000-0000-000000000003',NULL,NULL,10) AS unsold \gset
UPDATE game.auctions SET starts_at=clock_timestamp()-interval '2 minutes',ends_at=clock_timestamp()-interval '1 second' WHERE id=(:'unsold'::jsonb->>'auctionId')::uuid;
SELECT pg_temp.assert(public.game_expire_markets()->>'settled'='1','unsold auction also closes automatically');
SELECT pg_temp.assert((SELECT status='unsold' FROM game.auctions WHERE id=(:'unsold'::jsonb->>'auctionId')::uuid),'no-bid auction retains history without ownership');
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000001',gen_random_uuid(),'auction_open','f3000000-0000-0000-0000-000000000003',NULL,NULL,10) AS final_auction \gset
SELECT public.game_auction_command(:'code','b7000000-0000-0000-0000-000000000003',gen_random_uuid(),'auction_bid',NULL,(:'final_auction'::jsonb->>'auctionId')::uuid,10000000);
UPDATE game.market_windows SET opens_at=clock_timestamp()-interval '2 minutes',closes_at=clock_timestamp()-interval '1 second' WHERE id=(:'winter'::jsonb->>'windowId')::uuid;
SELECT public.game_expire_markets() AS expired_market \gset
SELECT pg_temp.assert(:'expired_market'::jsonb->>'closed'='1' AND :'expired_market'::jsonb->>'settled'='1','market expiry settles and closes in one transaction');
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts WHERE tournament_id=:'tournament' AND reserved<>0),'closure leaves no auction or offer holds');
SELECT pg_temp.assert((SELECT count(*)=3 FROM game.transfers WHERE tournament_id=:'tournament' AND kind='icon_auction'),'one transfer per adjudication');
SELECT pg_temp.assert(jsonb_array_length(public.game_market_state(:'code','b7000000-0000-0000-0000-000000000002')->'auctions')=4,'snapshot keeps auction history');
SET CONSTRAINTS ALL IMMEDIATE;
SELECT pg_temp.assert(NOT EXISTS(SELECT 1 FROM game.accounts a LEFT JOIN game.ledger l ON l.account_id=a.id GROUP BY a.id,a.balance HAVING a.balance<>coalesce(sum(l.amount),0)),'auction balances reconcile');
RESET ROLE;
SELECT pg_temp.must_fail(format('UPDATE game.auction_bids SET amount=1 WHERE auction_id=%L',:'auction'),'P0001');
SELECT pg_temp.must_fail(format('UPDATE game.auctions SET highest_bid=1 WHERE id=%L',:'auction'),'P0001');
SELECT pg_temp.assert(NOT has_function_privilege('anon','public.game_auction_command(text,text,uuid,text,uuid,uuid,bigint,integer)','EXECUTE'),'auction RPC private');
ROLLBACK;
\echo Auction tests passed: reserves, quotas, antisnipe, rollback, automatic/manual settlement and history.
