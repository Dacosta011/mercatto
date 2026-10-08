CREATE OR REPLACE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,p_player uuid DEFAULT NULL,p_offer uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_minutes integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; club uuid; sid uuid; r game.rules; source_contract game.contracts; w game.market_windows; f game.offers; result jsonb; op uuid; v_tier text; row record; count_rounds integer; BEGIN
 IF p_action IN('open','close') THEN tid:=game.require_admin(p_code,p_token);
 ELSE mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 SELECT * INTO r FROM game.rules WHERE tournament_id=tid;
 IF FOUND AND NOT EXISTS(SELECT 1 FROM game.operations WHERE tournament_id=tid AND idempotency_key='market:'||coalesce(mid::text,'admin')||':'||p_key) THEN
 SELECT id INTO sid FROM game.seasons WHERE tournament_id=tid AND ended_at IS NULL;
 SELECT * INTO w FROM game.market_windows WHERE tournament_id=tid AND status='open';
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 IF p_action='open' THEN
 IF EXISTS(SELECT 1 FROM game.market_windows WHERE season_id=sid AND kind=p_kind) THEN PERFORM game.rule_error('Window already used this season'); END IF;
 IF p_kind='summer' AND (SELECT phase FROM game.seasons WHERE id=sid)<>'assignment' THEN PERFORM game.rule_error('Summer belongs before league'); END IF;
 IF p_kind='winter' THEN
 SELECT count(*) INTO count_rounds FROM game.rounds WHERE season_id=sid;
 IF (SELECT phase FROM game.seasons WHERE id=sid)<>'league' OR (SELECT count(*) FROM game.rounds WHERE season_id=sid AND closed_at IS NOT NULL)<>greatest(1,count_rounds/2)
 OR EXISTS(SELECT 1 FROM game.fixtures WHERE season_id=sid AND status='playing') OR EXISTS(SELECT 1 FROM game.lineup_confirmations lc JOIN game.fixtures ff ON ff.id=lc.fixture_id WHERE ff.season_id=sid AND ff.status='scheduled') THEN PERFORM game.rule_error('Winter requires closed midpoint round'); END IF;
 END IF;
 ELSIF p_action='close' THEN
 UPDATE game.ballots SET status='cancelled' WHERE window_id=w.id AND status='open';
 UPDATE game.spins SET status='expired' WHERE window_id=w.id AND status='pending';
 ELSIF p_action IN('sign','offer','accept','counter') THEN
 IF p_action IN('offer','sign') THEN PERFORM game.ensure_purchase(tid,club); ELSE
 SELECT * INTO f FROM game.offers WHERE id=p_offer AND tournament_id=tid; IF p_action='accept' OR f.buyer_club_id=club THEN PERFORM game.ensure_purchase(tid,f.buyer_club_id); END IF; END IF;
 IF p_action='sign' THEN
 IF NOT game.eligible_free(tid,club,p_player,w.id) THEN PERFORM game.rule_error('Free player is not eligible today'); END IF;
 SELECT CASE WHEN ovr>=84 THEN 'premium' ELSE 'basic' END INTO v_tier FROM game.players WHERE tournament_id=tid AND player_id=p_player;
 IF (SELECT count(*) FROM game.daily_claims WHERE tournament_id=tid AND club_id=club AND period=(clock_timestamp() AT TIME ZONE 'America/Bogota')::date AND game.daily_claims.tier=v_tier)>=(CASE WHEN v_tier='premium' THEN r.daily_premium ELSE r.daily_basic END) THEN PERFORM game.rule_error('Daily free player quota reached'); END IF;
 END IF;
 END IF;
 END IF;
 IF r.tournament_id IS NOT NULL AND p_action='sign' AND NOT EXISTS(SELECT 1 FROM game.operations WHERE tournament_id=tid AND idempotency_key='market:'||mid||':'||p_key) THEN
 SELECT * INTO source_contract FROM game.contracts WHERE tournament_id=tid AND player_id=p_player AND ended_at IS NULL;
 IF source_contract.id IS NOT NULL THEN
 IF EXISTS(SELECT 1 FROM game.assignments WHERE club_id=source_contract.club_id AND ended_at IS NULL) THEN PERFORM game.rule_error('Player is no longer free'); END IF;
 UPDATE game.contracts SET ended_at=clock_timestamp() WHERE id=source_contract.id;
 END IF; END IF;
 result:=public.game_market_command_core(p_code,p_token,p_key,p_action,p_player,p_offer,p_amount,p_kind,p_minutes);
 IF source_contract.id IS NOT NULL THEN
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'unmanaged_source','unmanaged-source:'||mid||':'||p_key,jsonb_build_object('contract',source_contract.id,'sellerClubId',source_contract.club_id,'playerId',p_player),result);
 END IF;
 IF r.tournament_id IS NOT NULL THEN
 IF p_action='open' AND p_kind='winter' THEN
 UPDATE game.market_windows SET purchase_limit=r.winter_limit WHERE id=(result->>'windowId')::uuid;
 UPDATE game.market_limits SET purchase_limit=r.winter_limit WHERE window_id=(result->>'windowId')::uuid;
 ELSIF p_action='sign' THEN
 SELECT id INTO op FROM game.operations WHERE tournament_id=tid AND idempotency_key='market:'||mid||':'||p_key;
 INSERT INTO game.daily_claims VALUES(tid,club,(clock_timestamp() AT TIME ZONE 'America/Bogota')::date,coalesce(v_tier,(SELECT CASE WHEN ovr>=84 THEN 'premium' ELSE 'basic' END FROM game.players WHERE tournament_id=tid AND player_id=p_player)),op) ON CONFLICT DO NOTHING;
 END IF; END IF; RETURN result;
