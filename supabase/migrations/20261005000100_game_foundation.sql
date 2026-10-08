-- Foundation only: legacy application writes remain in public until the backend cutover.
-- No reconstruction of legacy budgets/transfers: initialize is for NEW tournaments only.
CREATE SCHEMA game;
REVOKE ALL ON SCHEMA game FROM PUBLIC, anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA game REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

CREATE TABLE game.tournaments (
  id uuid PRIMARY KEY REFERENCES public.tournaments(id) ON DELETE RESTRICT,
  initialized_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE game.clubs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES game.tournaments(id),
  team_id uuid NOT NULL REFERENCES public.teams(id),
  name text NOT NULL,
  crest_url text,
  UNIQUE (tournament_id, team_id),
  UNIQUE (tournament_id, id)
);
CREATE TABLE game.players (
  tournament_id uuid NOT NULL REFERENCES game.tournaments(id),
  player_id uuid NOT NULL REFERENCES public.players(id),
  name text NOT NULL,
  ovr integer NOT NULL,
  position text,
  is_icon boolean NOT NULL,
  reference_price bigint NOT NULL CHECK (reference_price >= 0),
  reference_clause bigint CHECK (reference_clause >= 0),
  PRIMARY KEY (tournament_id, player_id)
);
CREATE TABLE game.accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES game.tournaments(id),
  club_id uuid,
  balance bigint NOT NULL DEFAULT 0,
  reserved bigint NOT NULL DEFAULT 0 CHECK (reserved >= 0),
  CHECK ((club_id IS NULL AND reserved = 0) OR (club_id IS NOT NULL AND balance >= reserved)),
  UNIQUE (tournament_id, id),
  UNIQUE (tournament_id, club_id),
  FOREIGN KEY (tournament_id, club_id) REFERENCES game.clubs(tournament_id, id)
);
CREATE UNIQUE INDEX one_clearing_account ON game.accounts(tournament_id) WHERE club_id IS NULL;
CREATE TABLE game.seasons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES game.tournaments(id),
  number integer NOT NULL CHECK (number > 0),
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ended_at timestamptz,
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  UNIQUE (tournament_id, number),
  UNIQUE (tournament_id, id)
);
CREATE UNIQUE INDEX one_current_season ON game.seasons(tournament_id) WHERE ended_at IS NULL;
-- Standalone legacy member FK plus composite scope FK prevents cross-tournament assignment.
ALTER TABLE public.members ADD CONSTRAINT members_tournament_id_id_key UNIQUE (tournament_id, id);
CREATE TABLE game.assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL,
  season_id uuid NOT NULL,
  member_id uuid NOT NULL,
  club_id uuid NOT NULL,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ended_at timestamptz,
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  FOREIGN KEY (tournament_id, season_id) REFERENCES game.seasons(tournament_id, id),
  FOREIGN KEY (tournament_id, member_id) REFERENCES public.members(tournament_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (tournament_id, club_id) REFERENCES game.clubs(tournament_id, id)
);
CREATE UNIQUE INDEX one_current_club_per_member ON game.assignments(tournament_id, member_id) WHERE ended_at IS NULL;
CREATE UNIQUE INDEX one_current_member_per_club ON game.assignments(tournament_id, club_id) WHERE ended_at IS NULL;
CREATE INDEX assignment_history ON game.assignments(tournament_id, season_id, member_id);
CREATE TABLE game.contracts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL,
  player_id uuid NOT NULL,
  club_id uuid NOT NULL,
  acquired_price bigint NOT NULL CHECK (acquired_price >= 0),
  clause bigint CHECK (clause >= 0),
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ended_at timestamptz,
  CHECK (ended_at IS NULL OR ended_at >= started_at),
  FOREIGN KEY (tournament_id, player_id) REFERENCES game.players(tournament_id, player_id),
  FOREIGN KEY (tournament_id, club_id) REFERENCES game.clubs(tournament_id, id)
);
CREATE UNIQUE INDEX one_current_owner ON game.contracts(tournament_id, player_id) WHERE ended_at IS NULL;
CREATE INDEX club_squad ON game.contracts(tournament_id, club_id) WHERE ended_at IS NULL;
CREATE TABLE game.operations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES game.tournaments(id),
  kind text NOT NULL,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 1 AND 200),
  payload jsonb NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (tournament_id, id),
  UNIQUE (tournament_id, idempotency_key)
);
CREATE TABLE game.ledger (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tournament_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  account_id uuid NOT NULL,
  amount bigint NOT NULL CHECK (amount <> 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (tournament_id, operation_id) REFERENCES game.operations(tournament_id, id),
  FOREIGN KEY (tournament_id, account_id) REFERENCES game.accounts(tournament_id, id),
  UNIQUE (operation_id, account_id)
);
CREATE INDEX account_history ON game.ledger(tournament_id, account_id, id);

CREATE FUNCTION game.immutable_history() RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN RAISE EXCEPTION 'Financial history is immutable'; END $$;
CREATE TRIGGER immutable_ledger BEFORE UPDATE OR DELETE ON game.ledger FOR EACH ROW EXECUTE FUNCTION game.immutable_history();
CREATE TRIGGER immutable_operations BEFORE UPDATE OR DELETE ON game.operations FOR EACH ROW EXECUTE FUNCTION game.immutable_history();
CREATE FUNCTION game.check_balanced_operation() RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF (SELECT coalesce(sum(amount), 0) FROM game.ledger WHERE operation_id = NEW.operation_id) <> 0 THEN
    RAISE EXCEPTION 'Unbalanced operation';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER balanced_ledger AFTER INSERT ON game.ledger
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION game.check_balanced_operation();

CREATE FUNCTION game.initialize(p_tournament uuid, p_initial_budget bigint DEFAULT 200000000)
RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE v_operation uuid; v_clearing uuid;
BEGIN
  PERFORM 1 FROM public.tournaments WHERE id = p_tournament FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF p_initial_budget IS NULL OR p_initial_budget < 0 THEN RAISE EXCEPTION 'Invalid opening budget'; END IF;
  IF EXISTS(SELECT 1 FROM game.tournaments WHERE id = p_tournament) THEN
    IF NOT EXISTS(SELECT 1 FROM game.operations WHERE tournament_id=p_tournament
      AND idempotency_key='initialize' AND payload=jsonb_build_object('initial_budget',p_initial_budget)) THEN
      RAISE EXCEPTION 'Initialization parameters changed';
    END IF;
    RETURN;
  END IF;
  IF EXISTS(SELECT 1 FROM public.assignments WHERE tournament_id=p_tournament)
     OR EXISTS(SELECT 1 FROM public.market_sessions WHERE tournament_id=p_tournament)
     OR EXISTS(SELECT 1 FROM public.league_sessions WHERE tournament_id=p_tournament)
     OR EXISTS(SELECT 1 FROM public.members WHERE tournament_id=p_tournament AND budget IS NOT NULL) THEN
    RAISE EXCEPTION 'Existing game requires audited migration, not initialization';
  END IF;
  -- Serialize catalogue snapshot against legacy writes and fail on ambiguous base ownership.
  LOCK TABLE public.teams, public.players, public.team_players IN SHARE MODE;
  IF EXISTS(SELECT player_id FROM public.team_players GROUP BY player_id HAVING count(*)>1) THEN
    RAISE EXCEPTION 'Catalogue has duplicate ownership; repair before initialization';
  END IF;
  INSERT INTO game.tournaments(id) VALUES(p_tournament);
  INSERT INTO game.clubs(tournament_id,team_id,name,crest_url)
    SELECT p_tournament,id,name,crest_url FROM public.teams;
  INSERT INTO game.players(tournament_id,player_id,name,ovr,position,is_icon,reference_price,reference_clause)
    SELECT p_tournament,id,name,ovr,position,coalesce(is_icon,false),price,clause FROM public.players;
  INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause)
    SELECT p_tournament,tp.player_id,c.id,p.reference_price,p.reference_clause
    FROM public.team_players tp JOIN game.clubs c ON c.team_id=tp.team_id AND c.tournament_id=p_tournament
    JOIN game.players p ON p.player_id=tp.player_id AND p.tournament_id=p_tournament;
  INSERT INTO game.accounts(tournament_id) VALUES(p_tournament) RETURNING id INTO v_clearing;
  INSERT INTO game.accounts(tournament_id,club_id,balance)
    SELECT p_tournament,id,p_initial_budget FROM game.clubs WHERE tournament_id=p_tournament;
  INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result)
    VALUES(p_tournament,'opening','initialize',jsonb_build_object('initial_budget',p_initial_budget),'{}') RETURNING id INTO v_operation;
  IF p_initial_budget > 0 THEN
    INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount)
      SELECT p_tournament,v_operation,id,p_initial_budget FROM game.accounts WHERE tournament_id=p_tournament AND club_id IS NOT NULL;
    UPDATE game.accounts SET balance=-(SELECT sum(balance) FROM game.accounts WHERE tournament_id=p_tournament AND club_id IS NOT NULL)
      WHERE id=v_clearing;
    INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount)
      SELECT p_tournament,v_operation,id,balance FROM game.accounts WHERE id=v_clearing AND balance<>0;
  END IF;
  INSERT INTO game.seasons(tournament_id,number) VALUES(p_tournament,1);
