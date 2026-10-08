CREATE TABLE game.ballots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tournament_id uuid NOT NULL, window_id uuid NOT NULL,
 status text NOT NULL DEFAULT 'open' CHECK(status IN('open','chosen','cancelled')),
 ends_at timestamptz NOT NULL, auction_minutes integer NOT NULL CHECK(auction_minutes BETWEEN 1 AND 1440),
 winner uuid, auction_id uuid, UNIQUE(tournament_id,id),
 FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
 FOREIGN KEY(tournament_id,winner) REFERENCES game.players(tournament_id,player_id),
 FOREIGN KEY(tournament_id,auction_id) REFERENCES game.auctions(tournament_id,id)
);
CREATE UNIQUE INDEX one_open_ballot ON game.ballots(window_id) WHERE status='open';
CREATE TABLE game.ballot_options (
 tournament_id uuid NOT NULL, ballot_id uuid NOT NULL, player_id uuid NOT NULL,
 PRIMARY KEY(ballot_id,player_id), FOREIGN KEY(tournament_id,ballot_id) REFERENCES game.ballots(tournament_id,id),
 FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE TABLE game.electorate (
 tournament_id uuid NOT NULL, ballot_id uuid NOT NULL, club_id uuid NOT NULL,
 PRIMARY KEY(ballot_id,club_id), FOREIGN KEY(tournament_id,ballot_id) REFERENCES game.ballots(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE TABLE game.votes (
 tournament_id uuid NOT NULL, ballot_id uuid NOT NULL, club_id uuid NOT NULL, player_id uuid NOT NULL,
 PRIMARY KEY(ballot_id,club_id), FOREIGN KEY(ballot_id,club_id) REFERENCES game.electorate(ballot_id,club_id),
 FOREIGN KEY(ballot_id,player_id) REFERENCES game.ballot_options(ballot_id,player_id),
 FOREIGN KEY(tournament_id,ballot_id) REFERENCES game.ballots(tournament_id,id)
);
CREATE TABLE game.spins (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tournament_id uuid NOT NULL, window_id uuid NOT NULL, club_id uuid NOT NULL,
 player_id uuid NOT NULL, fee bigint NOT NULL CHECK(fee>=0), expires_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','claimed','rejected','expired')),
 UNIQUE(tournament_id,id), FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id),
 FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE UNIQUE INDEX one_pending_spin ON game.spins(window_id,club_id) WHERE status='pending';

CREATE FUNCTION game.eligible_free(p_tournament uuid,p_club uuid,p_player uuid,p_window uuid) RETURNS boolean
LANGUAGE sql STABLE SET search_path='' AS $$
 SELECT EXISTS(SELECT 1 FROM game.players p WHERE p.tournament_id=p_tournament AND p.player_id=p_player AND NOT p.is_icon)
 AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p_tournament AND c.player_id=p_player AND c.ended_at IS NULL)
 AND NOT EXISTS(SELECT 1 FROM game.releases rr WHERE rr.tournament_id=p_tournament AND rr.player_id=p_player
 AND ((rr.created_at AT TIME ZONE 'America/Bogota')::date >= (statement_timestamp() AT TIME ZONE 'America/Bogota')::date
 OR (rr.club_id=p_club AND rr.window_id IS NOT DISTINCT FROM p_window)))
$$;
CREATE FUNCTION game.ensure_purchase(p_tournament uuid,p_club uuid) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM game.debts WHERE tournament_id=p_tournament AND club_id=p_club AND amount>0) THEN PERFORM game.rule_error('Outstanding club debt'); END IF;
 IF (SELECT count(*) FROM game.contracts WHERE tournament_id=p_tournament AND club_id=p_club AND ended_at IS NULL)>=
 (SELECT max_squad FROM game.rules WHERE tournament_id=p_tournament) THEN PERFORM game.rule_error('Maximum squad reached'); END IF;
END $$;
CREATE FUNCTION game.finish_ballot(p_ballot uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE b game.ballots; w game.market_windows; v_winner uuid; auction uuid; price bigint; BEGIN
 SELECT * INTO b FROM game.ballots WHERE id=p_ballot FOR UPDATE;
 IF b.status<>'open' THEN RETURN jsonb_build_object('auctionId',b.auction_id); END IF;
 SELECT * INTO w FROM game.market_windows WHERE id=b.window_id;
 IF w.status<>'open' OR w.closes_at<=clock_timestamp() THEN UPDATE game.ballots SET status='cancelled' WHERE id=b.id; RETURN '{}'; END IF;
 -- Deterministic ties (UUID), including no votes: the entire candidate list is retained.
 SELECT o.player_id INTO v_winner FROM game.ballot_options o WHERE o.ballot_id=b.id
 AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=b.tournament_id AND c.player_id=o.player_id AND c.ended_at IS NULL)
 ORDER BY (SELECT count(*) FROM game.votes v WHERE v.ballot_id=b.id AND v.player_id=o.player_id) DESC,o.player_id LIMIT 1;
 IF v_winner IS NULL THEN UPDATE game.ballots SET status='cancelled' WHERE id=b.id; RETURN '{}'; END IF;
 SELECT reference_price INTO price FROM game.players WHERE tournament_id=b.tournament_id AND player_id=v_winner;
 INSERT INTO game.auctions(tournament_id,window_id,player_id,min_bid,starts_at,ends_at)
 VALUES(b.tournament_id,b.window_id,v_winner,greatest(5000000,price),clock_timestamp(),least(w.closes_at,clock_timestamp()+make_interval(mins=>b.auction_minutes))) RETURNING id INTO auction;
 UPDATE game.ballots SET status='chosen',winner=v_winner,auction_id=auction WHERE id=b.id;
 RETURN jsonb_build_object('auctionId',auction,'playerId',v_winner);
END $$;
CREATE FUNCTION public.game_activity_command(p_code text,p_token text,p_key uuid,p_action text,p_body jsonb DEFAULT '{}')
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
 INSERT INTO game.ballot_options SELECT tid,ballot,p.player_id FROM game.players p WHERE p.tournament_id=tid AND p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=tid AND c.player_id=p.player_id AND c.ended_at IS NULL);
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