END $$;
CREATE OR REPLACE FUNCTION game.eligible_free(p_tournament uuid,p_club uuid,p_player uuid,p_window uuid) RETURNS boolean LANGUAGE sql VOLATILE SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM game.players p WHERE p.tournament_id=p_tournament AND p.player_id=p_player AND NOT p.is_icon)
 AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p_tournament AND c.player_id=p_player AND c.ended_at IS NULL AND (c.club_id=p_club OR EXISTS(SELECT 1 FROM game.assignments aa WHERE aa.club_id=c.club_id AND aa.ended_at IS NULL)))
 AND NOT EXISTS(SELECT 1 FROM game.releases rr WHERE rr.tournament_id=p_tournament AND rr.player_id=p_player AND ((rr.created_at AT TIME ZONE 'America/Bogota')::date >= (clock_timestamp() AT TIME ZONE 'America/Bogota')::date OR (rr.club_id=p_club AND rr.window_id IS NOT DISTINCT FROM p_window)))
$$;
ALTER FUNCTION public.game_market_state(text,text) RENAME TO game_market_state_core;
CREATE FUNCTION public.game_market_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid; tid uuid; club uuid; wid uuid; result jsonb; candidates jsonb; BEGIN
 mid:=game.require_member(p_code,p_token);SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 result:=public.game_market_state_core(p_code,p_token);
 IF EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=tid) THEN
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 wid:=(result->'window'->>'id')::uuid;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'price',p.reference_price) ORDER BY p.ovr DESC,p.name),'[]') INTO candidates FROM game.players p WHERE p.tournament_id=tid AND game.eligible_free(tid,club,p.player_id,wid);
 result:=jsonb_set(result,'{freePlayers}',candidates);
 END IF; RETURN result;
END $$;
-- Retain public social identities; additive constraints reject new cross-tournament links.
ALTER TABLE public.posts ADD CONSTRAINT posts_scoped_member FOREIGN KEY(tournament_id,member_id) REFERENCES public.members(tournament_id,id) NOT VALID;
CREATE FUNCTION public.game_social_command(p_code text,p_token text,p_key uuid,p_action text,p_content text DEFAULT NULL,p_post uuid DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid;tid uuid;key text;old game.operations;result jsonb:='{}';post_id uuid;payload jsonb; BEGIN
 mid:=game.require_member(p_code,p_token);SELECT tournament_id INTO tid FROM public.members WHERE id=mid;PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 IF p_key IS NULL OR p_action NOT IN('post','like','unlike') OR p_action IS NULL THEN RAISE EXCEPTION 'Invalid social action'; END IF;
 key:='social:'||mid||':'||p_key;payload:=jsonb_build_object('action',p_action,'content',p_content,'post',p_post);
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key=key;
 IF FOUND THEN IF old.payload<>payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;RETURN old.result; END IF;
 IF p_post IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.posts WHERE id=p_post AND tournament_id=tid) THEN PERFORM game.rule_error('Post not found in tournament'); END IF;
 IF p_action='post' THEN
 IF length(trim(coalesce(p_content,''))) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Invalid post content'; END IF;
 INSERT INTO public.posts(member_id,tournament_id,content,parent_id) VALUES(mid,tid,trim(p_content),p_post) RETURNING id INTO post_id;result:=jsonb_build_object('postId',post_id);
 ELSIF p_post IS NULL THEN RAISE EXCEPTION 'Invalid post';
 ELSIF p_action='like' THEN INSERT INTO public.post_likes(post_id,member_id) VALUES(p_post,mid) ON CONFLICT DO NOTHING;
 ELSE DELETE FROM public.post_likes WHERE public.post_likes.post_id=p_post AND member_id=mid; END IF;
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'social_'||p_action,key,payload,result);RETURN result;
END $$;
CREATE FUNCTION public.game_social_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid;tid uuid;result jsonb; BEGIN
 mid:=game.require_member(p_code,p_token);SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 SELECT coalesce(jsonb_agg(jsonb_build_object('id',p.id,'author',m.display_name,'content',p.content,'imageUrl',p.image_url,'parentId',p.parent_id,'createdAt',p.created_at,'likes',(SELECT count(*) FROM public.post_likes pl WHERE pl.post_id=p.id),'liked',EXISTS(SELECT 1 FROM public.post_likes pl WHERE pl.post_id=p.id AND pl.member_id=mid)) ORDER BY p.created_at DESC,p.id),'[]') INTO result FROM (SELECT * FROM public.posts WHERE tournament_id=tid ORDER BY created_at DESC,id LIMIT 100) p JOIN public.members m ON m.id=p.member_id;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_market_state(text,text),public.game_social_state(text,text),public.game_social_command(text,text,uuid,text,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_market_state(text,text),public.game_social_state(text,text),public.game_social_command(text,text,uuid,text,text,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