END $$;

CREATE FUNCTION game.assign_club(p_tournament uuid, p_member uuid, p_club uuid, p_key text)
RETURNS uuid LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE v_season uuid; v_id uuid; v_old game.operations; v_payload jsonb;
BEGIN
  PERFORM 1 FROM game.tournaments WHERE id=p_tournament FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Game not initialized'; END IF;
  v_payload := jsonb_build_object('member',p_member,'club',p_club);
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=p_tournament AND idempotency_key=p_key;
  IF FOUND THEN
    IF v_old.kind<>'assignment' OR v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN (v_old.result->>'assignment_id')::uuid;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.members WHERE id=p_member AND tournament_id=p_tournament)
    OR NOT EXISTS(SELECT 1 FROM game.clubs WHERE id=p_club AND tournament_id=p_tournament) THEN
    RAISE EXCEPTION 'Member or club belongs to another tournament';
  END IF;
  SELECT id INTO v_season FROM game.seasons WHERE tournament_id=p_tournament AND ended_at IS NULL;
  IF v_season IS NULL THEN RAISE EXCEPTION 'No current season'; END IF;
  IF EXISTS(SELECT 1 FROM game.assignments WHERE tournament_id=p_tournament AND club_id=p_club AND ended_at IS NULL AND member_id<>p_member) THEN
    RAISE EXCEPTION 'Club already assigned';
  END IF;
  SELECT id INTO v_id FROM game.assignments WHERE tournament_id=p_tournament AND member_id=p_member AND club_id=p_club AND ended_at IS NULL;
  IF v_id IS NULL THEN
    UPDATE game.assignments SET ended_at=clock_timestamp() WHERE tournament_id=p_tournament AND member_id=p_member AND ended_at IS NULL;
    INSERT INTO game.assignments(tournament_id,season_id,member_id,club_id)
      VALUES(p_tournament,v_season,p_member,p_club) RETURNING id INTO v_id;
  END IF;
  INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result)
    VALUES(p_tournament,'assignment',p_key,v_payload,jsonb_build_object('assignment_id',v_id));
  RETURN v_id;