ALTER FUNCTION public.game_market_command(text,text,uuid,text,uuid,uuid,bigint,text,integer) RENAME TO game_market_command_core;
CREATE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,p_player uuid DEFAULT NULL,p_offer uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_minutes integer DEFAULT NULL)
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
 PERFORM game.ensure_purchase(tid,club);
 IF p_action='accept' THEN SELECT * INTO f FROM game.offers WHERE id=p_offer AND tournament_id=tid; PERFORM game.ensure_purchase(tid,f.buyer_club_id); END IF;
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
ALTER FUNCTION public.game_auction_command(text,text,uuid,text,uuid,uuid,bigint,integer) RENAME TO game_auction_command_core;
CREATE FUNCTION public.game_auction_command(p_code text,p_token text,p_key uuid,p_action text,p_player uuid DEFAULT NULL,p_auction uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_minutes integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$ DECLARE tid uuid; mid uuid; club uuid; BEGIN
 IF p_action='auction_open' THEN tid:=game.require_admin(p_code,p_token); ELSE mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=tid) THEN
 IF p_action='auction_open' THEN PERFORM game.rule_error('Vote before opening auction'); END IF;
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 PERFORM game.ensure_purchase(tid,club);
 END IF; RETURN public.game_auction_command_core(p_code,p_token,p_key,p_action,p_player,p_auction,p_amount,p_minutes);
END $$;
ALTER FUNCTION public.game_pay_clause(text,text,uuid,uuid) RENAME TO game_pay_clause_core;
CREATE FUNCTION public.game_pay_clause(p_code text,p_token text,p_key uuid,p_player uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid; tid uuid; club uuid; BEGIN
 mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=tid) AND NOT EXISTS(SELECT 1 FROM game.operations WHERE tournament_id=tid AND idempotency_key IN('market:'||mid||':'||p_key,'clause:'||mid||':'||p_key)) THEN
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL; PERFORM game.ensure_purchase(tid,club);
 END IF; RETURN public.game_pay_clause_core(p_code,p_token,p_key,p_player);
