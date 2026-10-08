CREATE OR REPLACE FUNCTION public.game_competition_command(p_code text,p_token text,p_key uuid,p_action text,p_body jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; club uuid; sid uuid; actor text; key text; old game.operations; result jsonb:='{}'; r game.rules;
 f game.fixtures; ct uuid; clubs uuid[]; n integer; legs integer; i integer; j integer; k integer; rr integer; h uuid; a uuid; swap uuid;
 round_now integer; fixture uuid; item record; players uuid[]; target uuid; credit bigint; BEGIN
 IF p_key IS NULL OR p_action IS NULL OR jsonb_typeof(p_body)<>'object' THEN RAISE EXCEPTION 'Invalid command'; END IF;
 IF p_action IN('configure','league_start','round_close','result_force','replace','forfeit','season_next') THEN tid:=game.require_admin(p_code,p_token); actor:='admin';
 ELSIF p_action='leave' THEN SELECT m.id,m.tournament_id INTO mid,tid FROM public.members m JOIN public.tournaments t ON t.id=m.tournament_id JOIN game.tournaments g ON g.id=t.id WHERE t.code=upper(p_code) AND t.status='prototype' AND m.member_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex'); IF mid IS NULL THEN RAISE EXCEPTION 'Invalid member token' USING ERRCODE='28000'; END IF; actor:=mid::text;
 ELSE mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; actor:=mid::text; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 SELECT * INTO r FROM game.rules WHERE tournament_id=tid;
 IF NOT FOUND THEN INSERT INTO game.rules(tournament_id) VALUES(tid) RETURNING * INTO r; END IF;
 key:='competition:'||actor||':'||p_key;
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key=key;
 IF FOUND THEN IF old.payload<>jsonb_build_object('action',p_action,'body',p_body) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF; RETURN old.result; END IF;
 SELECT id INTO sid FROM game.seasons WHERE tournament_id=tid AND ended_at IS NULL;
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 SELECT min(number) INTO round_now FROM game.rounds WHERE season_id=sid AND closed_at IS NULL;
 IF p_action='configure' THEN
 IF EXISTS(SELECT 1 FROM game.fixtures WHERE tournament_id=tid) OR EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid) THEN PERFORM game.rule_error('Configure before starting the game'); END IF;
 UPDATE game.rules SET min_squad=coalesce((p_body->>'minSquad')::integer,min_squad), max_squad=coalesce((p_body->>'maxSquad')::integer,max_squad),
 daily_basic=coalesce((p_body->>'dailyBasic')::integer,daily_basic),daily_premium=coalesce((p_body->>'dailyPremium')::integer,daily_premium),
 rerolls=coalesce((p_body->>'rerolls')::integer,rerolls),winter_limit=coalesce((p_body->>'winterLimit')::integer,winter_limit),
 season_income=coalesce((p_body->>'seasonIncome')::bigint,season_income),spin_fee=coalesce((p_body->>'spinFee')::bigint,spin_fee),replacement_days=coalesce((p_body->>'replacementDays')::integer,replacement_days) WHERE tournament_id=tid;
 ELSIF p_action IN('release','draw') THEN
 IF EXISTS(SELECT 1 FROM game.fixtures WHERE tournament_id=tid AND status='playing') THEN PERFORM game.rule_error('Finish active matches first'); END IF;
 IF p_action='release' THEN
 IF club IS NULL THEN PERFORM game.rule_error('Choose a club first'); END IF;
 IF NOT EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid AND status='open' AND closes_at>clock_timestamp()) THEN PERFORM game.rule_error('No open market'); END IF;
 SELECT id INTO ct FROM game.contracts WHERE tournament_id=tid AND club_id=club AND player_id=(p_body->>'playerId')::uuid AND ended_at IS NULL;
 IF ct IS NULL THEN PERFORM game.rule_error('Player is no longer owned'); END IF;
 result:=jsonb_build_object('operationId',game.release_contract(ct,key||':release',false));
 ELSE
 IF (SELECT phase FROM game.seasons WHERE id=sid)<>'assignment' OR EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid AND status='open') THEN PERFORM game.rule_error('Club selection is closed'); END IF;
 IF (SELECT count(*) FROM game.draws WHERE season_id=sid AND member_id=mid)>=r.rerolls+1 THEN PERFORM game.rule_error('No rerolls remaining'); END IF;
 SELECT c.id INTO target FROM game.clubs c WHERE c.tournament_id=tid AND NOT EXISTS(SELECT 1 FROM game.assignments aa WHERE aa.club_id=c.id AND aa.ended_at IS NULL) ORDER BY random() LIMIT 1;
 IF target IS NULL THEN PERFORM game.rule_error('No clubs available'); END IF;
 PERFORM game.assign_club(tid,mid,target,key||':draw'); INSERT INTO game.draws(tournament_id,season_id,member_id,club_id) VALUES(tid,sid,mid,target);
 result:=jsonb_build_object('clubId',target);
 END IF;
 ELSIF p_action='league_start' THEN
 IF (SELECT phase FROM game.seasons WHERE id=sid)<>'assignment' OR EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid AND status='open') THEN PERFORM game.rule_error('Close market before starting league'); END IF;
 SELECT array_agg(club_id ORDER BY club_id) INTO clubs FROM game.assignments WHERE tournament_id=tid AND ended_at IS NULL;
 n:=coalesce(cardinality(clubs),0); IF n<2 THEN PERFORM game.rule_error('At least two clubs required'); END IF;
 IF EXISTS(SELECT 1 FROM game.assignments aa WHERE aa.tournament_id=tid AND aa.ended_at IS NULL AND (SELECT count(*) FROM game.contracts c WHERE c.club_id=aa.club_id AND c.ended_at IS NULL) NOT BETWEEN r.min_squad AND r.max_squad) THEN PERFORM game.rule_error('Invalid squad size'); END IF;
 INSERT INTO game.entrants(tournament_id,season_id,club_id) SELECT tid,sid,unnest(clubs);
 IF n%2=1 THEN clubs:=array_append(clubs,NULL::uuid); n:=n+1; END IF;
 legs:=coalesce((p_body->>'legs')::integer,2); IF legs NOT IN(1,2) THEN RAISE EXCEPTION 'Invalid legs'; END IF;
 FOR k IN 1..legs LOOP FOR i IN 1..n-1 LOOP
 rr:=(k-1)*(n-1)+i; INSERT INTO game.rounds VALUES(tid,sid,rr,NULL);
 FOR j IN 1..n/2 LOOP h:=clubs[j]; a:=clubs[n-j+1];
 IF (i+j+k)%2=0 THEN swap:=h; h:=a; a:=swap; END IF;
 IF h IS NOT NULL AND a IS NOT NULL THEN INSERT INTO game.fixtures(tournament_id,season_id,round,home_club_id,away_club_id) VALUES(tid,sid,rr,h,a); END IF;
 END LOOP;
 clubs:=ARRAY[clubs[1],clubs[n]]||clubs[2:n-1];
 END LOOP; END LOOP;
 UPDATE game.seasons SET phase='league' WHERE id=sid;
 ELSIF p_action IN('lineup','result_submit','result_confirm','result_dispute','result_force','forfeit') THEN
 SELECT * INTO f FROM game.fixtures WHERE id=(p_body->>'fixtureId')::uuid AND tournament_id=tid AND season_id=sid FOR UPDATE;
 IF NOT FOUND THEN PERFORM game.rule_error('Fixture not found'); END IF;
 IF f.status IN('finished','forfeit') THEN PERFORM game.rule_error('Fixture already finished'); END IF;
 IF f.round<>round_now OR EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid AND status='open') THEN PERFORM game.rule_error('Fixture is not available in this phase'); END IF;
 IF mid IS NOT NULL AND club IS DISTINCT FROM f.home_club_id AND club IS DISTINCT FROM f.away_club_id THEN RAISE EXCEPTION 'Not a fixture participant' USING ERRCODE='28000'; END IF;
 IF p_action='lineup' THEN
 IF f.status<>'scheduled' OR EXISTS(SELECT 1 FROM game.lineup_confirmations WHERE fixture_id=f.id AND club_id=club) THEN PERFORM game.rule_error('Lineup already frozen'); END IF;
 IF p_body ? 'players' THEN SELECT array_agg(value::uuid) INTO players FROM jsonb_array_elements_text(p_body->'players');
 ELSE SELECT array_agg(c.player_id) INTO players FROM game.contracts c WHERE c.club_id=club AND c.ended_at IS NULL AND NOT EXISTS(SELECT 1 FROM game.suspensions s WHERE s.season_id=sid AND s.player_id=c.player_id AND s.expired_at IS NULL AND (SELECT count(*) FROM game.suspension_servings ss WHERE ss.suspension_id=s.id)<s.matches); END IF;
 IF EXISTS(SELECT 1 FROM unnest(players) pp WHERE NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=tid AND c.club_id=club AND c.player_id=pp AND c.ended_at IS NULL)) THEN RAISE EXCEPTION 'Invalid lineup'; END IF;
 IF EXISTS(SELECT 1 FROM game.suspensions s WHERE s.season_id=sid AND s.player_id=ANY(players) AND s.expired_at IS NULL AND (SELECT count(*) FROM game.suspension_servings ss WHERE ss.suspension_id=s.id)<s.matches) THEN PERFORM game.rule_error('Suspended player in lineup'); END IF;
 INSERT INTO game.lineups SELECT tid,f.id,club,c.player_id,p.name,p.ovr,p.position,c.acquired_price,coalesce(c.player_id=ANY(players),false) FROM game.contracts c JOIN game.players p ON p.tournament_id=c.tournament_id AND p.player_id=c.player_id WHERE c.club_id=club AND c.ended_at IS NULL;
 INSERT INTO game.lineup_confirmations VALUES(tid,f.id,club);
 IF (SELECT count(*) FROM game.lineup_confirmations WHERE fixture_id=f.id)=2 THEN UPDATE game.fixtures SET status='playing' WHERE id=f.id; END IF;
 ELSIF p_action='result_submit' THEN
 IF f.status<>'playing' THEN PERFORM game.rule_error('Confirm both lineups first'); END IF;
 IF f.proposer_club_id IS NOT NULL AND f.proposer_club_id<>club THEN PERFORM game.rule_error('Confirm or dispute existing result'); END IF;
 IF coalesce((p_body->>'homeGoals')::integer,-1) NOT BETWEEN 0 AND 99 OR coalesce((p_body->>'awayGoals')::integer,-1) NOT BETWEEN 0 AND 99 OR jsonb_typeof(coalesce(p_body->'cards','[]'))<>'array' THEN RAISE EXCEPTION 'Invalid result'; END IF;
 UPDATE game.fixtures SET proposal=jsonb_build_object('homeGoals',p_body->'homeGoals','awayGoals',p_body->'awayGoals','cards',coalesce(p_body->'cards','[]')),proposer_club_id=club WHERE id=f.id;
 ELSIF p_action IN('result_confirm','result_dispute') THEN
 IF f.proposal IS NULL OR f.proposer_club_id=club THEN PERFORM game.rule_error('Other club must confirm result'); END IF;
 IF p_action='result_dispute' THEN UPDATE game.fixtures SET proposal=NULL,proposer_club_id=NULL WHERE id=f.id;
 ELSE PERFORM game.finish_fixture(f.id,(f.proposal->>'homeGoals')::integer,(f.proposal->>'awayGoals')::integer,f.proposal->'cards'); END IF;
 ELSIF p_action='result_force' THEN PERFORM game.finish_fixture(f.id,(p_body->>'homeGoals')::integer,(p_body->>'awayGoals')::integer,coalesce(p_body->'cards','[]'));
 ELSE
 IF NOT EXISTS(SELECT 1 FROM game.entrants e WHERE e.season_id=sid AND e.club_id IN(f.home_club_id,f.away_club_id) AND e.replacement_due<=clock_timestamp() AND NOT EXISTS(SELECT 1 FROM game.assignments aa WHERE aa.club_id=e.club_id AND aa.ended_at IS NULL)) THEN PERFORM game.rule_error('Replacement deadline not reached'); END IF;
 h:=CASE WHEN EXISTS(SELECT 1 FROM game.assignments WHERE club_id=f.home_club_id AND ended_at IS NULL) THEN f.home_club_id END;
 a:=CASE WHEN EXISTS(SELECT 1 FROM game.assignments WHERE club_id=f.away_club_id AND ended_at IS NULL) THEN f.away_club_id END;
 PERFORM game.finish_fixture(f.id,CASE WHEN h IS NULL THEN 0 ELSE 3 END,CASE WHEN a IS NULL THEN 0 ELSE 3 END,'[]',true);
 END IF;
 ELSIF p_action='round_close' THEN
 IF round_now IS NULL OR EXISTS(SELECT 1 FROM game.fixtures WHERE season_id=sid AND round=round_now AND status NOT IN('finished','forfeit')) OR EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid AND status='open') THEN PERFORM game.rule_error('Finish all round matches first'); END IF;
 UPDATE game.rounds SET closed_at=clock_timestamp() WHERE season_id=sid AND number=round_now;
 IF NOT EXISTS(SELECT 1 FROM game.rounds WHERE season_id=sid AND closed_at IS NULL) THEN
 UPDATE game.seasons SET phase='finished' WHERE id=sid; UPDATE game.suspensions SET expired_at=clock_timestamp() WHERE season_id=sid AND expired_at IS NULL;
 END IF;
 ELSIF p_action='season_next' THEN
 IF (SELECT phase FROM game.seasons WHERE id=sid)<>'finished' THEN PERFORM game.rule_error('Finish league before next season'); END IF;
 target:=game.advance_season(tid,key||':season');
 FOR item IN SELECT id FROM game.clubs WHERE tournament_id=tid LOOP
 credit:=r.season_income;
 IF credit>0 THEN PERFORM game.cash(tid,item.id,credit,'season_income','season-income:'||target||':'||item.id); END IF;
 END LOOP; result:=jsonb_build_object('seasonId',target);
 ELSIF p_action='pay_debt' THEN
 IF club IS NULL THEN PERFORM game.rule_error('Choose a club first'); END IF;
 SELECT amount INTO credit FROM game.debts WHERE tournament_id=tid AND club_id=club;credit:=coalesce(credit,0);
 SELECT least(credit,balance-reserved) INTO credit FROM game.accounts WHERE tournament_id=tid AND club_id=club;
 PERFORM game.cash(tid,club,-credit,'debt_payment',key||':debt'); UPDATE game.debts SET amount=amount-credit WHERE tournament_id=tid AND club_id=club;
 ELSIF p_action IN('leave','replace') THEN
 IF EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid AND status='open') OR EXISTS(SELECT 1 FROM game.fixtures WHERE tournament_id=tid AND status='playing') THEN PERFORM game.rule_error('Close market and finish active matches first'); END IF;
 IF p_action='leave' THEN
 INSERT INTO game.departures VALUES(tid,mid,clock_timestamp());
 UPDATE game.assignments SET ended_at=clock_timestamp() WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 UPDATE game.entrants SET abandoned_at=clock_timestamp(),replacement_due=clock_timestamp()+make_interval(days=>r.replacement_days) WHERE season_id=sid AND club_id=club;
 ELSE
 target:=(p_body->>'memberId')::uuid; club:=(p_body->>'clubId')::uuid;
 IF NOT EXISTS(SELECT 1 FROM public.members m WHERE m.tournament_id=tid AND m.id=target AND NOT EXISTS(SELECT 1 FROM game.departures d WHERE d.member_id=m.id)) OR EXISTS(SELECT 1 FROM game.assignments WHERE tournament_id=tid AND member_id=target AND ended_at IS NULL) THEN PERFORM game.rule_error('Replacement member unavailable'); END IF;
 PERFORM game.assign_club(tid,target,club,key||':replace'); UPDATE game.entrants SET abandoned_at=NULL,replacement_due=NULL WHERE season_id=sid AND club_id=club;
 END IF;
 ELSE RAISE EXCEPTION 'Invalid competition action'; END IF;
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,p_action,key,jsonb_build_object('action',p_action,'body',p_body),result);
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.game_auction_command(p_code text,p_token text,p_key uuid,p_action text,p_player uuid DEFAULT NULL,p_auction uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_minutes integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$ DECLARE tid uuid; mid uuid; club uuid; BEGIN
 IF p_action='auction_open' THEN tid:=game.require_admin(p_code,p_token); ELSE mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=tid) AND NOT EXISTS(SELECT 1 FROM game.operations WHERE tournament_id=tid AND idempotency_key='market:'||coalesce(mid::text,'admin')||':'||p_key) THEN
 IF p_action='auction_open' THEN PERFORM game.rule_error('Vote before opening auction'); END IF;
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 PERFORM game.ensure_purchase(tid,club);
 END IF; RETURN public.game_auction_command_core(p_code,p_token,p_key,p_action,p_player,p_auction,p_amount,p_minutes);