END $$;

-- Called by the future season finalization transaction, after its sporting checks.
CREATE FUNCTION game.advance_season(p_tournament uuid, p_key text)
RETURNS uuid LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE v_old game.operations; v_season uuid; v_number integer; v_time timestamptz;
BEGIN
  PERFORM 1 FROM game.tournaments WHERE id=p_tournament FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Game not initialized'; END IF;
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=p_tournament AND idempotency_key=p_key;
  IF FOUND THEN
    IF v_old.kind<>'advance_season' THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN (v_old.result->>'season_id')::uuid;
  END IF;
  SELECT number INTO v_number FROM game.seasons WHERE tournament_id=p_tournament AND ended_at IS NULL;
  IF v_number IS NULL THEN RAISE EXCEPTION 'No current season'; END IF;
  v_time := clock_timestamp();
  UPDATE game.assignments SET ended_at=v_time WHERE tournament_id=p_tournament AND ended_at IS NULL;
  UPDATE game.seasons SET ended_at=v_time WHERE tournament_id=p_tournament AND ended_at IS NULL;
  INSERT INTO game.seasons(tournament_id,number) VALUES(p_tournament,v_number+1) RETURNING id INTO v_season;
  INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result)
    VALUES(p_tournament,'advance_season',p_key,'{}',jsonb_build_object('season_id',v_season));
  RETURN v_season;
END $$;

-- Private, trusted backend only; no API exposure or security-definer functions.
REVOKE ALL ON ALL TABLES IN SCHEMA game FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA game FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA game TO service_role;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA game TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA game TO service_role;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA game TO service_role;
DO $$ DECLARE v_table record; BEGIN
  FOR v_table IN SELECT tablename FROM pg_tables WHERE schemaname='game' LOOP
    EXECUTE format('ALTER TABLE game.%I ENABLE ROW LEVEL SECURITY',v_table.tablename);
  END LOOP;
END $$;
