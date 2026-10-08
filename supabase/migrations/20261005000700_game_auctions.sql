ALTER TABLE game.market_limits ADD COLUMN icons_used integer NOT NULL DEFAULT 0 CHECK(icons_used BETWEEN 0 AND 1),
  ADD COLUMN icons_held integer NOT NULL DEFAULT 0 CHECK(icons_held BETWEEN 0 AND 1),
  ADD CONSTRAINT one_icon_slot CHECK(icons_used+icons_held<=1);
ALTER TABLE game.transfers DROP CONSTRAINT transfers_kind_check;
ALTER TABLE game.transfers ADD CONSTRAINT transfers_kind_check CHECK(kind IN('offer','free','clause','icon_auction'));
CREATE TABLE game.auctions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),tournament_id uuid NOT NULL,window_id uuid NOT NULL,player_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK(status IN('active','settled','unsold')),
  min_bid bigint NOT NULL CHECK(min_bid>=5000000),highest_bid bigint NOT NULL DEFAULT 0 CHECK(highest_bid>=0),
  highest_club_id uuid,starts_at timestamptz NOT NULL,ends_at timestamptz NOT NULL CHECK(ends_at>starts_at),settled_at timestamptz,
  CHECK((highest_club_id IS NULL)=(highest_bid=0)),UNIQUE(tournament_id,id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id),
  FOREIGN KEY(tournament_id,highest_club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE UNIQUE INDEX one_active_auction_per_window ON game.auctions(window_id) WHERE status='active';
CREATE UNIQUE INDEX one_active_auction_per_player ON game.auctions(tournament_id,player_id) WHERE status='active';
CREATE TABLE game.auction_bids (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,tournament_id uuid NOT NULL,auction_id uuid NOT NULL,club_id uuid NOT NULL,
  amount bigint NOT NULL CHECK(amount>0),operation_id uuid NOT NULL UNIQUE,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY(tournament_id,auction_id) REFERENCES game.auctions(tournament_id,id),
  FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,operation_id) REFERENCES game.operations(tournament_id,id)
);
ALTER TABLE game.auctions ENABLE ROW LEVEL SECURITY;
ALTER TABLE game.auction_bids ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.auctions,game.auction_bids FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON game.auctions TO service_role;
GRANT SELECT,INSERT ON game.auction_bids TO service_role;
GRANT USAGE,SELECT ON SEQUENCE game.auction_bids_id_seq TO service_role;
CREATE TRIGGER immutable_auction_bids BEFORE UPDATE OR DELETE ON game.auction_bids FOR EACH ROW EXECUTE FUNCTION game.immutable_history();
CREATE FUNCTION game.guard_auction_history() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP='DELETE' OR OLD.status<>'active' THEN RAISE EXCEPTION 'Auction history is immutable'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER immutable_finished_auctions BEFORE UPDATE OR DELETE ON game.auctions FOR EACH ROW EXECUTE FUNCTION game.guard_auction_history();

-- Caller holds the tournament lock. A completed settlement is immutable and replayable.
CREATE FUNCTION game.settle_auction(p_auction uuid,p_reason text DEFAULT 'deadline') RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a game.auctions;w game.market_windows;v_op uuid:=gen_random_uuid();v_result jsonb;v_account uuid;v_clearing uuid;v_now timestamptz;
BEGIN
  SELECT * INTO a FROM game.auctions WHERE id=p_auction;
  IF NOT FOUND THEN RAISE EXCEPTION 'Auction not found' USING ERRCODE='GM001'; END IF;
  PERFORM 1 FROM game.tournaments WHERE id=a.tournament_id FOR UPDATE;
  SELECT * INTO a FROM game.auctions WHERE id=p_auction FOR UPDATE;
  IF a.status<>'active' THEN SELECT result INTO v_result FROM game.operations WHERE tournament_id=a.tournament_id AND idempotency_key='auction-settle:'||a.id; RETURN v_result; END IF;
  v_now:=clock_timestamp();SELECT * INTO w FROM game.market_windows WHERE id=a.window_id FOR UPDATE;
  IF p_reason IS NULL OR p_reason NOT IN('deadline','market_close') THEN RAISE EXCEPTION 'Invalid settlement reason'; END IF;
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

