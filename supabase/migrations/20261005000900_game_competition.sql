-- Complete competition mode is opt-in for earlier disposable market prototypes.
CREATE TABLE game.rules (
 tournament_id uuid PRIMARY KEY REFERENCES game.tournaments(id),
 min_squad integer NOT NULL DEFAULT 0 CHECK(min_squad BETWEEN 0 AND 35),
 max_squad integer NOT NULL DEFAULT 35 CHECK(max_squad BETWEEN 1 AND 60),
 daily_basic integer NOT NULL DEFAULT 2 CHECK(daily_basic BETWEEN 0 AND 10),
 daily_premium integer NOT NULL DEFAULT 1 CHECK(daily_premium BETWEEN 0 AND 10),
 rerolls integer NOT NULL DEFAULT 1 CHECK(rerolls BETWEEN 0 AND 5),
 winter_limit integer NOT NULL DEFAULT 2 CHECK(winter_limit BETWEEN 1 AND 10),
 season_income bigint NOT NULL DEFAULT 0 CHECK(season_income BETWEEN 0 AND 1000000000),
 spin_fee bigint NOT NULL DEFAULT 5000000 CHECK(spin_fee BETWEEN 0 AND 100000000),
 replacement_days integer NOT NULL DEFAULT 3 CHECK(replacement_days BETWEEN 1 AND 30),
 CHECK(min_squad<=max_squad)
);
ALTER TABLE game.seasons ADD COLUMN phase text NOT NULL DEFAULT 'assignment' CHECK(phase IN('assignment','league','finished'));
CREATE TABLE game.departures (
 tournament_id uuid NOT NULL, member_id uuid NOT NULL, left_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 PRIMARY KEY(tournament_id,member_id), FOREIGN KEY(tournament_id,member_id) REFERENCES public.members(tournament_id,id)
);
CREATE TABLE game.entrants (
 tournament_id uuid NOT NULL, season_id uuid NOT NULL, club_id uuid NOT NULL,
 abandoned_at timestamptz, replacement_due timestamptz,
 PRIMARY KEY(season_id,club_id),
 FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE TABLE game.rounds (
 tournament_id uuid NOT NULL, season_id uuid NOT NULL, number integer NOT NULL CHECK(number>0), closed_at timestamptz,
 PRIMARY KEY(season_id,number), FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id)
);
CREATE TABLE game.fixtures (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tournament_id uuid NOT NULL, season_id uuid NOT NULL,
 round integer NOT NULL, home_club_id uuid NOT NULL, away_club_id uuid NOT NULL CHECK(away_club_id<>home_club_id),
 status text NOT NULL DEFAULT 'scheduled' CHECK(status IN('scheduled','playing','finished','forfeit')),
 home_goals integer CHECK(home_goals BETWEEN 0 AND 99), away_goals integer CHECK(away_goals BETWEEN 0 AND 99),
 proposal jsonb, proposer_club_id uuid, finished_at timestamptz,
 UNIQUE(tournament_id,id), UNIQUE(season_id,home_club_id,away_club_id),
 FOREIGN KEY(season_id,round) REFERENCES game.rounds(season_id,number),
 FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id),
 FOREIGN KEY(season_id,home_club_id) REFERENCES game.entrants(season_id,club_id),
 FOREIGN KEY(season_id,away_club_id) REFERENCES game.entrants(season_id,club_id),
 FOREIGN KEY(tournament_id,home_club_id) REFERENCES game.clubs(tournament_id,id),
 FOREIGN KEY(tournament_id,away_club_id) REFERENCES game.clubs(tournament_id,id),
 FOREIGN KEY(tournament_id,proposer_club_id) REFERENCES game.clubs(tournament_id,id),
 CHECK((status IN('finished','forfeit'))=(finished_at IS NOT NULL AND home_goals IS NOT NULL AND away_goals IS NOT NULL))
);
CREATE INDEX fixture_calendar ON game.fixtures(tournament_id,season_id,round);
CREATE TABLE game.lineup_confirmations (
 tournament_id uuid NOT NULL, fixture_id uuid NOT NULL, club_id uuid NOT NULL,
 PRIMARY KEY(fixture_id,club_id), FOREIGN KEY(tournament_id,fixture_id) REFERENCES game.fixtures(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE TABLE game.lineups (
 tournament_id uuid NOT NULL, fixture_id uuid NOT NULL, club_id uuid NOT NULL, player_id uuid NOT NULL,
 player_name text NOT NULL, ovr integer NOT NULL, position text, price bigint NOT NULL CHECK(price>=0), selected boolean NOT NULL,
 PRIMARY KEY(fixture_id,player_id), FOREIGN KEY(tournament_id,fixture_id) REFERENCES game.fixtures(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id),
 FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE TABLE game.cards (
 tournament_id uuid NOT NULL, season_id uuid NOT NULL, fixture_id uuid NOT NULL, club_id uuid NOT NULL, player_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN('yellow','red')),
 PRIMARY KEY(fixture_id,player_id), FOREIGN KEY(tournament_id,fixture_id) REFERENCES game.fixtures(tournament_id,id),
 FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id),
 FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE TABLE game.suspensions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tournament_id uuid NOT NULL, season_id uuid NOT NULL,
 player_id uuid NOT NULL, origin_fixture_id uuid NOT NULL, matches integer NOT NULL CHECK(matches IN(1,2)),
 expired_at timestamptz, UNIQUE(tournament_id,id), UNIQUE(origin_fixture_id,player_id),
 FOREIGN KEY(tournament_id,origin_fixture_id) REFERENCES game.fixtures(tournament_id,id),
 FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id),
 FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE TABLE game.suspension_servings (
 tournament_id uuid NOT NULL, suspension_id uuid NOT NULL, fixture_id uuid NOT NULL, club_id uuid NOT NULL,
 PRIMARY KEY(suspension_id,fixture_id), FOREIGN KEY(tournament_id,suspension_id) REFERENCES game.suspensions(tournament_id,id),
 FOREIGN KEY(tournament_id,fixture_id) REFERENCES game.fixtures(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE TABLE game.releases (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tournament_id uuid NOT NULL, season_id uuid NOT NULL,
 window_id uuid, club_id uuid NOT NULL, player_id uuid NOT NULL, operation_id uuid NOT NULL UNIQUE,
 refund bigint NOT NULL CHECK(refund>=0), automatic boolean NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id),
 FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id),
 FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id),
 FOREIGN KEY(tournament_id,operation_id) REFERENCES game.operations(tournament_id,id)
);
CREATE INDEX released_player ON game.releases(tournament_id,player_id,created_at);
CREATE TABLE game.daily_claims (
 tournament_id uuid NOT NULL, club_id uuid NOT NULL, period date NOT NULL, tier text NOT NULL CHECK(tier IN('basic','premium')),
 operation_id uuid PRIMARY KEY, FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id),
 FOREIGN KEY(tournament_id,operation_id) REFERENCES game.operations(tournament_id,id)
);
CREATE INDEX daily_claim_count ON game.daily_claims(tournament_id,club_id,period,tier);
CREATE TABLE game.draws (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tournament_id uuid NOT NULL, season_id uuid NOT NULL, member_id uuid NOT NULL,
 club_id uuid NOT NULL, used_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id),
 FOREIGN KEY(tournament_id,member_id) REFERENCES public.members(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE TABLE game.debts (
 tournament_id uuid NOT NULL, club_id uuid NOT NULL, amount bigint NOT NULL DEFAULT 0 CHECK(amount>=0),
 PRIMARY KEY(tournament_id,club_id), FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE TABLE game.expenses (
 tournament_id uuid NOT NULL, fixture_id uuid NOT NULL, club_id uuid NOT NULL, player_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN('salary','yellow','red')), amount bigint NOT NULL CHECK(amount>0),
 PRIMARY KEY(fixture_id,player_id,kind), FOREIGN KEY(tournament_id,fixture_id) REFERENCES game.fixtures(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id),
 FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);

CREATE FUNCTION game.rule_error(p_message text) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
BEGIN RAISE EXCEPTION '%',p_message USING ERRCODE='GM001'; END $$;
CREATE FUNCTION game.require_admin(p_code text,p_token text) RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; BEGIN
 SELECT t.id INTO tid FROM public.tournaments t JOIN game.tournaments g ON g.id=t.id
 WHERE t.code=upper(p_code) AND t.status='prototype' AND t.admin_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
 IF tid IS NULL THEN RAISE EXCEPTION 'Invalid admin token' USING ERRCODE='28000'; END IF; RETURN tid;
END $$;
CREATE OR REPLACE FUNCTION game.require_member(p_code text,p_token text) RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid; BEGIN
 SELECT m.id INTO mid FROM public.members m JOIN public.tournaments t ON t.id=m.tournament_id JOIN game.tournaments g ON g.id=t.id
 WHERE t.code=upper(p_code) AND t.status='prototype' AND m.member_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex')
 AND NOT EXISTS(SELECT 1 FROM game.departures d WHERE d.member_id=m.id);
 IF mid IS NULL THEN RAISE EXCEPTION 'Invalid member token' USING ERRCODE='28000'; END IF; RETURN mid;
END $$;
CREATE FUNCTION game.cash(p_tournament uuid,p_club uuid,p_amount bigint,p_kind text,p_key text,p_payload jsonb DEFAULT '{}')
RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $$
DECLARE op uuid; acc uuid; clearing uuid; BEGIN
 SELECT id INTO op FROM game.operations WHERE tournament_id=p_tournament AND idempotency_key=p_key;
 IF op IS NOT NULL THEN RETURN op; END IF;
 PERFORM 1 FROM game.accounts WHERE tournament_id=p_tournament AND (club_id=p_club OR club_id IS NULL) ORDER BY id FOR UPDATE;
 SELECT id INTO acc FROM game.accounts WHERE tournament_id=p_tournament AND club_id=p_club;
 SELECT id INTO clearing FROM game.accounts WHERE tournament_id=p_tournament AND club_id IS NULL;
 IF p_amount<0 AND NOT EXISTS(SELECT 1 FROM game.accounts WHERE id=acc AND balance-reserved>=-p_amount) THEN PERFORM game.rule_error('Insufficient available balance'); END IF;
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(p_tournament,p_kind,p_key,p_payload,'{}') RETURNING id INTO op;
 IF p_amount<>0 THEN
 UPDATE game.accounts SET balance=balance+p_amount WHERE id=acc;
 UPDATE game.accounts SET balance=balance-p_amount WHERE id=clearing;
 INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES(p_tournament,op,acc,p_amount),(p_tournament,op,clearing,-p_amount);
 END IF; RETURN op;
END $$;
CREATE FUNCTION game.release_contract(p_contract uuid,p_key text,p_automatic boolean) RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $$
DECLARE ct game.contracts; sid uuid; wid uuid; refund bigint; op uuid; item record; BEGIN
 SELECT * INTO ct FROM game.contracts WHERE id=p_contract AND ended_at IS NULL FOR UPDATE;
 IF NOT FOUND THEN PERFORM game.rule_error('Player is no longer owned'); END IF;
 SELECT id INTO sid FROM game.seasons WHERE tournament_id=ct.tournament_id AND ended_at IS NULL;
 SELECT id INTO wid FROM game.market_windows WHERE tournament_id=ct.tournament_id AND season_id=sid ORDER BY opens_at DESC LIMIT 1;
 IF NOT p_automatic AND (SELECT count(*) FROM game.contracts WHERE tournament_id=ct.tournament_id AND club_id=ct.club_id AND ended_at IS NULL)<=
 (SELECT min_squad FROM game.rules WHERE tournament_id=ct.tournament_id) THEN PERFORM game.rule_error('Minimum squad reached'); END IF;
 FOR item IN SELECT id FROM game.offers WHERE tournament_id=ct.tournament_id AND player_id=ct.player_id AND status='pending' LOOP PERFORM game.release_offer(item.id,'stale'); END LOOP;
 refund:=CASE WHEN p_automatic THEN ct.acquired_price/2 ELSE 0 END;
 op:=game.cash(ct.tournament_id,ct.club_id,refund,CASE WHEN p_automatic THEN 'auto_release' ELSE 'release' END,p_key,jsonb_build_object('player',ct.player_id,'club',ct.club_id));
 UPDATE game.contracts SET ended_at=clock_timestamp() WHERE id=ct.id;
 INSERT INTO game.releases(tournament_id,season_id,window_id,club_id,player_id,operation_id,refund,automatic)
 VALUES(ct.tournament_id,sid,wid,ct.club_id,ct.player_id,op,refund,p_automatic); RETURN op;
END $$;
CREATE FUNCTION game.finish_fixture(p_fixture uuid,p_home integer,p_away integer,p_cards jsonb,p_forfeit boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE f game.fixtures; row record; ct uuid; charge bigint; available bigint; carried bigint; paid bigint; games integer; op uuid; BEGIN
 SELECT * INTO f FROM game.fixtures WHERE id=p_fixture FOR UPDATE;
 IF f.status IN('finished','forfeit') THEN PERFORM game.rule_error('Fixture already finished'); END IF;
 IF p_home NOT BETWEEN 0 AND 99 OR p_away NOT BETWEEN 0 AND 99 OR p_home IS NULL OR p_away IS NULL OR jsonb_typeof(p_cards)<>'array' THEN RAISE EXCEPTION 'Invalid result'; END IF;
 IF NOT p_forfeit THEN
 IF f.status<>'playing' THEN PERFORM game.rule_error('Confirm both lineups first'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_cards) x WHERE (x->>'kind') NOT IN('yellow','red') OR NOT EXISTS(SELECT 1 FROM game.lineups l WHERE l.fixture_id=f.id AND l.player_id=(x->>'playerId')::uuid AND l.selected)) THEN RAISE EXCEPTION 'Invalid cards'; END IF;
 -- Serve existing sanctions before creating the sanctions originating in this match.
 INSERT INTO game.suspension_servings(tournament_id,suspension_id,fixture_id,club_id)
 SELECT f.tournament_id,s.id,f.id,c.club_id FROM game.suspensions s JOIN game.contracts c ON c.tournament_id=s.tournament_id AND c.player_id=s.player_id AND c.ended_at IS NULL
 WHERE s.season_id=f.season_id AND s.expired_at IS NULL AND c.club_id IN(f.home_club_id,f.away_club_id)
 AND (SELECT count(*) FROM game.suspension_servings ss WHERE ss.suspension_id=s.id)<s.matches
 AND NOT EXISTS(SELECT 1 FROM game.lineups l WHERE l.fixture_id=f.id AND l.player_id=s.player_id AND l.selected);
 -- Two yellows become one red; a direct red also wins. Input duplicates never charge twice.
 INSERT INTO game.cards(tournament_id,season_id,fixture_id,club_id,player_id,kind)
 SELECT f.tournament_id,f.season_id,f.id,l.club_id,l.player_id,
 CASE WHEN bool_or(x->>'kind'='red') OR count(*)>=2 THEN 'red' ELSE 'yellow' END
 FROM jsonb_array_elements(p_cards) x JOIN game.lineups l ON l.fixture_id=f.id AND l.player_id=(x->>'playerId')::uuid GROUP BY l.club_id,l.player_id;
 INSERT INTO game.suspensions(tournament_id,season_id,player_id,origin_fixture_id,matches)
 SELECT c.tournament_id,c.season_id,c.player_id,f.id,CASE WHEN c.kind='red' THEN 2 ELSE 1 END FROM game.cards c
 WHERE c.fixture_id=f.id AND (c.kind='red' OR (SELECT count(*) FROM game.cards cc WHERE cc.season_id=f.season_id AND cc.player_id=c.player_id AND cc.kind='yellow')%3=0);
 SELECT count(*) INTO games FROM game.fixtures WHERE season_id=f.season_id AND (home_club_id=f.home_club_id OR away_club_id=f.home_club_id);
 INSERT INTO game.expenses(tournament_id,fixture_id,club_id,player_id,kind,amount)
 SELECT f.tournament_id,f.id,club_id,player_id,'salary',floor(price::numeric/10/greatest(1,games))::bigint FROM game.lineups WHERE fixture_id=f.id AND floor(price::numeric/10/greatest(1,games))>0;
 INSERT INTO game.expenses(tournament_id,fixture_id,club_id,player_id,kind,amount)
 SELECT f.tournament_id,f.id,club_id,player_id,kind,CASE WHEN kind='red' THEN 2000000 ELSE 500000 END FROM game.cards WHERE fixture_id=f.id;
 FOR row IN SELECT unnest(ARRAY[f.home_club_id,f.away_club_id]) AS club LOOP
 SELECT coalesce(sum(amount),0) INTO charge FROM game.expenses WHERE fixture_id=f.id AND club_id=row.club;
 SELECT coalesce((SELECT amount FROM game.debts WHERE tournament_id=f.tournament_id AND club_id=row.club),0) INTO carried; charge:=charge+carried;
 SELECT balance-reserved INTO available FROM game.accounts WHERE tournament_id=f.tournament_id AND club_id=row.club;
 WHILE available<charge LOOP
 SELECT id INTO ct FROM game.contracts WHERE tournament_id=f.tournament_id AND club_id=row.club AND ended_at IS NULL AND acquired_price>1 ORDER BY acquired_price DESC,id LIMIT 1;
 EXIT WHEN ct IS NULL;
 PERFORM game.release_contract(ct,'auto-release:'||f.id||':'||ct,true);
 SELECT balance-reserved INTO available FROM game.accounts WHERE tournament_id=f.tournament_id AND club_id=row.club;
 END LOOP;
 paid:=least(charge,available);
 op:=game.cash(f.tournament_id,row.club,-paid,'match_expenses','fixture-finance:'||f.id||':'||row.club,jsonb_build_object('fixture',f.id,'due',charge,'paid',paid));
 INSERT INTO game.debts VALUES(f.tournament_id,row.club,charge-paid) ON CONFLICT(tournament_id,club_id) DO UPDATE SET amount=EXCLUDED.amount;
 END LOOP;
 END IF;
 UPDATE game.fixtures SET status=CASE WHEN p_forfeit THEN 'forfeit' ELSE 'finished' END,home_goals=p_home,away_goals=p_away,finished_at=clock_timestamp(),proposal=NULL,proposer_club_id=NULL WHERE id=f.id;
END $$;

CREATE FUNCTION public.game_create_competition(p_key uuid,p_name text,p_display_name text,p_admin_token text,p_member_token text,p_teams uuid[],p_free_players uuid[])
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$ DECLARE result jsonb; BEGIN
 result:=public.game_create_tournament(p_key,p_name,p_display_name,p_admin_token,p_member_token,p_teams,p_free_players);
 INSERT INTO game.rules(tournament_id) VALUES((result->>'id')::uuid) ON CONFLICT DO NOTHING; RETURN result;
END $$;
CREATE FUNCTION public.game_competition_command(p_code text,p_token text,p_key uuid,p_action text,p_body jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; club uuid; sid uuid; actor text; key text; old game.operations; result jsonb:='{}'; r game.rules;
 f game.fixtures; ct uuid; clubs uuid[]; n integer; legs integer; i integer; j integer; k integer; rr integer; h uuid; a uuid; swap uuid;
 round_now integer; fixture uuid; item record; players uuid[]; target uuid; credit bigint; BEGIN
 IF p_key IS NULL OR p_action IS NULL OR jsonb_typeof(p_body)<>'object' THEN RAISE EXCEPTION 'Invalid command'; END IF;
 IF p_action IN('configure','league_start','round_close','result_force','replace','forfeit','season_next') THEN tid:=game.require_admin(p_code,p_token); actor:='admin';
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

-- Finalized results and their snapshots never change when the roster changes.
CREATE FUNCTION game.guard_fixture_history() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF TG_OP='DELETE' OR OLD.status IN('finished','forfeit') THEN RAISE EXCEPTION 'Fixture history is immutable'; END IF; RETURN NEW;
END $$;
CREATE TRIGGER fixture_history BEFORE UPDATE OR DELETE ON game.fixtures FOR EACH ROW EXECUTE FUNCTION game.guard_fixture_history();
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['lineups','lineup_confirmations','cards','suspension_servings','releases','daily_claims','draws','expenses','departures'] LOOP
 EXECUTE format('CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON game.%I FOR EACH ROW EXECUTE FUNCTION game.immutable_history()',name);
 END LOOP;
 FOR name IN SELECT tablename FROM pg_tables WHERE schemaname='game' LOOP EXECUTE format('ALTER TABLE game.%I ENABLE ROW LEVEL SECURITY',name); END LOOP;
END $$;
REVOKE ALL ON ALL TABLES IN SCHEMA game FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA game FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON ALL TABLES IN SCHEMA game TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA game TO service_role;
REVOKE ALL ON FUNCTION public.game_create_competition(uuid,text,text,text,text,uuid[],uuid[]),public.game_competition_command(text,text,uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_create_competition(uuid,text,text,text,text,uuid[],uuid[]),public.game_competition_command(text,text,uuid,text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
