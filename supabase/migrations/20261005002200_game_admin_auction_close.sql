-- Preserve the original administrator's End Auction action, with audited settlement.
CREATE OR REPLACE FUNCTION game.settle_auction(p_auction uuid,p_reason text DEFAULT 'deadline') RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a game.auctions;w game.market_windows;v_op uuid:=gen_random_uuid();v_result jsonb;v_account uuid;v_clearing uuid;v_now timestamptz;
BEGIN
  SELECT * INTO a FROM game.auctions WHERE id=p_auction;
  IF NOT FOUND THEN RAISE EXCEPTION 'Auction not found' USING ERRCODE='GM001'; END IF;
  PERFORM 1 FROM game.tournaments WHERE id=a.tournament_id FOR UPDATE;
  SELECT * INTO a FROM game.auctions WHERE id=p_auction FOR UPDATE;
  IF a.status<>'active' THEN SELECT result INTO v_result FROM game.operations WHERE tournament_id=a.tournament_id AND idempotency_key='auction-settle:'||a.id; RETURN v_result; END IF;
  v_now:=clock_timestamp();SELECT * INTO w FROM game.market_windows WHERE id=a.window_id FOR UPDATE;
  IF p_reason IS NULL OR p_reason NOT IN('deadline','market_close','admin_close') THEN RAISE EXCEPTION 'Invalid settlement reason'; END IF;
  IF p_reason='deadline' AND v_now<least(a.ends_at,w.closes_at) THEN RAISE EXCEPTION 'Auction deadline not reached' USING ERRCODE='GM001'; END IF;
  v_result:=jsonb_build_object('auctionId',a.id,'winnerClubId',a.highest_club_id,'amount',a.highest_bid,'reason',p_reason);
  INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result)
    VALUES(v_op,a.tournament_id,'icon_auction','auction-settle:'||a.id,jsonb_build_object('auction',a.id),v_result);
  IF a.highest_club_id IS NOT NULL THEN
    IF EXISTS(SELECT 1 FROM game.contracts WHERE tournament_id=a.tournament_id AND player_id=a.player_id AND ended_at IS NULL) THEN RAISE EXCEPTION 'Auction player is no longer free' USING ERRCODE='GM001'; END IF;
    PERFORM 1 FROM game.accounts WHERE tournament_id=a.tournament_id AND (club_id=a.highest_club_id OR club_id IS NULL) ORDER BY id FOR UPDATE;
    SELECT id INTO v_account FROM game.accounts WHERE tournament_id=a.tournament_id AND club_id=a.highest_club_id AND reserved>=a.highest_bid AND balance>=a.highest_bid;
    IF v_account IS NULL THEN RAISE EXCEPTION 'Missing auction reservation'; END IF;
    SELECT id INTO v_clearing FROM game.accounts WHERE tournament_id=a.tournament_id AND club_id IS NULL;
    IF v_clearing IS NULL THEN RAISE EXCEPTION 'Missing counterparty account'; END IF;
    UPDATE game.accounts SET reserved=reserved-a.highest_bid,balance=balance-a.highest_bid WHERE id=v_account;
    UPDATE game.accounts SET balance=balance+a.highest_bid WHERE id=v_clearing;
    UPDATE game.market_limits SET icons_held=icons_held-1,icons_used=icons_used+1 WHERE window_id=a.window_id AND club_id=a.highest_club_id;
    INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES(a.tournament_id,v_op,v_account,-a.highest_bid),(a.tournament_id,v_op,v_clearing,a.highest_bid);
    INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause,started_at)
      VALUES(a.tournament_id,a.player_id,a.highest_club_id,a.highest_bid,round(a.highest_bid::numeric*1.3)::bigint,v_now);
    INSERT INTO game.transfers(tournament_id,operation_id,window_id,buyer_club_id,player_id,amount,kind)
      VALUES(a.tournament_id,v_op,a.window_id,a.highest_club_id,a.player_id,a.highest_bid,'icon_auction');
  END IF;
  UPDATE game.auctions SET status=CASE WHEN highest_club_id IS NULL THEN 'unsold' ELSE 'settled' END,settled_at=v_now WHERE id=a.id;
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION game.settle_auction(uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION game.settle_auction(uuid,text) TO service_role;


CREATE FUNCTION public.game_ui_end_auction(p_code text,p_token text,p_key uuid,p_auction uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; previous game.operations; k text; result jsonb;
BEGIN
 tid:=game.require_admin(p_code,p_token);
 IF p_key IS NULL OR p_auction IS NULL THEN RAISE EXCEPTION 'Invalid auction closure'; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 k:='ui-auction-end:'||p_key;
 SELECT * INTO previous FROM game.operations WHERE tournament_id=tid AND idempotency_key=k;
 IF FOUND THEN
  IF previous.payload<>jsonb_build_object('auctionId',p_auction) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
  RETURN previous.result;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM game.auctions WHERE tournament_id=tid AND id=p_auction) THEN RAISE EXCEPTION 'Auction not found' USING ERRCODE='GM001'; END IF;
 result:=game.settle_auction(p_auction,'admin_close');
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'ui_auction_end',k,jsonb_build_object('auctionId',p_auction),result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_ui_end_auction(text,text,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_ui_end_auction(text,text,uuid,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
