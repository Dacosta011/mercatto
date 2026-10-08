CREATE OR REPLACE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,p_player uuid DEFAULT NULL,p_offer uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_minutes integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; club uuid; sid uuid; r game.rules; w game.market_windows; f game.offers; result jsonb; op uuid; v_tier text; row record; count_rounds integer; BEGIN
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
 result:=public.game_market_command_core(p_code,p_token,p_key,p_action,p_player,p_offer,p_amount,p_kind,p_minutes);
 IF r.tournament_id IS NOT NULL THEN
 IF p_action='open' AND p_kind='winter' THEN
 UPDATE game.market_windows SET purchase_limit=r.winter_limit WHERE id=(result->>'windowId')::uuid;
 UPDATE game.market_limits SET purchase_limit=r.winter_limit WHERE window_id=(result->>'windowId')::uuid;
 ELSIF p_action='sign' THEN
 SELECT id INTO op FROM game.operations WHERE tournament_id=tid AND idempotency_key='market:'||mid||':'||p_key;
 INSERT INTO game.daily_claims VALUES(tid,club,(clock_timestamp() AT TIME ZONE 'America/Bogota')::date,coalesce(v_tier,(SELECT CASE WHEN ovr>=84 THEN 'premium' ELSE 'basic' END FROM game.players WHERE tournament_id=tid AND player_id=p_player)),op) ON CONFLICT DO NOTHING;
 END IF; END IF; RETURN result;
END $$;
CREATE FUNCTION game.guard_ballot_history() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF TG_OP='DELETE' OR OLD.status<>'open' THEN RAISE EXCEPTION 'Voting history is immutable'; END IF;RETURN NEW;
END $$;
CREATE TRIGGER finished_ballot_history BEFORE UPDATE OR DELETE ON game.ballots FOR EACH ROW EXECUTE FUNCTION game.guard_ballot_history();
CREATE OR REPLACE FUNCTION public.game_expire_markets(p_limit integer DEFAULT 100) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE row record; b record; f game.fixtures; result jsonb; votes integer:=0; forfeits integer:=0; h boolean; a boolean; BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Invalid worker limit'; END IF;
 FOR row IN SELECT g.id FROM game.tournaments g WHERE EXISTS(SELECT 1 FROM game.ballots bb WHERE bb.tournament_id=g.id AND bb.status='open' AND bb.ends_at<=clock_timestamp()) OR EXISTS(SELECT 1 FROM game.entrants e WHERE e.tournament_id=g.id AND e.replacement_due<=clock_timestamp()) ORDER BY g.id LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
 FOR b IN SELECT id FROM game.ballots WHERE tournament_id=row.id AND status='open' AND ends_at<=clock_timestamp() LOOP PERFORM game.finish_ballot(b.id);votes:=votes+1; END LOOP;
 IF NOT EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=row.id AND status='open') THEN
 FOR f IN SELECT ff.* FROM game.fixtures ff JOIN game.seasons ss ON ss.id=ff.season_id WHERE ff.tournament_id=row.id AND ss.ended_at IS NULL AND ff.status='scheduled' AND ff.round=(SELECT min(number) FROM game.rounds WHERE season_id=ss.id AND closed_at IS NULL)
 AND EXISTS(SELECT 1 FROM game.entrants e WHERE e.season_id=ss.id AND e.club_id IN(ff.home_club_id,ff.away_club_id) AND e.replacement_due<=clock_timestamp() AND NOT EXISTS(SELECT 1 FROM game.assignments aa WHERE aa.club_id=e.club_id AND aa.ended_at IS NULL)) LOOP
 h:=EXISTS(SELECT 1 FROM game.assignments WHERE club_id=f.home_club_id AND ended_at IS NULL);a:=EXISTS(SELECT 1 FROM game.assignments WHERE club_id=f.away_club_id AND ended_at IS NULL);
 PERFORM game.finish_fixture(f.id,CASE WHEN h THEN 3 ELSE 0 END,CASE WHEN a THEN 3 ELSE 0 END,'[]',true);forfeits:=forfeits+1;
 END LOOP; END IF;
 END LOOP;
 result:=public.game_expire_markets_core(p_limit);
 UPDATE game.spins sp SET status='expired' WHERE status='pending' AND (expires_at<=clock_timestamp() OR EXISTS(SELECT 1 FROM game.market_windows w WHERE w.id=sp.window_id AND w.status='closed'));
 RETURN result||jsonb_build_object('votesClosed',votes,'forfeits',forfeits);
END $$;
REVOKE ALL ON FUNCTION game.guard_ballot_history() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION game.guard_ballot_history() TO service_role;
NOTIFY pgrst,'reload schema';