CREATE FUNCTION public.game_auction_command(p_code text,p_token text,p_key uuid,p_action text,
 p_player uuid DEFAULT NULL,p_auction uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_minutes integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_tournament uuid;v_member uuid;v_club uuid;v_actor text;v_key text;v_payload jsonb;v_old game.operations;
 w game.market_windows;a game.auctions;v_now timestamptz;v_price bigint;v_end timestamptz;v_op uuid:=gen_random_uuid();v_result jsonb;
BEGIN
 IF p_key IS NULL OR p_action IS NULL OR p_action NOT IN('auction_open','auction_bid') THEN RAISE EXCEPTION 'Invalid auction action'; END IF;
 IF p_action='auction_open' THEN
  SELECT t.id INTO v_tournament FROM public.tournaments t JOIN game.tournaments g ON g.id=t.id WHERE t.code=upper(p_code) AND t.status='prototype' AND t.admin_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  IF v_tournament IS NULL THEN RAISE EXCEPTION 'Invalid admin token' USING ERRCODE='28000'; END IF;v_actor:='admin';
 ELSE
  v_member:=game.require_member(p_code,p_token);SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;v_actor:=v_member::text;
 END IF;
 PERFORM 1 FROM game.tournaments WHERE id=v_tournament FOR UPDATE;v_now:=clock_timestamp();
 v_key:='market:'||v_actor||':'||p_key;v_payload:=jsonb_build_object('action',p_action,'player',p_player,'auction',p_auction,'amount',p_amount,'minutes',p_minutes);
 SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key=v_key;
 IF FOUND THEN IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;RETURN v_old.result;END IF;
 SELECT * INTO w FROM game.market_windows WHERE tournament_id=v_tournament AND status='open' FOR UPDATE;
 IF w.id IS NULL THEN RAISE EXCEPTION 'No open market' USING ERRCODE='GM001'; END IF;
 IF v_now>=w.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
 IF p_action='auction_open' THEN
  IF p_player IS NULL OR p_minutes IS NULL OR p_minutes NOT BETWEEN 1 AND 1440 THEN RAISE EXCEPTION 'Invalid auction settings'; END IF;
  IF EXISTS(SELECT 1 FROM game.auctions WHERE window_id=w.id AND status='active') THEN RAISE EXCEPTION 'Auction already active' USING ERRCODE='GM001'; END IF;
  SELECT reference_price INTO v_price FROM game.players WHERE tournament_id=v_tournament AND player_id=p_player AND is_icon FOR UPDATE;
  IF NOT FOUND OR EXISTS(SELECT 1 FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL) THEN RAISE EXCEPTION 'No eligible auction icon' USING ERRCODE='GM001'; END IF;
  INSERT INTO game.auctions(tournament_id,window_id,player_id,min_bid,starts_at,ends_at)
   VALUES(v_tournament,w.id,p_player,greatest(5000000,v_price),v_now,least(w.closes_at,v_now+make_interval(mins=>p_minutes))) RETURNING * INTO a;
  v_result:=jsonb_build_object('auctionId',a.id);
 ELSE
  IF p_auction IS NULL OR p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Invalid auction bid'; END IF;
  SELECT club_id INTO v_club FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  IF v_club IS NULL THEN RAISE EXCEPTION 'Choose a club first' USING ERRCODE='GM001'; END IF;
  SELECT * INTO a FROM game.auctions WHERE id=p_auction AND tournament_id=v_tournament AND window_id=w.id FOR UPDATE;
  IF NOT FOUND OR a.status<>'active' THEN RAISE EXCEPTION 'Auction is not active in this market' USING ERRCODE='GM001'; END IF;
  IF v_now>=a.ends_at THEN RAISE EXCEPTION 'Auction deadline passed' USING ERRCODE='GM001'; END IF;
  IF a.highest_club_id=v_club THEN RAISE EXCEPTION 'Club already leads auction' USING ERRCODE='GM001'; END IF;
  IF p_amount<greatest(a.min_bid,a.highest_bid+5000000) THEN RAISE EXCEPTION 'Auction bid below minimum' USING ERRCODE='GM001'; END IF;
  IF NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=w.id AND club_id=v_club AND icons_used+icons_held<1) THEN RAISE EXCEPTION 'No icon slots available' USING ERRCODE='GM001'; END IF;
  PERFORM 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id IN(v_club,a.highest_club_id) ORDER BY id FOR UPDATE;
  IF NOT EXISTS(SELECT 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_club AND balance-reserved>=p_amount) THEN RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001'; END IF;
  IF a.highest_club_id IS NOT NULL THEN
   UPDATE game.accounts SET reserved=reserved-a.highest_bid WHERE tournament_id=v_tournament AND club_id=a.highest_club_id;
   UPDATE game.market_limits SET icons_held=icons_held-1 WHERE window_id=w.id AND club_id=a.highest_club_id;
  END IF;
  UPDATE game.accounts SET reserved=reserved+p_amount WHERE tournament_id=v_tournament AND club_id=v_club;
  UPDATE game.market_limits SET icons_held=icons_held+1 WHERE window_id=w.id AND club_id=v_club;
  v_end:=a.ends_at;
  IF a.ends_at-v_now<=interval '2 minutes' THEN v_end:=least(w.closes_at,greatest(a.ends_at,v_now+interval '2 minutes')); END IF;
  UPDATE game.auctions SET highest_bid=p_amount,highest_club_id=v_club,ends_at=v_end WHERE id=a.id;
  v_result:=jsonb_build_object('auctionId',a.id,'amount',p_amount,'endsAt',v_end);
 END IF;
 INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result) VALUES(v_op,v_tournament,p_action,v_key,v_payload,v_result);
 IF p_action='auction_bid' THEN INSERT INTO game.auction_bids(tournament_id,auction_id,club_id,amount,operation_id) VALUES(v_tournament,a.id,v_club,p_amount,v_op); END IF;
 RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.game_auction_command(text,text,uuid,text,uuid,uuid,bigint,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_auction_command(text,text,uuid,text,uuid,uuid,bigint,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.game_expire_markets(p_limit integer DEFAULT 100) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_game record;w game.market_windows;v_row record;v_closed integer:=0;v_settled integer:=0;v_op uuid;v_result jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Invalid worker batch size'; END IF;
 FOR v_game IN SELECT g.id FROM game.tournaments g WHERE
  EXISTS(SELECT 1 FROM game.market_windows w WHERE w.tournament_id=g.id AND w.status='open' AND w.closes_at<=clock_timestamp()) OR
  EXISTS(SELECT 1 FROM game.auctions a WHERE a.tournament_id=g.id AND a.status='active' AND a.ends_at<=clock_timestamp())
  ORDER BY g.id LIMIT p_limit FOR UPDATE OF g SKIP LOCKED LOOP
  SELECT * INTO w FROM game.market_windows WHERE tournament_id=v_game.id AND status='open' FOR UPDATE;
  IF w.id IS NULL THEN CONTINUE; END IF;
  FOR v_row IN SELECT id FROM game.auctions WHERE window_id=w.id AND status='active' AND (ends_at<=clock_timestamp() OR w.closes_at<=clock_timestamp()) ORDER BY id LOOP
   PERFORM game.settle_auction(v_row.id,'deadline');v_settled:=v_settled+1;
  END LOOP;
  IF w.closes_at>clock_timestamp() THEN CONTINUE; END IF;
  FOR v_row IN SELECT id FROM game.offers WHERE window_id=w.id AND status='pending' ORDER BY id LOOP PERFORM game.release_offer(v_row.id,'expired');END LOOP;
  UPDATE game.market_windows SET status='closed',closed_at=clock_timestamp() WHERE id=w.id;
  v_op:=gen_random_uuid();v_result:=jsonb_build_object('windowId',w.id,'closed',true,'reason','deadline');
  INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result) VALUES(v_op,v_game.id,'market_auto_close','auto-close:'||w.id,jsonb_build_object('window',w.id),v_result);
  v_closed:=v_closed+1;
 END LOOP;
 RETURN jsonb_build_object('closed',v_closed,'settled',v_settled);
END $$;

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
      SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL FOR UPDATE;
      IF p_action='offer' THEN
        IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player AND kind IN('offer','clause')) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
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
        IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=v_offer.player_id AND kind IN('offer','clause')) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
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
        IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=v_offer.player_id AND kind IN('offer','clause')) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
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
    'window',(SELECT jsonb_build_object('id',w.id,'kind',w.kind,'status',CASE WHEN w.status='open' AND clock_timestamp()>=w.closes_at THEN 'expired' ELSE w.status END,'closesAt',w.closes_at,'purchaseLimit',w.purchase_limit,'clauseProtectionLimit',w.clause_protection_limit) FROM game.market_windows w WHERE w.tournament_id=v_tournament ORDER BY w.opens_at DESC,w.id DESC LIMIT 1),
    'limits',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',l.club_id,'used',l.purchases_used,'held',l.purchases_held,'limit',l.purchase_limit,'iconsUsed',l.icons_used,'iconsHeld',l.icons_held)) FROM game.market_limits l JOIN game.market_windows w ON w.id=l.window_id WHERE l.tournament_id=v_tournament AND w.status='open'),'[]'::jsonb),
    'freePlayers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'price',p.reference_price) ORDER BY p.name) FROM game.players p WHERE p.tournament_id=v_tournament AND NOT p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p.tournament_id AND c.player_id=p.player_id AND c.ended_at IS NULL)),'[]'::jsonb),
    'clauseAttempts',coalesce((SELECT jsonb_agg(jsonb_build_object('windowId',a.window_id,'buyerClubId',a.buyer_club_id,'buyer',b.name,'seller',s.name,'playerId',a.player_id,'playerName',p.name,'amount',a.amount,'outcome',a.outcome,'createdAt',a.created_at) ORDER BY a.created_at DESC) FROM game.clause_attempts a JOIN game.clubs b ON b.id=a.buyer_club_id JOIN game.clubs s ON s.id=a.seller_club_id JOIN game.players p ON p.tournament_id=a.tournament_id AND p.player_id=a.player_id WHERE a.tournament_id=v_tournament),'[]'::jsonb),
    'auctionIcons',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'minBid',greatest(5000000,p.reference_price)) ORDER BY p.name) FROM game.players p WHERE p.tournament_id=v_tournament AND p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p.tournament_id AND c.player_id=p.player_id AND c.ended_at IS NULL)),'[]'::jsonb),
    'auctions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'windowId',a.window_id,'playerId',a.player_id,'playerName',p.name,'status',a.status,'endsAt',a.ends_at,'minBid',a.min_bid,'highestBid',a.highest_bid,'highestClubId',a.highest_club_id,'highestClub',c.name,
      'bids',coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'clubId',b.club_id,'club',bc.name,'amount',b.amount,'createdAt',b.created_at) ORDER BY b.id DESC) FROM game.auction_bids b JOIN game.clubs bc ON bc.id=b.club_id WHERE b.auction_id=a.id),'[]'::jsonb)) ORDER BY a.starts_at DESC,a.id DESC) FROM game.auctions a JOIN game.players p ON p.tournament_id=a.tournament_id AND p.player_id=a.player_id LEFT JOIN game.clubs c ON c.id=a.highest_club_id WHERE a.tournament_id=v_tournament),'[]'::jsonb),
    'offers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'windowId',o.window_id,'playerId',o.player_id,'playerName',p.name,'buyerClubId',o.buyer_club_id,'sellerClubId',o.seller_club_id,'buyer',b.name,'seller',s.name,'amount',o.amount,'status',o.status,'proposedAmount',o.proposed_amount,'proposedByClubId',o.proposed_by_club_id,
      'revisions',coalesce((SELECT jsonb_agg(jsonb_build_object('revision',r.revision,'authorClubId',r.author_club_id,'amount',r.amount) ORDER BY r.revision) FROM game.offer_revisions r WHERE r.offer_id=o.id),'[]'::jsonb)) ORDER BY o.created_at DESC,o.id DESC) FROM game.offers o JOIN game.players p ON p.tournament_id=o.tournament_id AND p.player_id=o.player_id JOIN game.clubs b ON b.id=o.buyer_club_id JOIN game.clubs s ON s.id=o.seller_club_id WHERE o.tournament_id=v_tournament),'[]'::jsonb),
    'transfers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'playerId',tr.player_id,'playerName',p.name,'buyer',b.name,'seller',s.name,'amount',tr.amount,'kind',tr.kind,'createdAt',tr.created_at) ORDER BY tr.created_at DESC,tr.id DESC) FROM game.transfers tr JOIN game.players p ON p.tournament_id=tr.tournament_id AND p.player_id=tr.player_id JOIN game.clubs b ON b.id=tr.buyer_club_id LEFT JOIN game.clubs s ON s.id=tr.seller_club_id WHERE tr.tournament_id=v_tournament),'[]'::jsonb),
    'ledger',coalesce((SELECT jsonb_agg(jsonb_build_object('id',l.id,'amount',l.amount,'kind',o.kind,'createdAt',l.created_at) ORDER BY l.id DESC) FROM game.ledger l JOIN game.operations o ON o.id=l.operation_id JOIN game.accounts a ON a.id=l.account_id WHERE l.tournament_id=v_tournament AND a.club_id=v_club),'[]'::jsonb)) INTO v_result;
  RETURN v_result;
END $$;


NOTIFY pgrst,'reload schema';
