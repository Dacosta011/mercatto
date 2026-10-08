-- Avoid a table alias that shadows the worker window record; report expired auctions without writes.
CREATE OR REPLACE FUNCTION public.game_expire_markets(p_limit integer DEFAULT 100) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_game record;w game.market_windows;v_row record;v_closed integer:=0;v_settled integer:=0;v_op uuid;v_result jsonb;
BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Invalid worker batch size'; END IF;
 FOR v_game IN SELECT g.id FROM game.tournaments g WHERE
  EXISTS(SELECT 1 FROM game.market_windows mw WHERE mw.tournament_id=g.id AND mw.status='open' AND mw.closes_at<=clock_timestamp()) OR
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
    'auctions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',a.id,'windowId',a.window_id,'playerId',a.player_id,'playerName',p.name,'status',CASE WHEN a.status='active' AND a.ends_at<=clock_timestamp() THEN 'expired' ELSE a.status END,'endsAt',a.ends_at,'minBid',a.min_bid,'highestBid',a.highest_bid,'highestClubId',a.highest_club_id,'highestClub',c.name,
      'bids',coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'clubId',b.club_id,'club',bc.name,'amount',b.amount,'createdAt',b.created_at) ORDER BY b.id DESC) FROM game.auction_bids b JOIN game.clubs bc ON bc.id=b.club_id WHERE b.auction_id=a.id),'[]'::jsonb)) ORDER BY a.starts_at DESC,a.id DESC) FROM game.auctions a JOIN game.players p ON p.tournament_id=a.tournament_id AND p.player_id=a.player_id LEFT JOIN game.clubs c ON c.id=a.highest_club_id WHERE a.tournament_id=v_tournament),'[]'::jsonb),
    'offers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'windowId',o.window_id,'playerId',o.player_id,'playerName',p.name,'buyerClubId',o.buyer_club_id,'sellerClubId',o.seller_club_id,'buyer',b.name,'seller',s.name,'amount',o.amount,'status',o.status,'proposedAmount',o.proposed_amount,'proposedByClubId',o.proposed_by_club_id,
      'revisions',coalesce((SELECT jsonb_agg(jsonb_build_object('revision',r.revision,'authorClubId',r.author_club_id,'amount',r.amount) ORDER BY r.revision) FROM game.offer_revisions r WHERE r.offer_id=o.id),'[]'::jsonb)) ORDER BY o.created_at DESC,o.id DESC) FROM game.offers o JOIN game.players p ON p.tournament_id=o.tournament_id AND p.player_id=o.player_id JOIN game.clubs b ON b.id=o.buyer_club_id JOIN game.clubs s ON s.id=o.seller_club_id WHERE o.tournament_id=v_tournament),'[]'::jsonb),
    'transfers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'playerId',tr.player_id,'playerName',p.name,'buyer',b.name,'seller',s.name,'amount',tr.amount,'kind',tr.kind,'createdAt',tr.created_at) ORDER BY tr.created_at DESC,tr.id DESC) FROM game.transfers tr JOIN game.players p ON p.tournament_id=tr.tournament_id AND p.player_id=tr.player_id JOIN game.clubs b ON b.id=tr.buyer_club_id LEFT JOIN game.clubs s ON s.id=tr.seller_club_id WHERE tr.tournament_id=v_tournament),'[]'::jsonb),
    'ledger',coalesce((SELECT jsonb_agg(jsonb_build_object('id',l.id,'amount',l.amount,'kind',o.kind,'createdAt',l.created_at) ORDER BY l.id DESC) FROM game.ledger l JOIN game.operations o ON o.id=l.operation_id JOIN game.accounts a ON a.id=l.account_id WHERE l.tournament_id=v_tournament AND a.club_id=v_club),'[]'::jsonb)) INTO v_result;
  RETURN v_result;
END $$;


NOTIFY pgrst,'reload schema';
