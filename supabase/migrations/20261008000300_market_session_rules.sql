-- A player can only be acquired once per market session, including free signings and icons.
CREATE OR REPLACE FUNCTION public.game_market_command_core(p_code text,p_token text,p_key uuid,p_action text,
  p_player uuid DEFAULT NULL,p_offer uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,
  p_kind text DEFAULT NULL,p_minutes integer DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE
  v_tournament uuid; v_member uuid; v_actor text; v_club uuid; v_key text; v_payload jsonb; v_old game.operations;
  v_window game.market_windows; v_offer game.offers; v_contract game.contracts; v_player game.players;
  v_season uuid; v_limit integer; v_now timestamptz; v_operation uuid:=gen_random_uuid(); v_result jsonb;
  v_trade boolean:=false; v_buyer uuid; v_seller uuid; v_amount bigint; v_clause bigint;
  v_account uuid; v_counter_account uuid; v_offer_id uuid; v_row record; v_kind text;
BEGIN
  IF p_key IS NULL OR p_action IS NULL OR p_action NOT IN('open','close','offer','accept','reject','cancel','sign','counter') THEN RAISE EXCEPTION 'Invalid market action'; END IF;
  IF p_action IN('open','close') THEN
    SELECT g.id INTO v_tournament FROM game.tournaments g JOIN public.tournaments t ON t.id=g.id
      WHERE t.code=upper(p_code) AND t.status='prototype' AND t.admin_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
    IF v_tournament IS NULL THEN RAISE EXCEPTION 'Invalid admin token' USING ERRCODE='28000'; END IF;
    v_actor:='admin';
  ELSE
    v_member:=game.require_member(p_code,p_token);
    SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
    v_actor:=v_member::text;
  END IF;
  -- Every game command serializes on this row. Clock is checked AFTER acquiring it.
  PERFORM 1 FROM game.tournaments WHERE id=v_tournament FOR UPDATE;
  v_now:=clock_timestamp();
  v_key:='market:'||v_actor||':'||p_key;
  v_payload:=jsonb_build_object('action',p_action,'player',p_player,'offer',p_offer,'amount',p_amount,'kind',p_kind,'minutes',p_minutes);
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  SELECT * INTO v_window FROM game.market_windows WHERE tournament_id=v_tournament AND status='open' FOR UPDATE;
  IF p_action='open' THEN
    IF v_window.id IS NOT NULL THEN RAISE EXCEPTION 'Close existing market first' USING ERRCODE='GM001'; END IF;
    IF p_kind IS NULL OR p_kind NOT IN('summer','winter') OR p_minutes IS NULL OR p_minutes NOT BETWEEN 1 AND 1440 THEN RAISE EXCEPTION 'Invalid market settings'; END IF;
    SELECT id INTO v_season FROM game.seasons WHERE tournament_id=v_tournament AND ended_at IS NULL;
    SELECT greatest(1,least(10,max_transfers)) INTO v_limit FROM public.tournaments WHERE id=v_tournament;
    INSERT INTO game.market_windows(tournament_id,season_id,kind,opens_at,closes_at,purchase_limit)
      VALUES(v_tournament,v_season,p_kind,v_now,v_now+make_interval(mins=>p_minutes),v_limit) RETURNING * INTO v_window;
    INSERT INTO game.market_limits(tournament_id,window_id,club_id,purchase_limit)
      SELECT v_tournament,v_window.id,id,v_limit FROM game.clubs WHERE tournament_id=v_tournament;
    v_result:=jsonb_build_object('windowId',v_window.id);
  ELSIF p_action='close' THEN
    IF v_window.id IS NULL THEN RAISE EXCEPTION 'No open market' USING ERRCODE='GM001'; END IF;
    FOR v_row IN SELECT id FROM game.auctions WHERE window_id=v_window.id AND status='active' ORDER BY id LOOP
      PERFORM game.settle_auction(v_row.id,'market_close');
    END LOOP;
    FOR v_row IN SELECT id FROM game.offers WHERE window_id=v_window.id AND status='pending' ORDER BY id LOOP
      PERFORM game.release_offer(v_row.id,CASE WHEN v_now>=v_window.closes_at THEN 'expired' ELSE 'cancelled' END);
    END LOOP;
    UPDATE game.market_windows SET status='closed',closed_at=v_now WHERE id=v_window.id;
    v_result:=jsonb_build_object('windowId',v_window.id,'closed',true);
  ELSE
    SELECT club_id INTO v_club FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
    IF v_club IS NULL THEN RAISE EXCEPTION 'Choose a club first' USING ERRCODE='GM001'; END IF;
    IF v_window.id IS NULL THEN RAISE EXCEPTION 'No open market' USING ERRCODE='GM001'; END IF;
    IF p_action IN('offer','accept','sign','counter') AND v_now>=v_window.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
    IF p_action IN('offer','sign') THEN
      SELECT * INTO v_player FROM game.players WHERE tournament_id=v_tournament AND player_id=p_player FOR UPDATE;
      IF NOT FOUND THEN RAISE EXCEPTION 'Player not in this tournament' USING ERRCODE='GM001'; END IF;
      IF v_player.is_icon THEN RAISE EXCEPTION 'Icons require an auction' USING ERRCODE='GM001'; END IF;
      IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
      SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL FOR UPDATE;
      IF p_action='offer' THEN
        IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
        IF v_contract.id IS NULL OR v_contract.club_id=v_club THEN RAISE EXCEPTION 'Player has no eligible seller' USING ERRCODE='GM001'; END IF;
        IF NOT EXISTS(SELECT 1 FROM game.assignments WHERE tournament_id=v_tournament AND club_id=v_contract.club_id AND ended_at IS NULL) THEN RAISE EXCEPTION 'Seller club has no manager' USING ERRCODE='GM001'; END IF;
        IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Invalid offer amount'; END IF;
        IF EXISTS(SELECT 1 FROM game.offers WHERE window_id=v_window.id AND buyer_club_id=v_club AND player_id=p_player AND status='pending') THEN RAISE EXCEPTION 'Offer already pending' USING ERRCODE='GM001'; END IF;
        v_amount:=p_amount;
      ELSE
        IF v_contract.id IS NOT NULL THEN RAISE EXCEPTION 'Player is no longer free' USING ERRCODE='GM001'; END IF;
        v_amount:=v_player.reference_price;
        IF v_amount<=0 THEN RAISE EXCEPTION 'Free player has no valid price' USING ERRCODE='GM001'; END IF;
        v_clause:=v_player.reference_clause;
      END IF;
      IF NOT EXISTS(SELECT 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_club AND balance-reserved>=v_amount) THEN RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001'; END IF;
      IF NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=v_window.id AND club_id=v_club AND purchases_used+purchases_held<purchase_limit) THEN RAISE EXCEPTION 'No purchase slots available' USING ERRCODE='GM001'; END IF;
      IF p_action='offer' THEN
        INSERT INTO game.offers(tournament_id,window_id,buyer_club_id,seller_club_id,player_id,amount)
          VALUES(v_tournament,v_window.id,v_club,v_contract.club_id,p_player,v_amount) RETURNING id INTO v_offer_id;
        UPDATE game.accounts SET reserved=reserved+v_amount WHERE tournament_id=v_tournament AND club_id=v_club;
        UPDATE game.market_limits SET purchases_held=purchases_held+1 WHERE window_id=v_window.id AND club_id=v_club;
        v_result:=jsonb_build_object('offerId',v_offer_id,'reserved',v_amount);
      ELSE
        v_trade:=true; v_buyer:=v_club; v_seller:=NULL; v_kind:='free';
        v_result:=jsonb_build_object('operationId',v_operation,'playerId',p_player,'amount',v_amount);
      END IF;
    ELSE
      SELECT * INTO v_offer FROM game.offers WHERE id=p_offer AND tournament_id=v_tournament AND window_id=v_window.id FOR UPDATE;
      IF NOT FOUND OR v_offer.status<>'pending' THEN RAISE EXCEPTION 'Offer is not pending in this market' USING ERRCODE='GM001'; END IF;
      IF p_action IN('accept','reject','counter') AND
        (v_club NOT IN(v_offer.buyer_club_id,v_offer.seller_club_id) OR
         v_club=coalesce(v_offer.proposed_by_club_id,v_offer.buyer_club_id)) THEN
        RAISE EXCEPTION 'Not authorized for this offer' USING ERRCODE='28000';
      END IF;
      IF p_action='cancel' AND v_club<>v_offer.buyer_club_id THEN RAISE EXCEPTION 'Not authorized for this offer' USING ERRCODE='28000'; END IF;
      IF p_action='counter' THEN
        IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Invalid counteroffer amount'; END IF;
        SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=v_offer.player_id AND ended_at IS NULL FOR UPDATE;
        IF v_contract.id IS NULL OR v_contract.club_id<>v_offer.seller_club_id THEN RAISE EXCEPTION 'Seller no longer owns player' USING ERRCODE='GM001'; END IF;
        IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=v_offer.player_id) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
        IF v_club=v_offer.buyer_club_id THEN
          IF NOT EXISTS(SELECT 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_club AND balance-reserved+v_offer.amount>=p_amount) THEN
            RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001';
          END IF;
          UPDATE game.accounts SET reserved=reserved-v_offer.amount+p_amount WHERE tournament_id=v_tournament AND club_id=v_club;
        END IF;
        INSERT INTO game.offer_revisions(tournament_id,offer_id,revision,author_club_id,amount)
          VALUES(v_tournament,v_offer.id,0,v_offer.buyer_club_id,v_offer.amount) ON CONFLICT(offer_id,revision) DO NOTHING;
        INSERT INTO game.offer_revisions(tournament_id,offer_id,revision,author_club_id,amount)
          VALUES(v_tournament,v_offer.id,v_offer.proposal_revision+1,v_club,p_amount);
        UPDATE game.offers SET proposed_amount=p_amount,proposed_by_club_id=v_club,proposal_revision=proposal_revision+1,
          amount=CASE WHEN v_club=buyer_club_id THEN p_amount ELSE amount END WHERE id=v_offer.id;
        v_result:=jsonb_build_object('offerId',v_offer.id,'proposedAmount',p_amount,'revision',v_offer.proposal_revision+1);
      ELSIF p_action='accept' THEN
        SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=v_offer.player_id AND ended_at IS NULL FOR UPDATE;
        IF v_contract.id IS NULL OR v_contract.club_id<>v_offer.seller_club_id THEN RAISE EXCEPTION 'Seller no longer owns player' USING ERRCODE='GM001'; END IF;
        IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=v_offer.player_id) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
        v_trade:=true; v_buyer:=v_offer.buyer_club_id; v_seller:=v_offer.seller_club_id;
        p_player:=v_offer.player_id; v_amount:=coalesce(v_offer.proposed_amount,v_offer.amount);
        IF NOT EXISTS(SELECT 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_offer.buyer_club_id AND balance-reserved+v_offer.amount>=v_amount) THEN
          RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001';
        END IF;
        UPDATE game.accounts SET reserved=reserved-v_offer.amount+v_amount WHERE tournament_id=v_tournament AND club_id=v_offer.buyer_club_id;
        UPDATE game.offers SET amount=v_amount WHERE id=v_offer.id; v_clause:=v_contract.clause; v_kind:='offer';
        PERFORM game.release_offer(v_offer.id,'accepted');
        v_result:=jsonb_build_object('operationId',v_operation,'offerId',v_offer.id,'playerId',p_player,'amount',v_amount);
      ELSE
        PERFORM game.release_offer(v_offer.id,CASE WHEN p_action='reject' THEN 'rejected' ELSE 'cancelled' END);
        v_result:=jsonb_build_object('offerId',v_offer.id,'released',v_offer.amount);
      END IF;
    END IF;
  END IF;
  INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result)
    VALUES(v_operation,v_tournament,'market_'||p_action,v_key,v_payload,v_result);
  IF v_trade THEN
    -- Cancel rival offers before payment and return their holds to the correct clubs.
    FOR v_row IN SELECT id FROM game.offers WHERE tournament_id=v_tournament AND player_id=p_player AND status='pending' ORDER BY id LOOP
      PERFORM game.release_offer(v_row.id,'stale');
    END LOOP;
    PERFORM 1 FROM game.accounts WHERE tournament_id=v_tournament AND (club_id IN(v_buyer,v_seller) OR (v_seller IS NULL AND club_id IS NULL)) ORDER BY id FOR UPDATE;
    SELECT id INTO v_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_buyer AND balance-reserved>=v_amount;
    IF v_account IS NULL THEN RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001'; END IF;
    SELECT id INTO v_counter_account FROM game.accounts WHERE tournament_id=v_tournament AND
      ((v_seller IS NOT NULL AND club_id=v_seller) OR (v_seller IS NULL AND club_id IS NULL));
    IF v_counter_account IS NULL THEN RAISE EXCEPTION 'Missing counterparty account'; END IF;
    UPDATE game.market_limits SET purchases_used=purchases_used+1 WHERE window_id=v_window.id AND club_id=v_buyer;
    UPDATE game.accounts SET balance=balance-v_amount WHERE id=v_account;
    UPDATE game.accounts SET balance=balance+v_amount WHERE id=v_counter_account;
    INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES
      (v_tournament,v_operation,v_account,-v_amount),(v_tournament,v_operation,v_counter_account,v_amount);
    UPDATE game.contracts SET ended_at=v_now WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL;
    INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause,started_at)
      VALUES(v_tournament,p_player,v_buyer,v_amount,v_clause,v_now);
    INSERT INTO game.transfers(tournament_id,operation_id,window_id,buyer_club_id,seller_club_id,player_id,amount,kind)
      VALUES(v_tournament,v_operation,v_window.id,v_buyer,v_seller,p_player,v_amount,v_kind);
  END IF;
  RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.game_pay_clause_core(p_code text,p_token text,p_key uuid,p_player uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
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
  IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
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

CREATE OR REPLACE FUNCTION game.eligible_free(p_tournament uuid,p_club uuid,p_player uuid,p_window uuid) RETURNS boolean LANGUAGE sql VOLATILE SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM game.players p WHERE p.tournament_id=p_tournament AND p.player_id=p_player AND NOT p.is_icon)
 AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p_tournament AND c.player_id=p_player AND c.ended_at IS NULL AND (c.club_id=p_club OR EXISTS(SELECT 1 FROM game.assignments aa WHERE aa.club_id=c.club_id AND aa.ended_at IS NULL)))
 AND NOT EXISTS(SELECT 1 FROM game.releases rr WHERE rr.tournament_id=p_tournament AND rr.player_id=p_player AND ((rr.created_at AT TIME ZONE 'America/Bogota')::date >= (clock_timestamp() AT TIME ZONE 'America/Bogota')::date OR (rr.club_id=p_club AND rr.window_id IS NOT DISTINCT FROM p_window)))
 AND NOT EXISTS(SELECT 1 FROM game.transfers tr WHERE tr.window_id=p_window AND tr.player_id=p_player)