END $$;
ALTER FUNCTION public.game_choose_club(text,text,uuid,uuid) RENAME TO game_choose_club_core;
CREATE FUNCTION public.game_choose_club(p_code text,p_token text,p_club uuid,p_key uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid; tid uuid; BEGIN
 mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=tid) AND NOT EXISTS(SELECT 1 FROM game.operations WHERE tournament_id=tid AND idempotency_key='choose:'||mid||':'||p_key) THEN
 IF (SELECT phase FROM game.seasons WHERE tournament_id=tid AND ended_at IS NULL)<>'assignment' THEN PERFORM game.rule_error('Club selection is closed'); END IF;
 IF EXISTS(SELECT 1 FROM game.draws d JOIN game.seasons s ON s.id=d.season_id WHERE d.member_id=mid AND s.ended_at IS NULL) THEN PERFORM game.rule_error('Use reroll after roulette'); END IF;
 END IF; RETURN public.game_choose_club_core(p_code,p_token,p_club,p_key);
END $$;
ALTER FUNCTION public.game_next_season(text,text,uuid) RENAME TO game_next_season_core;
CREATE FUNCTION public.game_next_season(p_code text,p_token text,p_key uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$ DECLARE tid uuid; BEGIN
 tid:=game.require_admin(p_code,p_token); PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 IF EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=tid) THEN RETURN public.game_competition_command(p_code,p_token,p_key,'season_next'); END IF;
 RETURN public.game_next_season_core(p_code,p_token,p_key);
END $$;
ALTER FUNCTION public.game_expire_markets(integer) RENAME TO game_expire_markets_core;
CREATE FUNCTION public.game_expire_markets(p_limit integer DEFAULT 100) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE row record; b record; result jsonb; votes integer:=0; BEGIN
 IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 1000 THEN RAISE EXCEPTION 'Invalid worker limit'; END IF;
 FOR row IN SELECT g.id FROM game.tournaments g WHERE EXISTS(SELECT 1 FROM game.ballots bb WHERE bb.tournament_id=g.id AND bb.status='open' AND bb.ends_at<=clock_timestamp()) ORDER BY g.id LIMIT p_limit FOR UPDATE SKIP LOCKED LOOP
 FOR b IN SELECT id FROM game.ballots WHERE tournament_id=row.id AND status='open' AND ends_at<=clock_timestamp() LOOP PERFORM game.finish_ballot(b.id); votes:=votes+1; END LOOP;
 END LOOP;
 result:=public.game_expire_markets_core(p_limit);
 UPDATE game.spins s SET status='expired' WHERE status='pending' AND (expires_at<=clock_timestamp() OR EXISTS(SELECT 1 FROM game.market_windows w WHERE w.id=s.window_id AND w.status='closed'));
 RETURN result||jsonb_build_object('votesClosed',votes);
END $$;

CREATE FUNCTION public.game_competition_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; result jsonb; BEGIN
 mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 SELECT jsonb_build_object('enabled',r.tournament_id IS NOT NULL,'rules',to_jsonb(r),
 'phase',s.phase,'seasonId',s.id,'round',(SELECT min(number) FROM game.rounds WHERE season_id=s.id AND closed_at IS NULL),
 'rounds',coalesce((SELECT jsonb_agg(jsonb_build_object('number',rr.number,'closed',rr.closed_at IS NOT NULL) ORDER BY rr.number) FROM game.rounds rr WHERE rr.season_id=s.id),'[]'),
 'seasons',coalesce((SELECT jsonb_agg(jsonb_build_object('id',ss.id,'number',ss.number,'phase',ss.phase) ORDER BY ss.number) FROM game.seasons ss WHERE ss.tournament_id=tid),'[]'),
 'fixtures',coalesce((SELECT jsonb_agg(jsonb_build_object('id',f.id,'seasonId',f.season_id,'round',f.round,'homeClubId',f.home_club_id,'awayClubId',f.away_club_id,'status',f.status,'homeGoals',f.home_goals,'awayGoals',f.away_goals,'proposal',f.proposal,'proposerClubId',f.proposer_club_id,
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
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['ballot_options','electorate','votes'] LOOP EXECUTE format('CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON game.%I FOR EACH ROW EXECUTE FUNCTION game.immutable_history()',name); END LOOP;
 FOR name IN SELECT tablename FROM pg_tables WHERE schemaname='game' LOOP EXECUTE format('ALTER TABLE game.%I ENABLE ROW LEVEL SECURITY',name); END LOOP;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA game FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA game FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON ALL TABLES IN SCHEMA game TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA game TO service_role;
DO $$ DECLARE row record; BEGIN
 FOR row IN SELECT oid::regprocedure AS fn FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'game_%' LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',row.fn); EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role',row.fn);
 END LOOP;
END $$;
NOTIFY pgrst,'reload schema';
