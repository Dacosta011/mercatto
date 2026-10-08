-- Clause and negotiation commands share actor-scoped idempotency keys.
CREATE OR REPLACE FUNCTION public.game_pay_clause(p_code text,p_token text,p_key uuid,p_player uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE
  v_member uuid; v_tournament uuid; v_buyer uuid; v_seller uuid; v_window game.market_windows; v_contract game.contracts;
  v_old game.operations; v_key text; v_payload jsonb; v_now timestamptz; v_amount bigint; v_icon boolean;
  v_reserved bigint; v_held integer; v_account uuid; v_seller_account uuid; v_op uuid:=gen_random_uuid();
  v_rejected boolean; v_result jsonb; v_row record;
BEGIN
  IF p_key IS NULL OR p_player IS NULL THEN RAISE EXCEPTION 'Invalid clause request'; END IF;
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  PERFORM 1 FROM game.tournaments WHERE id=v_tournament FOR UPDATE;
  v_now:=clock_timestamp(); v_key:='market:'||v_member||':'||p_key; v_payload:=jsonb_build_object('action','clause','player',p_player,'offer',NULL,'amount',NULL,'kind',NULL,'minutes',NULL);
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  -- Preserve already committed local attempts made before the unified market namespace.
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key='clause:'||v_member||':'||p_key;
  IF FOUND THEN
    IF v_old.payload<>jsonb_build_object('player',p_player) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  SELECT club_id INTO v_buyer FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  IF v_buyer IS NULL THEN RAISE EXCEPTION 'Choose a club first' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_window FROM game.market_windows WHERE tournament_id=v_tournament AND status='open' FOR UPDATE;
  IF v_window.id IS NULL THEN RAISE EXCEPTION 'No open market' USING ERRCODE='GM001'; END IF;
  IF v_now>=v_window.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL FOR UPDATE;
  IF v_contract.id IS NULL OR v_contract.club_id=v_buyer THEN RAISE EXCEPTION 'Player has no eligible seller' USING ERRCODE='GM001'; END IF;
  v_seller:=v_contract.club_id; v_amount:=v_contract.clause;
  IF NOT EXISTS(SELECT 1 FROM game.assignments WHERE tournament_id=v_tournament AND club_id=v_seller AND ended_at IS NULL) THEN RAISE EXCEPTION 'Seller club has no manager' USING ERRCODE='GM001'; END IF;
  IF v_amount IS NULL OR v_amount<=0 THEN RAISE EXCEPTION 'Player has no valid clause' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.clause_attempts WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player) THEN RAISE EXCEPTION 'Clause already attempted in this window' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player AND kind IN('offer','clause')) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
  IF v_window.clause_protection_limit>0 AND (SELECT count(*) FROM game.transfers WHERE window_id=v_window.id AND seller_club_id=v_seller AND kind='clause')>=v_window.clause_protection_limit THEN
    RAISE EXCEPTION 'Seller clause protection reached' USING ERRCODE='GM001';
  END IF;
  -- An accepted clause replaces this buyer's pending offer for the same player.
  SELECT coalesce(sum(amount),0),count(*) INTO v_reserved,v_held FROM game.offers WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player AND status='pending';
  PERFORM 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id IN(v_buyer,v_seller) ORDER BY id FOR UPDATE;
  SELECT id INTO v_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_buyer AND balance-reserved+v_reserved>=v_amount;
  IF v_account IS NULL THEN RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001'; END IF;
  IF NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=v_window.id AND club_id=v_buyer AND purchases_used+purchases_held-v_held<purchase_limit) THEN RAISE EXCEPTION 'No purchase slots available' USING ERRCODE='GM001'; END IF;
  v_rejected:=random()<0.25;
  v_result:=jsonb_build_object('operationId',v_op,'playerId',p_player,'amount',v_amount,'rejected',v_rejected);
  INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result) VALUES(v_op,v_tournament,'market_clause',v_key,v_payload,v_result);
  INSERT INTO game.clause_attempts(tournament_id,window_id,buyer_club_id,seller_club_id,player_id,operation_id,amount,outcome)
    VALUES(v_tournament,v_window.id,v_buyer,v_seller,p_player,v_op,v_amount,CASE WHEN v_rejected THEN 'rejected' ELSE 'accepted' END);
  IF v_rejected THEN RETURN v_result; END IF;
  FOR v_row IN SELECT id FROM game.offers WHERE tournament_id=v_tournament AND player_id=p_player AND status='pending' ORDER BY id LOOP
    PERFORM game.release_offer(v_row.id,'stale');
  END LOOP;
  SELECT id INTO v_seller_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_seller;
  IF v_seller_account IS NULL THEN RAISE EXCEPTION 'Missing counterparty account'; END IF;
  UPDATE game.market_limits SET purchases_used=purchases_used+1 WHERE window_id=v_window.id AND club_id=v_buyer;
  UPDATE game.accounts SET balance=balance-v_amount WHERE id=v_account;
  UPDATE game.accounts SET balance=balance+v_amount WHERE id=v_seller_account;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES(v_tournament,v_op,v_account,-v_amount),(v_tournament,v_op,v_seller_account,v_amount);
  SELECT is_icon INTO v_icon FROM game.players WHERE tournament_id=v_tournament AND player_id=p_player;
  UPDATE game.contracts SET ended_at=v_now WHERE id=v_contract.id;
  INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause,started_at)
    VALUES(v_tournament,p_player,v_buyer,v_amount,CASE WHEN v_icon THEN round(v_amount::numeric*1.3)::bigint ELSE v_amount END,v_now);
  INSERT INTO game.transfers(tournament_id,operation_id,window_id,buyer_club_id,seller_club_id,player_id,amount,kind)
    VALUES(v_tournament,v_op,v_window.id,v_buyer,v_seller,p_player,v_amount,'clause');
  RETURN v_result;
END $$;

NOTIFY pgrst,'reload schema';