END $$;
CREATE OR REPLACE FUNCTION game.ensure_purchase(p_tournament uuid,p_club uuid) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM game.debts WHERE tournament_id=p_tournament AND club_id=p_club AND amount>0) THEN PERFORM game.rule_error('Outstanding club debt'); END IF;
 IF (SELECT count(*) FROM game.contracts WHERE tournament_id=p_tournament AND club_id=p_club AND ended_at IS NULL)+coalesce((SELECT sum(icons_held) FROM game.market_limits ml JOIN game.market_windows w ON w.id=ml.window_id WHERE ml.club_id=p_club AND w.status='open'),0)>=
 (SELECT max_squad FROM game.rules WHERE tournament_id=p_tournament) THEN PERFORM game.rule_error('Maximum squad reached'); END IF;
END $$;
CREATE FUNCTION game.guard_complete_contract() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF NEW.ended_at IS NULL AND EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=NEW.tournament_id) AND (SELECT count(*) FROM game.contracts WHERE club_id=NEW.club_id AND ended_at IS NULL AND id<>NEW.id)>=(SELECT max_squad FROM game.rules WHERE tournament_id=NEW.tournament_id) THEN PERFORM game.rule_error('Maximum squad reached'); END IF; RETURN NEW;
END $$;
CREATE TRIGGER complete_contract_limit BEFORE INSERT OR UPDATE ON game.contracts FOR EACH ROW EXECUTE FUNCTION game.guard_complete_contract();
CREATE FUNCTION game.guard_finished_activity() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF TG_OP='DELETE' OR OLD.status<>'pending' THEN RAISE EXCEPTION 'Activity history is immutable'; END IF; RETURN NEW;
END $$;
CREATE TRIGGER finished_spin_history BEFORE UPDATE OR DELETE ON game.spins FOR EACH ROW EXECUTE FUNCTION game.guard_finished_activity();
REVOKE ALL ON FUNCTION game.guard_complete_contract(),game.guard_finished_activity() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION game.guard_complete_contract(),game.guard_finished_activity() TO service_role;
NOTIFY pgrst,'reload schema';
