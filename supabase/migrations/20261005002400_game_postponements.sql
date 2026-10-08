-- Postponements are scoped to unfinished fixtures; completed history is untouched.
CREATE FUNCTION public.game_fixture_schedule(p_code text,p_token text,p_key uuid,p_fixture uuid,p_action text,p_cancel boolean DEFAULT false,p_force boolean DEFAULT false) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; club uuid; f game.fixtures; requested uuid; old game.operations; k text; payload jsonb; result jsonb;
BEGIN
 IF p_key IS NULL OR p_fixture IS NULL OR p_action IS NULL OR p_action NOT IN('postpone','reactivate') OR p_cancel IS NULL OR p_force IS NULL OR (p_cancel AND p_force) THEN PERFORM game.rule_error('Solicitud inválida'); END IF;
 IF p_force THEN tid:=game.require_admin(p_code,p_token);
 ELSE mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 k:='fixture-schedule:'||coalesce(mid::text,'admin')||':'||p_key;
 payload:=jsonb_build_object('fixtureId',p_fixture,'action',p_action,'cancel',p_cancel,'force',p_force);
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key=k;
 IF FOUND THEN
  IF old.payload<>payload THEN PERFORM game.rule_error('La clave de reintento pertenece a otra solicitud'); END IF;
  RETURN old.result;
 END IF;
 SELECT * INTO f FROM game.fixtures WHERE id=p_fixture AND tournament_id=tid FOR UPDATE;
 IF f.id IS NULL THEN PERFORM game.rule_error('Partido no encontrado'); END IF;
 IF NOT EXISTS(SELECT 1 FROM game.seasons WHERE id=f.season_id AND ended_at IS NULL AND phase='league') OR f.status IN('finished','forfeit') THEN PERFORM game.rule_error('El partido ya finalizó'); END IF;
 IF NOT p_force THEN
  SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND season_id=f.season_id AND member_id=mid AND ended_at IS NULL;
  IF club IS NULL OR club NOT IN(f.home_club_id,f.away_club_id) THEN RAISE EXCEPTION 'No eres participante de este partido' USING ERRCODE='28000'; END IF;
 END IF;
 IF (p_action='postpone' AND f.status='postponed') OR (p_action='reactivate' AND f.status<>'postponed') THEN PERFORM game.rule_error('El estado del partido cambió; actualiza el calendario'); END IF;
 requested:=CASE WHEN p_action='postpone' THEN f.postpone_requested_club_id ELSE f.reactivate_requested_club_id END;
 IF p_cancel THEN
  IF requested IS DISTINCT FROM club THEN PERFORM game.rule_error('No tienes una solicitud pendiente'); END IF;
  requested:=NULL; result:='{"ok":true,"cancelled":true}';
 ELSIF NOT p_force AND requested IS NULL THEN
  IF f.proposal IS NOT NULL THEN PERFORM game.rule_error('Confirma o disputa el resultado antes de aplazar'); END IF;
  requested:=club; result:='{"ok":true,"requested":true}';
 ELSIF NOT p_force AND requested=club THEN
  PERFORM game.rule_error('Tu solicitud ya está pendiente de aceptación');
 ELSE
  IF NOT p_force AND f.proposal IS NOT NULL THEN PERFORM game.rule_error('Confirma o disputa el resultado antes de aplazar'); END IF;
  UPDATE game.fixtures SET status=CASE WHEN p_action='postpone' THEN 'postponed' ELSE 'scheduled' END,
   proposal=NULL,proposer_club_id=NULL,postpone_requested_club_id=NULL,reactivate_requested_club_id=NULL WHERE id=f.id;
  DELETE FROM game.lineup_confirmations WHERE fixture_id=f.id;
  DELETE FROM game.lineups WHERE fixture_id=f.id;
  result:=jsonb_build_object('ok',true,'forced',p_force,'postponed',p_action='postpone','reactivated',p_action='reactivate');
 END IF;
 IF result ? 'requested' OR result ? 'cancelled' THEN
  IF p_action='postpone' THEN UPDATE game.fixtures SET postpone_requested_club_id=requested WHERE id=f.id;
  ELSE UPDATE game.fixtures SET reactivate_requested_club_id=requested WHERE id=f.id; END IF;
 END IF;
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'fixture_schedule',k,payload,result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_fixture_schedule(text,text,uuid,uuid,text,boolean,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_fixture_schedule(text,text,uuid,uuid,text,boolean,boolean) TO service_role;
ALTER TABLE game.fixtures DROP CONSTRAINT fixtures_status_check;
ALTER TABLE game.fixtures ADD CONSTRAINT fixtures_status_check CHECK(status IN('scheduled','playing','postponed','finished','forfeit'));
ALTER TABLE game.fixtures ADD COLUMN postpone_requested_club_id uuid, ADD COLUMN reactivate_requested_club_id uuid,
 ADD FOREIGN KEY(tournament_id,postpone_requested_club_id) REFERENCES game.clubs(tournament_id,id),
 ADD FOREIGN KEY(tournament_id,reactivate_requested_club_id) REFERENCES game.clubs(tournament_id,id),
 ADD CHECK(postpone_requested_club_id IS NULL OR postpone_requested_club_id IN(home_club_id,away_club_id)),
 ADD CHECK(reactivate_requested_club_id IS NULL OR reactivate_requested_club_id IN(home_club_id,away_club_id));
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
 IF f.status='postponed' AND p_action<>'forfeit' THEN PERFORM game.rule_error('Reactiva el partido antes de continuar'); END IF;
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
CREATE OR REPLACE FUNCTION public.game_competition_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; result jsonb; BEGIN
 mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 SELECT jsonb_build_object('enabled',r.tournament_id IS NOT NULL,'rules',to_jsonb(r),
 'phase',s.phase,'seasonId',s.id,'round',(SELECT min(number) FROM game.rounds WHERE season_id=s.id AND closed_at IS NULL),
 'rounds',coalesce((SELECT jsonb_agg(jsonb_build_object('number',rr.number,'closed',rr.closed_at IS NOT NULL) ORDER BY rr.number) FROM game.rounds rr WHERE rr.season_id=s.id),'[]'),
 'seasons',coalesce((SELECT jsonb_agg(jsonb_build_object('id',ss.id,'number',ss.number,'phase',ss.phase) ORDER BY ss.number) FROM game.seasons ss WHERE ss.tournament_id=tid),'[]'),
 'fixtures',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'seasonId',f.season_id,'round',f.round,'homeClubId',f.home_club_id,'awayClubId',f.away_club_id,'status',f.status,'homeGoals',f.home_goals,'awayGoals',f.away_goals,'proposal',f.proposal,'proposerClubId',f.proposer_club_id,
 'postponeRequestedClubId',f.postpone_requested_club_id,'reactivateRequestedClubId',f.reactivate_requested_club_id,
 'confirmedClubs',coalesce((SELECT jsonb_agg(club_id) FROM game.lineup_confirmations WHERE fixture_id=f.id),'[]'),
 'lineups',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',l.club_id,'playerId',l.player_id,'name',l.player_name,'ovr',l.ovr,'position',l.position,'price',l.price,'selected',l.selected) ORDER BY l.club_id,l.player_name) FROM game.lineups l WHERE l.fixture_id=f.id),'[]'),
 'cards',coalesce((SELECT jsonb_agg(jsonb_build_object('playerId',c.player_id,'kind',c.kind)) FROM game.cards c WHERE c.fixture_id=f.id),'[]'),
 'expenses',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',e.club_id,'playerId',e.player_id,'kind',e.kind,'amount',e.amount)) FROM game.expenses e WHERE e.fixture_id=f.id),'[]')) ORDER BY ss.number,f.round,f.id)
 FROM game.fixtures f JOIN game.seasons ss ON ss.id=f.season_id WHERE f.tournament_id=tid),'[]'),
 'suspensions',coalesce((SELECT jsonb_agg(jsonb_build_object('id',su.id,'seasonId',su.season_id,'playerId',su.player_id,'matches',su.matches,'served',(SELECT count(*) FROM game.suspension_servings sv WHERE sv.suspension_id=su.id),'expired',su.expired_at IS NOT NULL)) FROM game.suspensions su WHERE su.tournament_id=tid),'[]'),
 'releases',coalesce((SELECT jsonb_agg(jsonb_build_object('playerId',re.player_id,'clubId',re.club_id,'windowId',re.window_id,'refund',re.refund,'automatic',re.automatic,'createdAt',re.created_at) ORDER BY re.created_at) FROM game.releases re WHERE re.tournament_id=tid),'[]'),
 'daily',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',dc.club_id,'tier',dc.tier,'used',dc.used)) FROM (SELECT club_id,tier,count(*) used FROM game.daily_claims WHERE tournament_id=tid AND period=(clock_timestamp() AT TIME ZONE 'America/Bogota')::date GROUP BY club_id,tier) dc),'[]'),
 'debts',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',d.club_id,'amount',d.amount)) FROM game.debts d WHERE d.tournament_id=tid AND d.amount>0),'[]'),
 'departures',coalesce((SELECT jsonb_agg(member_id) FROM game.departures WHERE tournament_id=tid),'[]'),
 'entrants',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',e.club_id,'replacementDue',e.replacement_due)) FROM game.entrants e WHERE e.season_id=s.id),'[]'),
 'draws',coalesce((SELECT jsonb_agg(jsonb_build_object('memberId',d.member_id,'clubId',d.club_id,'seasonId',d.season_id)) FROM game.draws d WHERE d.tournament_id=tid),'[]'),
 'spins',coalesce((SELECT jsonb_agg(jsonb_build_object('id',sp.id,'clubId',sp.club_id,'playerId',sp.player_id,'status',CASE WHEN sp.status='pending' AND sp.expires_at<=clock_timestamp() THEN 'expired' ELSE sp.status END,'fee',sp.fee,'expiresAt',sp.expires_at) ORDER BY sp.expires_at DESC) FROM game.spins sp WHERE sp.tournament_id=tid AND sp.club_id IN(SELECT club_id FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL)),'[]'),
 'ballots',coalesce((SELECT jsonb_agg(jsonb_build_object('id',b.id,'windowId',b.window_id,'status',b.status,'endsAt',b.ends_at,'winner',b.winner,'auctionId',b.auction_id,
 'options',(SELECT jsonb_agg(jsonb_build_object('playerId',o.player_id,'name',p.name,'votes',(SELECT count(*) FROM game.votes v WHERE v.ballot_id=b.id AND v.player_id=o.player_id)) ORDER BY o.player_id) FROM game.ballot_options o JOIN game.players p ON p.tournament_id=o.tournament_id AND p.player_id=o.player_id WHERE o.ballot_id=b.id),
 'votedClubs',coalesce((SELECT jsonb_agg(v.club_id) FROM game.votes v WHERE v.ballot_id=b.id),'[]'),'electorate',(SELECT count(*) FROM game.electorate WHERE ballot_id=b.id)) ORDER BY b.ends_at DESC) FROM game.ballots b WHERE b.tournament_id=tid),'[]'))
 INTO result FROM game.seasons s LEFT JOIN game.rules r ON r.tournament_id=s.tournament_id WHERE s.tournament_id=tid AND s.ended_at IS NULL;
 RETURN result;
END $$;
