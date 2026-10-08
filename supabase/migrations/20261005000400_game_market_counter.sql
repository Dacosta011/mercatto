ALTER TABLE game.offers ADD COLUMN proposed_amount bigint CHECK(proposed_amount>0),
  ADD COLUMN proposed_by_club_id uuid,
  ADD COLUMN proposal_revision integer NOT NULL DEFAULT 0 CHECK(proposal_revision>=0),
  ADD CONSTRAINT proposal_pair CHECK((proposed_amount IS NULL)=(proposed_by_club_id IS NULL)),
  ADD CONSTRAINT proposal_author_scope FOREIGN KEY(tournament_id,proposed_by_club_id) REFERENCES game.clubs(tournament_id,id),
  ADD CONSTRAINT proposal_author_party CHECK(proposed_by_club_id IS NULL OR proposed_by_club_id IN(buyer_club_id,seller_club_id));
CREATE TABLE game.offer_revisions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tournament_id uuid NOT NULL,
  offer_id uuid NOT NULL,
  revision integer NOT NULL CHECK(revision>=0),
  author_club_id uuid NOT NULL,
  amount bigint NOT NULL CHECK(amount>0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(offer_id,revision),
  FOREIGN KEY(tournament_id,offer_id) REFERENCES game.offers(tournament_id,id),
  FOREIGN KEY(tournament_id,author_club_id) REFERENCES game.clubs(tournament_id,id)
);
ALTER TABLE game.offer_revisions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.offer_revisions FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON game.offer_revisions TO service_role;
GRANT USAGE,SELECT ON SEQUENCE game.offer_revisions_id_seq TO service_role;
CREATE TRIGGER immutable_offer_revisions BEFORE UPDATE OR DELETE ON game.offer_revisions FOR EACH ROW EXECUTE FUNCTION game.immutable_history();

-- Explicit worker command. Reads never settle games. Skip busy tournaments and retry next tick.
CREATE FUNCTION public.game_expire_markets(p_limit integer DEFAULT 100) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_game record; v_window game.market_windows; v_offer record; v_count integer:=0; v_op uuid; v_result jsonb;
BEGIN
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Invalid worker batch size'; END IF;
  FOR v_game IN SELECT g.id FROM game.tournaments g
    WHERE EXISTS(SELECT 1 FROM game.market_windows w WHERE w.tournament_id=g.id AND w.status='open' AND w.closes_at<=clock_timestamp())
    ORDER BY g.id LIMIT p_limit FOR UPDATE OF g SKIP LOCKED LOOP
    SELECT * INTO v_window FROM game.market_windows WHERE tournament_id=v_game.id AND status='open' AND closes_at<=clock_timestamp() FOR UPDATE;
    IF v_window.id IS NULL THEN CONTINUE; END IF;
    FOR v_offer IN SELECT id FROM game.offers WHERE window_id=v_window.id AND status='pending' ORDER BY id LOOP
      PERFORM game.release_offer(v_offer.id,'expired');
    END LOOP;
    UPDATE game.market_windows SET status='closed',closed_at=clock_timestamp() WHERE id=v_window.id;
    v_op:=gen_random_uuid(); v_result:=jsonb_build_object('windowId',v_window.id,'closed',true,'reason','deadline');
    INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result)
      VALUES(v_op,v_game.id,'market_auto_close','auto-close:'||v_window.id,jsonb_build_object('window',v_window.id),v_result);
    v_count:=v_count+1;
  END LOOP;
  RETURN jsonb_build_object('closed',v_count);
END $$;
REVOKE ALL ON FUNCTION public.game_expire_markets(integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_expire_markets(integer) TO service_role;

-- Updated transactional command/read definitions follow below.
CREATE OR REPLACE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,
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
      SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL FOR UPDATE;
      IF p_action='offer' THEN
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

CREATE OR REPLACE FUNCTION public.game_market_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid; v_tournament uuid; v_club uuid; v_result jsonb;
BEGIN
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  SELECT club_id INTO v_club FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  SELECT jsonb_build_object(
    'window',(SELECT jsonb_build_object('id',w.id,'kind',w.kind,'status',CASE WHEN w.status='open' AND clock_timestamp()>=w.closes_at THEN 'expired' ELSE w.status END,'closesAt',w.closes_at,'purchaseLimit',w.purchase_limit) FROM game.market_windows w WHERE w.tournament_id=v_tournament ORDER BY w.opens_at DESC,w.id DESC LIMIT 1),
    'limits',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',l.club_id,'used',l.purchases_used,'held',l.purchases_held,'limit',l.purchase_limit)) FROM game.market_limits l JOIN game.market_windows w ON w.id=l.window_id WHERE l.tournament_id=v_tournament AND w.status='open'),'[]'::jsonb),
    'freePlayers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'price',p.reference_price) ORDER BY p.name) FROM game.players p WHERE p.tournament_id=v_tournament AND NOT p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p.tournament_id AND c.player_id=p.player_id AND c.ended_at IS NULL)),'[]'::jsonb),
    'offers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'windowId',o.window_id,'playerId',o.player_id,'playerName',p.name,'buyerClubId',o.buyer_club_id,'sellerClubId',o.seller_club_id,'buyer',b.name,'seller',s.name,'amount',o.amount,'status',o.status,'proposedAmount',o.proposed_amount,'proposedByClubId',o.proposed_by_club_id,
      'revisions',coalesce((SELECT jsonb_agg(jsonb_build_object('revision',r.revision,'authorClubId',r.author_club_id,'amount',r.amount) ORDER BY r.revision) FROM game.offer_revisions r WHERE r.offer_id=o.id),'[]'::jsonb)) ORDER BY o.created_at DESC,o.id DESC) FROM game.offers o JOIN game.players p ON p.tournament_id=o.tournament_id AND p.player_id=o.player_id JOIN game.clubs b ON b.id=o.buyer_club_id JOIN game.clubs s ON s.id=o.seller_club_id WHERE o.tournament_id=v_tournament),'[]'::jsonb),
    'transfers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'playerId',tr.player_id,'playerName',p.name,'buyer',b.name,'seller',s.name,'amount',tr.amount,'kind',tr.kind,'createdAt',tr.created_at) ORDER BY tr.created_at DESC,tr.id DESC) FROM game.transfers tr JOIN game.players p ON p.tournament_id=tr.tournament_id AND p.player_id=tr.player_id JOIN game.clubs b ON b.id=tr.buyer_club_id LEFT JOIN game.clubs s ON s.id=tr.seller_club_id WHERE tr.tournament_id=v_tournament),'[]'::jsonb),
    'ledger',coalesce((SELECT jsonb_agg(jsonb_build_object('id',l.id,'amount',l.amount,'kind',o.kind,'createdAt',l.created_at) ORDER BY l.id DESC) FROM game.ledger l JOIN game.operations o ON o.id=l.operation_id JOIN game.accounts a ON a.id=l.account_id WHERE l.tournament_id=v_tournament AND a.club_id=v_club),'[]'::jsonb)) INTO v_result;
  RETURN v_result;
END $$;


NOTIFY pgrst,'reload schema';