$$;

CREATE OR REPLACE FUNCTION public.game_activity_command(p_code text,p_token text,p_key uuid,p_action text,p_body jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; club uuid; actor text; key text; old game.operations; w game.market_windows; b game.ballots; sp game.spins;
 r game.rules; player uuid; ballot uuid; spin uuid; result jsonb:='{}'; op uuid; BEGIN
 IF p_key IS NULL OR p_action IS NULL OR jsonb_typeof(p_body)<>'object' THEN RAISE EXCEPTION 'Invalid activity'; END IF;
 IF p_action IN('vote_open','vote_close') THEN tid:=game.require_admin(p_code,p_token); actor:='admin';
 ELSE mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; actor:=mid::text; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 key:='activity:'||actor||':'||p_key; SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key=key;
 IF FOUND THEN IF old.payload<>jsonb_build_object('action',p_action,'body',p_body) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF; RETURN old.result; END IF;
 SELECT * INTO r FROM game.rules WHERE tournament_id=tid; IF NOT FOUND THEN PERFORM game.rule_error('Competition mode required'); END IF;
 SELECT * INTO w FROM game.market_windows WHERE tournament_id=tid AND status='open';
 IF w.id IS NULL OR w.closes_at<=clock_timestamp() THEN PERFORM game.rule_error('No open market'); END IF;
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 IF mid IS NOT NULL AND club IS NULL THEN PERFORM game.rule_error('Choose a club first'); END IF;
 IF p_action='vote_open' THEN
 IF coalesce((p_body->>'minutes')::integer,0) NOT BETWEEN 1 AND 60 OR coalesce((p_body->>'auctionMinutes')::integer,0) NOT BETWEEN 1 AND 1440 THEN RAISE EXCEPTION 'Invalid voting duration'; END IF;
 IF EXISTS(SELECT 1 FROM game.auctions WHERE window_id=w.id AND status='active') OR EXISTS(SELECT 1 FROM game.ballots WHERE window_id=w.id AND status='open') THEN PERFORM game.rule_error('Auction or voting already active'); END IF;
 INSERT INTO game.ballots(tournament_id,window_id,ends_at,auction_minutes) VALUES(tid,w.id,least(w.closes_at,clock_timestamp()+make_interval(mins=>(p_body->>'minutes')::integer)),(p_body->>'auctionMinutes')::integer) RETURNING id INTO ballot;
 INSERT INTO game.ballot_options SELECT tid,ballot,p.player_id FROM game.players p WHERE p.tournament_id=tid AND p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=tid AND c.player_id=p.player_id AND c.ended_at IS NULL) AND NOT EXISTS(SELECT 1 FROM game.transfers tr WHERE tr.window_id=w.id AND tr.player_id=p.player_id) ORDER BY random() LIMIT 5;
 IF NOT FOUND THEN PERFORM game.rule_error('No eligible auction icon'); END IF;
 INSERT INTO game.electorate SELECT tid,ballot,club_id FROM game.assignments WHERE tournament_id=tid AND ended_at IS NULL;
 IF NOT FOUND THEN PERFORM game.rule_error('At least one assigned club required'); END IF;
 result:=jsonb_build_object('ballotId',ballot);
 ELSIF p_action IN('vote','vote_close') THEN
 SELECT * INTO b FROM game.ballots WHERE id=(p_body->>'ballotId')::uuid AND tournament_id=tid AND window_id=w.id AND status='open';
 IF NOT FOUND THEN PERFORM game.rule_error('Voting is closed'); END IF;
 IF p_action='vote' THEN
 IF b.ends_at<=clock_timestamp() THEN PERFORM game.rule_error('Voting is closed'); END IF;
 player:=(p_body->>'playerId')::uuid;
 IF NOT EXISTS(SELECT 1 FROM game.electorate WHERE ballot_id=b.id AND club_id=club) OR NOT EXISTS(SELECT 1 FROM game.ballot_options WHERE ballot_id=b.id AND player_id=player) THEN RAISE EXCEPTION 'Invalid vote'; END IF;
 IF EXISTS(SELECT 1 FROM game.votes WHERE ballot_id=b.id AND club_id=club) THEN PERFORM game.rule_error('Club already voted'); END IF;
 INSERT INTO game.votes VALUES(tid,b.id,club,player);
 ELSE
 IF b.ends_at>clock_timestamp() AND (SELECT count(*) FROM game.votes WHERE ballot_id=b.id)<(SELECT count(*) FROM game.electorate WHERE ballot_id=b.id) THEN PERFORM game.rule_error('Voting still pending'); END IF;
 result:=game.finish_ballot(b.id);
 END IF;
 ELSIF p_action='spin' THEN
 PERFORM game.ensure_purchase(tid,club);
 UPDATE game.spins SET status='expired' WHERE tournament_id=tid AND club_id=club AND status='pending' AND expires_at<=clock_timestamp();
 IF EXISTS(SELECT 1 FROM game.spins WHERE window_id=w.id AND club_id=club AND status='pending') THEN PERFORM game.rule_error('Resolve pending spin first'); END IF;
 SELECT p.player_id INTO player FROM game.players p WHERE p.tournament_id=tid AND game.eligible_free(tid,club,p.player_id,w.id)
 AND (SELECT count(*) FROM game.daily_claims dc WHERE dc.tournament_id=tid AND dc.club_id=club AND dc.period=(clock_timestamp() AT TIME ZONE 'America/Bogota')::date AND dc.tier=CASE WHEN p.ovr>=84 THEN 'premium' ELSE 'basic' END)<CASE WHEN p.ovr>=84 THEN r.daily_premium ELSE r.daily_basic END
 ORDER BY random() LIMIT 1;
 IF player IS NULL THEN PERFORM game.rule_error('No eligible daily free players'); END IF;
 op:=game.cash(tid,club,-r.spin_fee,'slot_spin',key||':fee',jsonb_build_object('player',player));
 INSERT INTO game.spins(tournament_id,window_id,club_id,player_id,fee,expires_at) VALUES(tid,w.id,club,player,r.spin_fee,least(w.closes_at,clock_timestamp()+interval '5 minutes')) RETURNING id INTO spin;
 result:=jsonb_build_object('spinId',spin,'playerId',player);
 ELSIF p_action IN('spin_claim','spin_reject') THEN
 SELECT * INTO sp FROM game.spins WHERE id=(p_body->>'spinId')::uuid AND tournament_id=tid AND club_id=club AND window_id=w.id AND status='pending';
 IF NOT FOUND OR sp.expires_at<=clock_timestamp() THEN PERFORM game.rule_error('Spin expired or resolved'); END IF;
 IF p_action='spin_claim' THEN
 result:=public.game_market_command(p_code,p_token,p_key,'sign',sp.player_id);
 UPDATE game.spins SET status='claimed' WHERE id=sp.id;
 ELSE UPDATE game.spins SET status='rejected' WHERE id=sp.id; END IF;
 ELSE RAISE EXCEPTION 'Invalid activity action'; END IF;
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,p_action,key,jsonb_build_object('action',p_action,'body',p_body),result); RETURN result;
END $$;

-- Serialize inserts too, so every acquisition path obeys the session rule.
CREATE FUNCTION game.guard_repeat_transfer() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 PERFORM 1 FROM game.tournaments WHERE id=NEW.tournament_id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=NEW.window_id AND player_id=NEW.player_id) THEN
  RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001';
 END IF;
 RETURN NEW;
END $$;
CREATE INDEX transfer_window_player ON game.transfers(window_id,player_id);
CREATE TRIGGER prevent_repeat_transfer BEFORE INSERT ON game.transfers FOR EACH ROW EXECUTE FUNCTION game.guard_repeat_transfer();
REVOKE ALL ON FUNCTION game.guard_repeat_transfer() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION game.guard_repeat_transfer() TO service_role;

NOTIFY pgrst,'reload schema';
