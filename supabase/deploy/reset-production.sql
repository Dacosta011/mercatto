-- MERCATTO: REINICIO REMOTO AUTORIZADO, VERSION 270004.
-- Proyecto previsto: fczlwqgpjzghqdyjnyes.supabase.co
-- Ejecutar COMPLETO en Supabase SQL Editor con el rol postgres.
-- ANTES: respaldo externo verificado y ventana de mantenimiento.
-- DESTRUYE torneos, participantes, mercado, resultados, catalogo y dependencias.
-- No elimina usuarios de Auth, buckets ni objetos de Storage.
-- La app antigua dejara de funcionar: desplegar el backend nuevo coordinadamente.
-- SQL NO SUBE IMAGENES: los 453 objetos deben cargarse aparte a Storage remoto.
-- Primera instalacion del esquema game solamente. Una repeticion aborta SIN borrar.
BEGIN;
SET LOCAL search_path=public,extensions;
SET LOCAL lock_timeout='10s';
SELECT pg_advisory_xact_lock(173812905);
DO $preflight$ DECLARE tab text; BEGIN
 IF to_regnamespace('game') IS NOT NULL OR to_regclass('public.sofifa_imports') IS NOT NULL THEN
  RAISE EXCEPTION 'El modelo nuevo ya existe. No repetir este reinicio; revisar migraciones pendientes.';
 END IF;
 FOREACH tab IN ARRAY ARRAY['tournaments','members','teams','players','assignments','member_roster','listings','market_sessions','market_turns','market_transfers','market_offers','team_players','league_sessions','fixtures','matchday_rests','discipline','suspensions','icon_auctions','icon_activation_votes','icon_selection_votes','icon_bids','lineups','notifications','push_subscriptions','icon_votes','social_profiles','posts','post_likes'] LOOP
  IF to_regclass('public.'||tab) IS NULL THEN RAISE EXCEPTION 'Falta tabla heredada %. No se ha borrado nada.',tab; END IF;
 END LOOP;
END $preflight$;
-- Lista cerrada: sin CASCADE para rechazar dependencias imprevistas.
DO $wipe$ DECLARE targets text := 'public.tournaments,public.members,public.teams,public.players,public.assignments,public.member_roster,public.listings,public.market_sessions,public.market_turns,public.market_transfers,public.market_offers,public.team_players,public.league_sessions,public.fixtures,public.matchday_rests,public.discipline,public.suspensions,public.icon_auctions,public.icon_activation_votes,public.icon_selection_votes,public.icon_bids,public.lineups,public.notifications,public.push_subscriptions,public.icon_votes,public.social_profiles,public.posts,public.post_likes'; tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['club_expenses','season_archive_assignments','season_archive_fixtures','season_archives','slot_machine_pool','slot_machine_spins','team_budgets'] LOOP
  IF to_regclass('public.'||tab) IS NOT NULL THEN targets := targets || ',public.' || quote_ident(tab); END IF;
 END LOOP;
 EXECUTE 'TRUNCATE ' || targets;
END $wipe$;
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations(version text PRIMARY KEY,statements text[],name text);

-- Migration 20261005000100_game_foundation.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000100','game_foundation',ARRAY[$mercatto_source$-- Foundation only: legacy application writes remain in public until the backend cutover.
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
$mercatto_source$]);

-- Migration 20261005000200_game_local_flow.sql
-- Local-first vertical slice. Public wrappers are executable ONLY by service_role.
-- These prototypes cannot enter the legacy gameplay endpoints.
CREATE TABLE game.creation_requests (
  request_key uuid PRIMARY KEY,
  payload jsonb NOT NULL,
  tournament_id uuid NOT NULL UNIQUE REFERENCES game.tournaments(id),
  result jsonb NOT NULL
);
ALTER TABLE game.creation_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.creation_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON game.creation_requests TO service_role;

CREATE FUNCTION game.initialize_catalog(p_tournament uuid, p_teams uuid[], p_free_players uuid[])
RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_op uuid; v_clearing uuid; v_payload jsonb;
BEGIN
  PERFORM 1 FROM public.tournaments WHERE id=p_tournament FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF EXISTS(SELECT 1 FROM game.tournaments WHERE id=p_tournament) THEN RAISE EXCEPTION 'Game already initialized'; END IF;
  IF EXISTS(SELECT 1 FROM public.assignments WHERE tournament_id=p_tournament)
    OR EXISTS(SELECT 1 FROM public.market_sessions WHERE tournament_id=p_tournament)
    OR EXISTS(SELECT 1 FROM public.league_sessions WHERE tournament_id=p_tournament)
    OR EXISTS(SELECT 1 FROM public.members WHERE tournament_id=p_tournament AND budget IS NOT NULL) THEN
    RAISE EXCEPTION 'Existing game requires audited migration';
  END IF;
  LOCK TABLE public.teams,public.players,public.team_players IN SHARE MODE;
  IF coalesce(cardinality(p_teams),0)=0 OR cardinality(p_teams)<>(SELECT count(*) FROM public.teams WHERE id=ANY(p_teams)) THEN
    RAISE EXCEPTION 'Invalid catalogue teams';
  END IF;
  IF p_free_players IS NULL OR cardinality(p_free_players)<>(SELECT count(*) FROM public.players WHERE id=ANY(p_free_players)) THEN
    RAISE EXCEPTION 'Invalid free players';
  END IF;
  IF EXISTS(SELECT 1 FROM public.team_players WHERE player_id=ANY(p_free_players)) THEN
    RAISE EXCEPTION 'Free player already belongs to a catalogue team';
  END IF;
  IF EXISTS(SELECT player_id FROM public.team_players WHERE team_id=ANY(p_teams) GROUP BY player_id HAVING count(*)>1) THEN
    RAISE EXCEPTION 'Selected catalogue has duplicate ownership';
  END IF;
  INSERT INTO game.tournaments(id) VALUES(p_tournament);
  INSERT INTO game.clubs(tournament_id,team_id,name,crest_url)
    SELECT p_tournament,id,name,crest_url FROM public.teams WHERE id=ANY(p_teams);
  INSERT INTO game.players(tournament_id,player_id,name,ovr,position,is_icon,reference_price,reference_clause)
    SELECT p_tournament,id,name,ovr,position,coalesce(is_icon,false),price,clause FROM public.players
    WHERE id=ANY(p_free_players) OR id IN(SELECT player_id FROM public.team_players WHERE team_id=ANY(p_teams));
  INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause)
    SELECT p_tournament,tp.player_id,c.id,p.reference_price,p.reference_clause
    FROM public.team_players tp JOIN game.clubs c ON c.team_id=tp.team_id AND c.tournament_id=p_tournament
    JOIN game.players p ON p.player_id=tp.player_id AND p.tournament_id=p_tournament;
  INSERT INTO game.accounts(tournament_id) VALUES(p_tournament) RETURNING id INTO v_clearing;
  -- Existing OVR budget formula, calculated ONCE at club initialization.
  INSERT INTO game.accounts(tournament_id,club_id,balance)
    SELECT p_tournament,c.id,
      CASE WHEN count(p.player_id)=0 THEN 100000000
      ELSE greatest(100000000,least(400000000,round((100000000+(88-avg(p.ovr))*20000000)/5000000)*5000000))::bigint END
    FROM game.clubs c LEFT JOIN game.contracts ct ON ct.club_id=c.id AND ct.tournament_id=c.tournament_id
    LEFT JOIN game.players p ON p.player_id=ct.player_id AND p.tournament_id=ct.tournament_id
    WHERE c.tournament_id=p_tournament GROUP BY c.id;
  v_payload:=jsonb_build_object('teams',p_teams,'free_players',p_free_players,'budget_rule','ovr_v1');
  INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result)
    VALUES(p_tournament,'opening','initialize',v_payload,'{}') RETURNING id INTO v_op;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount)
    SELECT p_tournament,v_op,id,balance FROM game.accounts WHERE tournament_id=p_tournament AND club_id IS NOT NULL;
  UPDATE game.accounts SET balance=-(SELECT sum(balance) FROM game.accounts WHERE tournament_id=p_tournament AND club_id IS NOT NULL) WHERE id=v_clearing;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount)
    SELECT p_tournament,v_op,id,balance FROM game.accounts WHERE id=v_clearing;
  INSERT INTO game.seasons(tournament_id,number) VALUES(p_tournament,1);
END $$;

CREATE FUNCTION public.game_create_tournament(p_key uuid,p_name text,p_display_name text,p_admin_token text,p_member_token text,p_teams uuid[],p_free_players uuid[])
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_tournament uuid; v_member uuid; v_code text; v_payload jsonb; v_old game.creation_requests; v_result jsonb;
BEGIN
  IF p_key IS NULL OR p_name IS NULL OR length(trim(p_name)) NOT BETWEEN 1 AND 80
    OR p_display_name IS NULL OR length(trim(p_display_name)) NOT BETWEEN 1 AND 40
    OR length(coalesce(p_admin_token,''))<32 OR length(coalesce(p_member_token,''))<32 THEN RAISE EXCEPTION 'Invalid creation parameters'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_key::text,0));
  v_payload:=jsonb_build_object('name',trim(p_name),'display_name',trim(p_display_name),'teams',p_teams,'free_players',p_free_players);
  SELECT * INTO v_old FROM game.creation_requests WHERE request_key=p_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  v_tournament:=gen_random_uuid(); v_member:=gen_random_uuid();
  v_code:='DEV-'||upper(replace(v_tournament::text,'-',''));
  INSERT INTO public.tournaments(id,name,code,admin_token_hash,status)
    VALUES(v_tournament,trim(p_name),v_code,encode(sha256(convert_to(p_admin_token,'UTF8')),'hex'),'prototype');
  INSERT INTO public.members(id,tournament_id,display_name,member_token_hash)
    VALUES(v_member,v_tournament,trim(p_display_name),encode(sha256(convert_to(p_member_token,'UTF8')),'hex'));
  PERFORM game.initialize_catalog(v_tournament,p_teams,p_free_players);
  v_result:=jsonb_build_object('id',v_tournament,'name',trim(p_name),'code',v_code,'memberId',v_member,'adminToken',p_admin_token,'memberToken',p_member_token);
  -- Credential recovery for retries stays in the private schema, backend-only.
  INSERT INTO game.creation_requests VALUES(p_key,v_payload,v_tournament,v_result);
  RETURN v_result;
END $$;

CREATE FUNCTION game.require_member(p_code text,p_token text) RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid;
BEGIN
  SELECT m.id INTO v_member FROM public.members m JOIN public.tournaments t ON t.id=m.tournament_id
    JOIN game.tournaments g ON g.id=t.id
    WHERE t.code=upper(p_code) AND t.status='prototype'
      AND m.member_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  IF v_member IS NULL THEN RAISE EXCEPTION 'Invalid member token' USING ERRCODE='28000'; END IF;
  RETURN v_member;
END $$;

CREATE FUNCTION public.game_join_tournament(p_code text,p_name text,p_token text,p_key uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_tournament uuid; v_member uuid; v_old game.operations; v_payload jsonb; v_result jsonb;
BEGIN
  IF p_key IS NULL OR p_name IS NULL OR length(trim(p_name)) NOT BETWEEN 1 AND 40 OR length(coalesce(p_token,''))<32 THEN RAISE EXCEPTION 'Invalid join parameters'; END IF;
  SELECT g.id INTO v_tournament FROM game.tournaments g JOIN public.tournaments t ON t.id=g.id WHERE t.code=upper(p_code) AND t.status='prototype' FOR UPDATE OF g;
  IF v_tournament IS NULL THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  v_payload:=jsonb_build_object('name',trim(p_name));
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key='join:'||p_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  IF EXISTS(SELECT 1 FROM public.members WHERE tournament_id=v_tournament AND lower(display_name)=lower(trim(p_name))) THEN RAISE EXCEPTION 'Display name already in use'; END IF;
  INSERT INTO public.members(tournament_id,display_name,member_token_hash)
    VALUES(v_tournament,trim(p_name),encode(sha256(convert_to(p_token,'UTF8')),'hex')) RETURNING id INTO v_member;
  v_result:=jsonb_build_object('memberId',v_member,'memberToken',p_token,'code',upper(p_code));
  INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result)
    VALUES(v_tournament,'join','join:'||p_key,v_payload,v_result);
  RETURN v_result;
END $$;

CREATE FUNCTION public.game_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid; v_tournament uuid; v_result jsonb;
BEGIN
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  -- A single SQL statement gives one consistent snapshot of roster/account/assignment.
  SELECT jsonb_build_object('id',t.id,'name',t.name,'code',t.code,'memberId',v_member,
    'season',(SELECT number FROM game.seasons WHERE tournament_id=t.id AND ended_at IS NULL),
    'clubs',coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'teamId',c.team_id,'name',c.name,'budget',ac.balance,'reserved',ac.reserved,
      'memberId',a.member_id,'manager',m.display_name,'squad',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'position',p.position,'price',ct.acquired_price,'clause',ct.clause) ORDER BY p.ovr DESC,p.player_id)
      FROM game.contracts ct JOIN game.players p ON p.tournament_id=ct.tournament_id AND p.player_id=ct.player_id WHERE ct.tournament_id=c.tournament_id AND ct.club_id=c.id AND ct.ended_at IS NULL),'[]'::jsonb)) ORDER BY c.name,c.id)
      FROM game.clubs c JOIN game.accounts ac ON ac.tournament_id=c.tournament_id AND ac.club_id=c.id
      LEFT JOIN game.assignments a ON a.tournament_id=c.tournament_id AND a.club_id=c.id AND a.ended_at IS NULL
      LEFT JOIN public.members m ON m.id=a.member_id WHERE c.tournament_id=t.id),'[]'::jsonb),
    'members',(SELECT jsonb_agg(jsonb_build_object('id',id,'name',display_name) ORDER BY display_name,id) FROM public.members WHERE tournament_id=t.id))
    INTO v_result FROM public.tournaments t WHERE t.id=v_tournament;
  RETURN v_result;
END $$;

CREATE FUNCTION public.game_choose_club(p_code text,p_token text,p_club uuid,p_key uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid; v_tournament uuid; v_assignment uuid;
BEGIN
  IF p_key IS NULL OR p_club IS NULL THEN RAISE EXCEPTION 'Invalid assignment parameters'; END IF;
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  v_assignment:=game.assign_club(v_tournament,v_member,p_club,'choose:'||v_member||':'||p_key);
  RETURN jsonb_build_object('assignmentId',v_assignment);
END $$;

CREATE FUNCTION public.game_next_season(p_code text,p_token text,p_key uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_tournament uuid; v_season uuid;
BEGIN
  IF p_key IS NULL THEN RAISE EXCEPTION 'Invalid season parameters'; END IF;
  SELECT g.id INTO v_tournament FROM game.tournaments g JOIN public.tournaments t ON t.id=g.id
    WHERE t.code=upper(p_code) AND t.status='prototype' AND t.admin_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  IF v_tournament IS NULL THEN RAISE EXCEPTION 'Invalid admin token' USING ERRCODE='28000'; END IF;
  -- Prototype-only: no league exists yet. Real league finalization will replace this entry point.
  v_season:=game.advance_season(v_tournament,'next:'||p_key);
  RETURN jsonb_build_object('seasonId',v_season);
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA game FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA game TO service_role;
REVOKE ALL ON FUNCTION public.game_create_tournament(uuid,text,text,text,text,uuid[],uuid[]),
  public.game_join_tournament(text,text,text,uuid),public.game_state(text,text),
  public.game_choose_club(text,text,uuid,uuid),public.game_next_season(text,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_create_tournament(uuid,text,text,text,text,uuid[],uuid[]),
  public.game_join_tournament(text,text,text,uuid),public.game_state(text,text),
  public.game_choose_club(text,text,uuid,uuid),public.game_next_season(text,text,uuid) TO service_role;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000200','game_local_flow',ARRAY[$mercatto_source$-- Local-first vertical slice. Public wrappers are executable ONLY by service_role.
-- These prototypes cannot enter the legacy gameplay endpoints.
CREATE TABLE game.creation_requests (
  request_key uuid PRIMARY KEY,
  payload jsonb NOT NULL,
  tournament_id uuid NOT NULL UNIQUE REFERENCES game.tournaments(id),
  result jsonb NOT NULL
);
ALTER TABLE game.creation_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.creation_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON game.creation_requests TO service_role;

CREATE FUNCTION game.initialize_catalog(p_tournament uuid, p_teams uuid[], p_free_players uuid[])
RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_op uuid; v_clearing uuid; v_payload jsonb;
BEGIN
  PERFORM 1 FROM public.tournaments WHERE id=p_tournament FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  IF EXISTS(SELECT 1 FROM game.tournaments WHERE id=p_tournament) THEN RAISE EXCEPTION 'Game already initialized'; END IF;
  IF EXISTS(SELECT 1 FROM public.assignments WHERE tournament_id=p_tournament)
    OR EXISTS(SELECT 1 FROM public.market_sessions WHERE tournament_id=p_tournament)
    OR EXISTS(SELECT 1 FROM public.league_sessions WHERE tournament_id=p_tournament)
    OR EXISTS(SELECT 1 FROM public.members WHERE tournament_id=p_tournament AND budget IS NOT NULL) THEN
    RAISE EXCEPTION 'Existing game requires audited migration';
  END IF;
  LOCK TABLE public.teams,public.players,public.team_players IN SHARE MODE;
  IF coalesce(cardinality(p_teams),0)=0 OR cardinality(p_teams)<>(SELECT count(*) FROM public.teams WHERE id=ANY(p_teams)) THEN
    RAISE EXCEPTION 'Invalid catalogue teams';
  END IF;
  IF p_free_players IS NULL OR cardinality(p_free_players)<>(SELECT count(*) FROM public.players WHERE id=ANY(p_free_players)) THEN
    RAISE EXCEPTION 'Invalid free players';
  END IF;
  IF EXISTS(SELECT 1 FROM public.team_players WHERE player_id=ANY(p_free_players)) THEN
    RAISE EXCEPTION 'Free player already belongs to a catalogue team';
  END IF;
  IF EXISTS(SELECT player_id FROM public.team_players WHERE team_id=ANY(p_teams) GROUP BY player_id HAVING count(*)>1) THEN
    RAISE EXCEPTION 'Selected catalogue has duplicate ownership';
  END IF;
  INSERT INTO game.tournaments(id) VALUES(p_tournament);
  INSERT INTO game.clubs(tournament_id,team_id,name,crest_url)
    SELECT p_tournament,id,name,crest_url FROM public.teams WHERE id=ANY(p_teams);
  INSERT INTO game.players(tournament_id,player_id,name,ovr,position,is_icon,reference_price,reference_clause)
    SELECT p_tournament,id,name,ovr,position,coalesce(is_icon,false),price,clause FROM public.players
    WHERE id=ANY(p_free_players) OR id IN(SELECT player_id FROM public.team_players WHERE team_id=ANY(p_teams));
  INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause)
    SELECT p_tournament,tp.player_id,c.id,p.reference_price,p.reference_clause
    FROM public.team_players tp JOIN game.clubs c ON c.team_id=tp.team_id AND c.tournament_id=p_tournament
    JOIN game.players p ON p.player_id=tp.player_id AND p.tournament_id=p_tournament;
  INSERT INTO game.accounts(tournament_id) VALUES(p_tournament) RETURNING id INTO v_clearing;
  -- Existing OVR budget formula, calculated ONCE at club initialization.
  INSERT INTO game.accounts(tournament_id,club_id,balance)
    SELECT p_tournament,c.id,
      CASE WHEN count(p.player_id)=0 THEN 100000000
      ELSE greatest(100000000,least(400000000,round((100000000+(88-avg(p.ovr))*20000000)/5000000)*5000000))::bigint END
    FROM game.clubs c LEFT JOIN game.contracts ct ON ct.club_id=c.id AND ct.tournament_id=c.tournament_id
    LEFT JOIN game.players p ON p.player_id=ct.player_id AND p.tournament_id=ct.tournament_id
    WHERE c.tournament_id=p_tournament GROUP BY c.id;
  v_payload:=jsonb_build_object('teams',p_teams,'free_players',p_free_players,'budget_rule','ovr_v1');
  INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result)
    VALUES(p_tournament,'opening','initialize',v_payload,'{}') RETURNING id INTO v_op;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount)
    SELECT p_tournament,v_op,id,balance FROM game.accounts WHERE tournament_id=p_tournament AND club_id IS NOT NULL;
  UPDATE game.accounts SET balance=-(SELECT sum(balance) FROM game.accounts WHERE tournament_id=p_tournament AND club_id IS NOT NULL) WHERE id=v_clearing;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount)
    SELECT p_tournament,v_op,id,balance FROM game.accounts WHERE id=v_clearing;
  INSERT INTO game.seasons(tournament_id,number) VALUES(p_tournament,1);
END $$;

CREATE FUNCTION public.game_create_tournament(p_key uuid,p_name text,p_display_name text,p_admin_token text,p_member_token text,p_teams uuid[],p_free_players uuid[])
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_tournament uuid; v_member uuid; v_code text; v_payload jsonb; v_old game.creation_requests; v_result jsonb;
BEGIN
  IF p_key IS NULL OR p_name IS NULL OR length(trim(p_name)) NOT BETWEEN 1 AND 80
    OR p_display_name IS NULL OR length(trim(p_display_name)) NOT BETWEEN 1 AND 40
    OR length(coalesce(p_admin_token,''))<32 OR length(coalesce(p_member_token,''))<32 THEN RAISE EXCEPTION 'Invalid creation parameters'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_key::text,0));
  v_payload:=jsonb_build_object('name',trim(p_name),'display_name',trim(p_display_name),'teams',p_teams,'free_players',p_free_players);
  SELECT * INTO v_old FROM game.creation_requests WHERE request_key=p_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  v_tournament:=gen_random_uuid(); v_member:=gen_random_uuid();
  v_code:='DEV-'||upper(replace(v_tournament::text,'-',''));
  INSERT INTO public.tournaments(id,name,code,admin_token_hash,status)
    VALUES(v_tournament,trim(p_name),v_code,encode(sha256(convert_to(p_admin_token,'UTF8')),'hex'),'prototype');
  INSERT INTO public.members(id,tournament_id,display_name,member_token_hash)
    VALUES(v_member,v_tournament,trim(p_display_name),encode(sha256(convert_to(p_member_token,'UTF8')),'hex'));
  PERFORM game.initialize_catalog(v_tournament,p_teams,p_free_players);
  v_result:=jsonb_build_object('id',v_tournament,'name',trim(p_name),'code',v_code,'memberId',v_member,'adminToken',p_admin_token,'memberToken',p_member_token);
  -- Credential recovery for retries stays in the private schema, backend-only.
  INSERT INTO game.creation_requests VALUES(p_key,v_payload,v_tournament,v_result);
  RETURN v_result;
END $$;

CREATE FUNCTION game.require_member(p_code text,p_token text) RETURNS uuid LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid;
BEGIN
  SELECT m.id INTO v_member FROM public.members m JOIN public.tournaments t ON t.id=m.tournament_id
    JOIN game.tournaments g ON g.id=t.id
    WHERE t.code=upper(p_code) AND t.status='prototype'
      AND m.member_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  IF v_member IS NULL THEN RAISE EXCEPTION 'Invalid member token' USING ERRCODE='28000'; END IF;
  RETURN v_member;
END $$;

CREATE FUNCTION public.game_join_tournament(p_code text,p_name text,p_token text,p_key uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_tournament uuid; v_member uuid; v_old game.operations; v_payload jsonb; v_result jsonb;
BEGIN
  IF p_key IS NULL OR p_name IS NULL OR length(trim(p_name)) NOT BETWEEN 1 AND 40 OR length(coalesce(p_token,''))<32 THEN RAISE EXCEPTION 'Invalid join parameters'; END IF;
  SELECT g.id INTO v_tournament FROM game.tournaments g JOIN public.tournaments t ON t.id=g.id WHERE t.code=upper(p_code) AND t.status='prototype' FOR UPDATE OF g;
  IF v_tournament IS NULL THEN RAISE EXCEPTION 'Tournament not found'; END IF;
  v_payload:=jsonb_build_object('name',trim(p_name));
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key='join:'||p_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  IF EXISTS(SELECT 1 FROM public.members WHERE tournament_id=v_tournament AND lower(display_name)=lower(trim(p_name))) THEN RAISE EXCEPTION 'Display name already in use'; END IF;
  INSERT INTO public.members(tournament_id,display_name,member_token_hash)
    VALUES(v_tournament,trim(p_name),encode(sha256(convert_to(p_token,'UTF8')),'hex')) RETURNING id INTO v_member;
  v_result:=jsonb_build_object('memberId',v_member,'memberToken',p_token,'code',upper(p_code));
  INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result)
    VALUES(v_tournament,'join','join:'||p_key,v_payload,v_result);
  RETURN v_result;
END $$;

CREATE FUNCTION public.game_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid; v_tournament uuid; v_result jsonb;
BEGIN
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  -- A single SQL statement gives one consistent snapshot of roster/account/assignment.
  SELECT jsonb_build_object('id',t.id,'name',t.name,'code',t.code,'memberId',v_member,
    'season',(SELECT number FROM game.seasons WHERE tournament_id=t.id AND ended_at IS NULL),
    'clubs',coalesce((SELECT jsonb_agg(jsonb_build_object('id',c.id,'teamId',c.team_id,'name',c.name,'budget',ac.balance,'reserved',ac.reserved,
      'memberId',a.member_id,'manager',m.display_name,'squad',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'position',p.position,'price',ct.acquired_price,'clause',ct.clause) ORDER BY p.ovr DESC,p.player_id)
      FROM game.contracts ct JOIN game.players p ON p.tournament_id=ct.tournament_id AND p.player_id=ct.player_id WHERE ct.tournament_id=c.tournament_id AND ct.club_id=c.id AND ct.ended_at IS NULL),'[]'::jsonb)) ORDER BY c.name,c.id)
      FROM game.clubs c JOIN game.accounts ac ON ac.tournament_id=c.tournament_id AND ac.club_id=c.id
      LEFT JOIN game.assignments a ON a.tournament_id=c.tournament_id AND a.club_id=c.id AND a.ended_at IS NULL
      LEFT JOIN public.members m ON m.id=a.member_id WHERE c.tournament_id=t.id),'[]'::jsonb),
    'members',(SELECT jsonb_agg(jsonb_build_object('id',id,'name',display_name) ORDER BY display_name,id) FROM public.members WHERE tournament_id=t.id))
    INTO v_result FROM public.tournaments t WHERE t.id=v_tournament;
  RETURN v_result;
END $$;

CREATE FUNCTION public.game_choose_club(p_code text,p_token text,p_club uuid,p_key uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid; v_tournament uuid; v_assignment uuid;
BEGIN
  IF p_key IS NULL OR p_club IS NULL THEN RAISE EXCEPTION 'Invalid assignment parameters'; END IF;
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  v_assignment:=game.assign_club(v_tournament,v_member,p_club,'choose:'||v_member||':'||p_key);
  RETURN jsonb_build_object('assignmentId',v_assignment);
END $$;

CREATE FUNCTION public.game_next_season(p_code text,p_token text,p_key uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_tournament uuid; v_season uuid;
BEGIN
  IF p_key IS NULL THEN RAISE EXCEPTION 'Invalid season parameters'; END IF;
  SELECT g.id INTO v_tournament FROM game.tournaments g JOIN public.tournaments t ON t.id=g.id
    WHERE t.code=upper(p_code) AND t.status='prototype' AND t.admin_token_hash=encode(sha256(convert_to(p_token,'UTF8')),'hex');
  IF v_tournament IS NULL THEN RAISE EXCEPTION 'Invalid admin token' USING ERRCODE='28000'; END IF;
  -- Prototype-only: no league exists yet. Real league finalization will replace this entry point.
  v_season:=game.advance_season(v_tournament,'next:'||p_key);
  RETURN jsonb_build_object('seasonId',v_season);
END $$;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA game FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA game TO service_role;
REVOKE ALL ON FUNCTION public.game_create_tournament(uuid,text,text,text,text,uuid[],uuid[]),
  public.game_join_tournament(text,text,text,uuid),public.game_state(text,text),
  public.game_choose_club(text,text,uuid,uuid),public.game_next_season(text,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_create_tournament(uuid,text,text,text,text,uuid[],uuid[]),
  public.game_join_tournament(text,text,text,uuid),public.game_state(text,text),
  public.game_choose_club(text,text,uuid,uuid),public.game_next_season(text,text,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005000300_game_market.sql
CREATE TABLE game.market_windows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES game.tournaments(id),
  season_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN('summer','winter')),
  status text NOT NULL DEFAULT 'open' CHECK(status IN('open','closed')),
  opens_at timestamptz NOT NULL,
  closes_at timestamptz NOT NULL CHECK(closes_at>opens_at),
  closed_at timestamptz,
  purchase_limit integer NOT NULL CHECK(purchase_limit BETWEEN 1 AND 10),
  UNIQUE(tournament_id,id),
  FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id)
);
CREATE UNIQUE INDEX one_open_market ON game.market_windows(tournament_id) WHERE status='open';
CREATE TABLE game.market_limits (
  tournament_id uuid NOT NULL,
  window_id uuid NOT NULL,
  club_id uuid NOT NULL,
  purchase_limit integer NOT NULL CHECK(purchase_limit BETWEEN 1 AND 10),
  purchases_used integer NOT NULL DEFAULT 0 CHECK(purchases_used>=0),
  purchases_held integer NOT NULL DEFAULT 0 CHECK(purchases_held>=0),
  CHECK(purchases_used+purchases_held<=purchase_limit),
  PRIMARY KEY(window_id,club_id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE TABLE game.offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL,
  window_id uuid NOT NULL,
  buyer_club_id uuid NOT NULL,
  seller_club_id uuid NOT NULL CHECK(seller_club_id<>buyer_club_id),
  player_id uuid NOT NULL,
  amount bigint NOT NULL CHECK(amount>0),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','accepted','rejected','cancelled','stale','expired')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  resolved_at timestamptz,
  UNIQUE(tournament_id,id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,buyer_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,seller_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE UNIQUE INDEX one_pending_offer_per_buyer ON game.offers(window_id,buyer_club_id,player_id) WHERE status='pending';
CREATE INDEX pending_player_offers ON game.offers(tournament_id,player_id) WHERE status='pending';
CREATE TABLE game.transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL,
  operation_id uuid NOT NULL UNIQUE,
  window_id uuid NOT NULL,
  buyer_club_id uuid NOT NULL,
  seller_club_id uuid,
  player_id uuid NOT NULL,
  amount bigint NOT NULL CHECK(amount>0),
  kind text NOT NULL CHECK(kind IN('offer','free')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(seller_club_id IS NULL OR seller_club_id<>buyer_club_id),
  FOREIGN KEY(tournament_id,operation_id) REFERENCES game.operations(tournament_id,id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,buyer_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,seller_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE INDEX transfer_history ON game.transfers(tournament_id,created_at,id);
CREATE TRIGGER immutable_transfers BEFORE UPDATE OR DELETE ON game.transfers FOR EACH ROW EXECUTE FUNCTION game.immutable_history();

-- The final account balance MUST equal the immutable ledger, even for trusted backend writes.
CREATE FUNCTION game.check_account_ledger() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_account uuid;
BEGIN
  IF TG_TABLE_NAME='accounts' THEN v_account:=NEW.id; ELSE v_account:=NEW.account_id; END IF;
  IF (SELECT balance FROM game.accounts WHERE id=v_account) IS DISTINCT FROM
     (SELECT coalesce(sum(amount),0)::bigint FROM game.ledger WHERE account_id=v_account) THEN
    RAISE EXCEPTION 'Account balance does not match ledger';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER account_ledger_consistency AFTER INSERT OR UPDATE ON game.accounts
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION game.check_account_ledger();
CREATE CONSTRAINT TRIGGER ledger_account_consistency AFTER INSERT ON game.ledger
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION game.check_account_ledger();

CREATE FUNCTION game.guard_market_assignment() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=NEW.tournament_id AND status='open') THEN
    RAISE EXCEPTION 'Close market before changing clubs or season' USING ERRCODE='GM001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER market_assignment_guard BEFORE INSERT OR UPDATE ON game.assignments FOR EACH ROW EXECUTE FUNCTION game.guard_market_assignment();
CREATE TRIGGER market_season_guard BEFORE INSERT OR UPDATE ON game.seasons FOR EACH ROW EXECUTE FUNCTION game.guard_market_assignment();

CREATE FUNCTION game.release_offer(p_offer uuid,p_status text) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_offer game.offers;
BEGIN
  SELECT * INTO v_offer FROM game.offers WHERE id=p_offer AND status='pending' FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF p_status NOT IN('accepted','rejected','cancelled','stale','expired') THEN RAISE EXCEPTION 'Invalid offer resolution'; END IF;
  UPDATE game.accounts SET reserved=reserved-v_offer.amount WHERE tournament_id=v_offer.tournament_id AND club_id=v_offer.buyer_club_id;
  UPDATE game.market_limits SET purchases_held=purchases_held-1 WHERE window_id=v_offer.window_id AND club_id=v_offer.buyer_club_id;
  UPDATE game.offers SET status=p_status,resolved_at=clock_timestamp() WHERE id=p_offer;
END $$;

CREATE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,
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
  IF p_key IS NULL OR p_action IS NULL OR p_action NOT IN('open','close','offer','accept','reject','cancel','sign') THEN RAISE EXCEPTION 'Invalid market action'; END IF;
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
    IF p_action IN('offer','accept','sign') AND v_now>=v_window.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
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
      IF (p_action IN('accept','reject') AND v_offer.seller_club_id<>v_club) OR (p_action='cancel' AND v_offer.buyer_club_id<>v_club) THEN RAISE EXCEPTION 'Not authorized for this offer' USING ERRCODE='28000'; END IF;
      IF p_action='accept' THEN
        SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=v_offer.player_id AND ended_at IS NULL FOR UPDATE;
        IF v_contract.id IS NULL OR v_contract.club_id<>v_offer.seller_club_id THEN RAISE EXCEPTION 'Seller no longer owns player' USING ERRCODE='GM001'; END IF;
        v_trade:=true; v_buyer:=v_offer.buyer_club_id; v_seller:=v_offer.seller_club_id;
        p_player:=v_offer.player_id; v_amount:=v_offer.amount; v_clause:=v_contract.clause; v_kind:='offer';
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

CREATE FUNCTION public.game_market_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid; v_tournament uuid; v_club uuid; v_result jsonb;
BEGIN
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  SELECT club_id INTO v_club FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  SELECT jsonb_build_object(
    'window',(SELECT jsonb_build_object('id',w.id,'kind',w.kind,'status',CASE WHEN w.status='open' AND clock_timestamp()>=w.closes_at THEN 'expired' ELSE w.status END,'closesAt',w.closes_at,'purchaseLimit',w.purchase_limit) FROM game.market_windows w WHERE w.tournament_id=v_tournament ORDER BY w.opens_at DESC,w.id DESC LIMIT 1),
    'limits',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',l.club_id,'used',l.purchases_used,'held',l.purchases_held,'limit',l.purchase_limit)) FROM game.market_limits l JOIN game.market_windows w ON w.id=l.window_id WHERE l.tournament_id=v_tournament AND w.status='open'),'[]'::jsonb),
    'freePlayers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'price',p.reference_price) ORDER BY p.name) FROM game.players p WHERE p.tournament_id=v_tournament AND NOT p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p.tournament_id AND c.player_id=p.player_id AND c.ended_at IS NULL)),'[]'::jsonb),
    'offers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'windowId',o.window_id,'playerId',o.player_id,'playerName',p.name,'buyerClubId',o.buyer_club_id,'sellerClubId',o.seller_club_id,'buyer',b.name,'seller',s.name,'amount',o.amount,'status',o.status) ORDER BY o.created_at DESC,o.id DESC) FROM game.offers o JOIN game.players p ON p.tournament_id=o.tournament_id AND p.player_id=o.player_id JOIN game.clubs b ON b.id=o.buyer_club_id JOIN game.clubs s ON s.id=o.seller_club_id WHERE o.tournament_id=v_tournament),'[]'::jsonb),
    'transfers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'playerId',tr.player_id,'playerName',p.name,'buyer',b.name,'seller',s.name,'amount',tr.amount,'kind',tr.kind,'createdAt',tr.created_at) ORDER BY tr.created_at DESC,tr.id DESC) FROM game.transfers tr JOIN game.players p ON p.tournament_id=tr.tournament_id AND p.player_id=tr.player_id JOIN game.clubs b ON b.id=tr.buyer_club_id LEFT JOIN game.clubs s ON s.id=tr.seller_club_id WHERE tr.tournament_id=v_tournament),'[]'::jsonb),
    'ledger',coalesce((SELECT jsonb_agg(jsonb_build_object('id',l.id,'amount',l.amount,'kind',o.kind,'createdAt',l.created_at) ORDER BY l.id DESC) FROM game.ledger l JOIN game.operations o ON o.id=l.operation_id JOIN game.accounts a ON a.id=l.account_id WHERE l.tournament_id=v_tournament AND a.club_id=v_club),'[]'::jsonb)) INTO v_result;
  RETURN v_result;
END $$;

DO $$ DECLARE v_table text; BEGIN
  FOREACH v_table IN ARRAY ARRAY['market_windows','market_limits','offers','transfers'] LOOP
    EXECUTE format('ALTER TABLE game.%I ENABLE ROW LEVEL SECURITY',v_table);
    EXECUTE format('REVOKE ALL ON game.%I FROM PUBLIC,anon,authenticated',v_table);
    EXECUTE format('GRANT SELECT,INSERT,UPDATE ON game.%I TO service_role',v_table);
  END LOOP;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA game FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA game TO service_role;
REVOKE ALL ON FUNCTION public.game_market_command(text,text,uuid,text,uuid,uuid,bigint,text,integer),public.game_market_state(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_market_command(text,text,uuid,text,uuid,uuid,bigint,text,integer),public.game_market_state(text,text) TO service_role;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000300','game_market',ARRAY[$mercatto_source$CREATE TABLE game.market_windows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES game.tournaments(id),
  season_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN('summer','winter')),
  status text NOT NULL DEFAULT 'open' CHECK(status IN('open','closed')),
  opens_at timestamptz NOT NULL,
  closes_at timestamptz NOT NULL CHECK(closes_at>opens_at),
  closed_at timestamptz,
  purchase_limit integer NOT NULL CHECK(purchase_limit BETWEEN 1 AND 10),
  UNIQUE(tournament_id,id),
  FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id)
);
CREATE UNIQUE INDEX one_open_market ON game.market_windows(tournament_id) WHERE status='open';
CREATE TABLE game.market_limits (
  tournament_id uuid NOT NULL,
  window_id uuid NOT NULL,
  club_id uuid NOT NULL,
  purchase_limit integer NOT NULL CHECK(purchase_limit BETWEEN 1 AND 10),
  purchases_used integer NOT NULL DEFAULT 0 CHECK(purchases_used>=0),
  purchases_held integer NOT NULL DEFAULT 0 CHECK(purchases_held>=0),
  CHECK(purchases_used+purchases_held<=purchase_limit),
  PRIMARY KEY(window_id,club_id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
CREATE TABLE game.offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL,
  window_id uuid NOT NULL,
  buyer_club_id uuid NOT NULL,
  seller_club_id uuid NOT NULL CHECK(seller_club_id<>buyer_club_id),
  player_id uuid NOT NULL,
  amount bigint NOT NULL CHECK(amount>0),
  status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','accepted','rejected','cancelled','stale','expired')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  resolved_at timestamptz,
  UNIQUE(tournament_id,id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,buyer_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,seller_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE UNIQUE INDEX one_pending_offer_per_buyer ON game.offers(window_id,buyer_club_id,player_id) WHERE status='pending';
CREATE INDEX pending_player_offers ON game.offers(tournament_id,player_id) WHERE status='pending';
CREATE TABLE game.transfers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL,
  operation_id uuid NOT NULL UNIQUE,
  window_id uuid NOT NULL,
  buyer_club_id uuid NOT NULL,
  seller_club_id uuid,
  player_id uuid NOT NULL,
  amount bigint NOT NULL CHECK(amount>0),
  kind text NOT NULL CHECK(kind IN('offer','free')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK(seller_club_id IS NULL OR seller_club_id<>buyer_club_id),
  FOREIGN KEY(tournament_id,operation_id) REFERENCES game.operations(tournament_id,id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,buyer_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,seller_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id)
);
CREATE INDEX transfer_history ON game.transfers(tournament_id,created_at,id);
CREATE TRIGGER immutable_transfers BEFORE UPDATE OR DELETE ON game.transfers FOR EACH ROW EXECUTE FUNCTION game.immutable_history();

-- The final account balance MUST equal the immutable ledger, even for trusted backend writes.
CREATE FUNCTION game.check_account_ledger() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_account uuid;
BEGIN
  IF TG_TABLE_NAME='accounts' THEN v_account:=NEW.id; ELSE v_account:=NEW.account_id; END IF;
  IF (SELECT balance FROM game.accounts WHERE id=v_account) IS DISTINCT FROM
     (SELECT coalesce(sum(amount),0)::bigint FROM game.ledger WHERE account_id=v_account) THEN
    RAISE EXCEPTION 'Account balance does not match ledger';
  END IF;
  RETURN NULL;
END $$;
CREATE CONSTRAINT TRIGGER account_ledger_consistency AFTER INSERT OR UPDATE ON game.accounts
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION game.check_account_ledger();
CREATE CONSTRAINT TRIGGER ledger_account_consistency AFTER INSERT ON game.ledger
  DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION game.check_account_ledger();

CREATE FUNCTION game.guard_market_assignment() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  IF EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=NEW.tournament_id AND status='open') THEN
    RAISE EXCEPTION 'Close market before changing clubs or season' USING ERRCODE='GM001';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER market_assignment_guard BEFORE INSERT OR UPDATE ON game.assignments FOR EACH ROW EXECUTE FUNCTION game.guard_market_assignment();
CREATE TRIGGER market_season_guard BEFORE INSERT OR UPDATE ON game.seasons FOR EACH ROW EXECUTE FUNCTION game.guard_market_assignment();

CREATE FUNCTION game.release_offer(p_offer uuid,p_status text) RETURNS void LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_offer game.offers;
BEGIN
  SELECT * INTO v_offer FROM game.offers WHERE id=p_offer AND status='pending' FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF p_status NOT IN('accepted','rejected','cancelled','stale','expired') THEN RAISE EXCEPTION 'Invalid offer resolution'; END IF;
  UPDATE game.accounts SET reserved=reserved-v_offer.amount WHERE tournament_id=v_offer.tournament_id AND club_id=v_offer.buyer_club_id;
  UPDATE game.market_limits SET purchases_held=purchases_held-1 WHERE window_id=v_offer.window_id AND club_id=v_offer.buyer_club_id;
  UPDATE game.offers SET status=p_status,resolved_at=clock_timestamp() WHERE id=p_offer;
END $$;

CREATE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,
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
  IF p_key IS NULL OR p_action IS NULL OR p_action NOT IN('open','close','offer','accept','reject','cancel','sign') THEN RAISE EXCEPTION 'Invalid market action'; END IF;
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
    IF p_action IN('offer','accept','sign') AND v_now>=v_window.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
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
      IF (p_action IN('accept','reject') AND v_offer.seller_club_id<>v_club) OR (p_action='cancel' AND v_offer.buyer_club_id<>v_club) THEN RAISE EXCEPTION 'Not authorized for this offer' USING ERRCODE='28000'; END IF;
      IF p_action='accept' THEN
        SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=v_offer.player_id AND ended_at IS NULL FOR UPDATE;
        IF v_contract.id IS NULL OR v_contract.club_id<>v_offer.seller_club_id THEN RAISE EXCEPTION 'Seller no longer owns player' USING ERRCODE='GM001'; END IF;
        v_trade:=true; v_buyer:=v_offer.buyer_club_id; v_seller:=v_offer.seller_club_id;
        p_player:=v_offer.player_id; v_amount:=v_offer.amount; v_clause:=v_contract.clause; v_kind:='offer';
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

CREATE FUNCTION public.game_market_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE v_member uuid; v_tournament uuid; v_club uuid; v_result jsonb;
BEGIN
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  SELECT club_id INTO v_club FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  SELECT jsonb_build_object(
    'window',(SELECT jsonb_build_object('id',w.id,'kind',w.kind,'status',CASE WHEN w.status='open' AND clock_timestamp()>=w.closes_at THEN 'expired' ELSE w.status END,'closesAt',w.closes_at,'purchaseLimit',w.purchase_limit) FROM game.market_windows w WHERE w.tournament_id=v_tournament ORDER BY w.opens_at DESC,w.id DESC LIMIT 1),
    'limits',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',l.club_id,'used',l.purchases_used,'held',l.purchases_held,'limit',l.purchase_limit)) FROM game.market_limits l JOIN game.market_windows w ON w.id=l.window_id WHERE l.tournament_id=v_tournament AND w.status='open'),'[]'::jsonb),
    'freePlayers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'price',p.reference_price) ORDER BY p.name) FROM game.players p WHERE p.tournament_id=v_tournament AND NOT p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p.tournament_id AND c.player_id=p.player_id AND c.ended_at IS NULL)),'[]'::jsonb),
    'offers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'windowId',o.window_id,'playerId',o.player_id,'playerName',p.name,'buyerClubId',o.buyer_club_id,'sellerClubId',o.seller_club_id,'buyer',b.name,'seller',s.name,'amount',o.amount,'status',o.status) ORDER BY o.created_at DESC,o.id DESC) FROM game.offers o JOIN game.players p ON p.tournament_id=o.tournament_id AND p.player_id=o.player_id JOIN game.clubs b ON b.id=o.buyer_club_id JOIN game.clubs s ON s.id=o.seller_club_id WHERE o.tournament_id=v_tournament),'[]'::jsonb),
    'transfers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'playerId',tr.player_id,'playerName',p.name,'buyer',b.name,'seller',s.name,'amount',tr.amount,'kind',tr.kind,'createdAt',tr.created_at) ORDER BY tr.created_at DESC,tr.id DESC) FROM game.transfers tr JOIN game.players p ON p.tournament_id=tr.tournament_id AND p.player_id=tr.player_id JOIN game.clubs b ON b.id=tr.buyer_club_id LEFT JOIN game.clubs s ON s.id=tr.seller_club_id WHERE tr.tournament_id=v_tournament),'[]'::jsonb),
    'ledger',coalesce((SELECT jsonb_agg(jsonb_build_object('id',l.id,'amount',l.amount,'kind',o.kind,'createdAt',l.created_at) ORDER BY l.id DESC) FROM game.ledger l JOIN game.operations o ON o.id=l.operation_id JOIN game.accounts a ON a.id=l.account_id WHERE l.tournament_id=v_tournament AND a.club_id=v_club),'[]'::jsonb)) INTO v_result;
  RETURN v_result;
END $$;

DO $$ DECLARE v_table text; BEGIN
  FOREACH v_table IN ARRAY ARRAY['market_windows','market_limits','offers','transfers'] LOOP
    EXECUTE format('ALTER TABLE game.%I ENABLE ROW LEVEL SECURITY',v_table);
    EXECUTE format('REVOKE ALL ON game.%I FROM PUBLIC,anon,authenticated',v_table);
    EXECUTE format('GRANT SELECT,INSERT,UPDATE ON game.%I TO service_role',v_table);
  END LOOP;
END $$;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA game FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA game TO service_role;
REVOKE ALL ON FUNCTION public.game_market_command(text,text,uuid,text,uuid,uuid,bigint,text,integer),public.game_market_state(text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_market_command(text,text,uuid,text,uuid,uuid,bigint,text,integer),public.game_market_state(text,text) TO service_role;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005000400_game_market_counter.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000400','game_market_counter',ARRAY[$mercatto_source$ALTER TABLE game.offers ADD COLUMN proposed_amount bigint CHECK(proposed_amount>0),
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
$mercatto_source$]);

-- Migration 20261005000500_game_clause.sql
ALTER TABLE game.market_windows ADD COLUMN clause_protection_limit integer NOT NULL DEFAULT 1 CHECK(clause_protection_limit BETWEEN 0 AND 10);
UPDATE game.market_windows w SET clause_protection_limit=greatest(0,least(10,t.clause_protection_limit)) FROM public.tournaments t WHERE t.id=w.tournament_id;
CREATE FUNCTION game.snapshot_clause_rules() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  SELECT greatest(0,least(10,t.clause_protection_limit)) INTO NEW.clause_protection_limit FROM public.tournaments t WHERE t.id=NEW.tournament_id;
  RETURN NEW;
END $$;
CREATE TRIGGER snapshot_clause_rules BEFORE INSERT ON game.market_windows FOR EACH ROW EXECUTE FUNCTION game.snapshot_clause_rules();
ALTER TABLE game.transfers DROP CONSTRAINT transfers_kind_check;
ALTER TABLE game.transfers ADD CONSTRAINT transfers_kind_check CHECK(kind IN('offer','free','clause'));
CREATE UNIQUE INDEX one_managed_transfer_per_window ON game.transfers(window_id,player_id) WHERE kind IN('offer','clause');
CREATE TABLE game.clause_attempts (
  tournament_id uuid NOT NULL,
  window_id uuid NOT NULL,
  buyer_club_id uuid NOT NULL,
  seller_club_id uuid NOT NULL CHECK(seller_club_id<>buyer_club_id),
  player_id uuid NOT NULL,
  operation_id uuid NOT NULL UNIQUE,
  amount bigint NOT NULL CHECK(amount>0),
  outcome text NOT NULL CHECK(outcome IN('accepted','rejected')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(window_id,buyer_club_id,player_id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,buyer_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,seller_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id),
  FOREIGN KEY(tournament_id,operation_id) REFERENCES game.operations(tournament_id,id)
);
ALTER TABLE game.clause_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.clause_attempts FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON game.clause_attempts TO service_role;
CREATE TRIGGER immutable_clause_attempts BEFORE UPDATE OR DELETE ON game.clause_attempts FOR EACH ROW EXECUTE FUNCTION game.immutable_history();

CREATE FUNCTION public.game_pay_clause(p_code text,p_token text,p_key uuid,p_player uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE
  v_member uuid; v_tournament uuid; v_buyer uuid; v_seller uuid; v_window game.market_windows; v_contract game.contracts;
  v_old game.operations; v_key text; v_payload jsonb; v_now timestamptz; v_amount bigint; v_icon boolean;
  v_reserved bigint; v_held integer; v_account uuid; v_seller_account uuid; v_op uuid:=gen_random_uuid();
  v_rejected boolean; v_result jsonb; v_row record;
BEGIN
  IF p_key IS NULL OR p_player IS NULL THEN RAISE EXCEPTION 'Invalid clause request'; END IF;
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  PERFORM 1 FROM game.tournaments WHERE id=v_tournament FOR UPDATE;
  v_now:=clock_timestamp(); v_key:='clause:'||v_member||':'||p_key; v_payload:=jsonb_build_object('player',p_player);
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  SELECT club_id INTO v_buyer FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  IF v_buyer IS NULL THEN RAISE EXCEPTION 'Choose a club first' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_window FROM game.market_windows WHERE tournament_id=v_tournament AND status='open' FOR UPDATE;
  IF v_window.id IS NULL THEN RAISE EXCEPTION 'No open market' USING ERRCODE='GM001'; END IF;
  IF v_now>=v_window.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL FOR UPDATE;
  IF v_contract.id IS NULL OR v_contract.club_id=v_buyer THEN RAISE EXCEPTION 'Player has no eligible seller' USING ERRCODE='GM001'; END IF;
  v_seller:=v_contract.club_id; v_amount:=v_contract.clause;
  IF NOT EXISTS(SELECT 1 FROM game.assignments WHERE tournament_id=v_tournament AND club_id=v_seller AND ended_at IS NULL) THEN RAISE EXCEPTION 'Seller club has no manager' USING ERRCODE='GM001'; END IF;
  IF v_amount IS NULL OR v_amount<=0 THEN RAISE EXCEPTION 'Player has no valid clause' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.clause_attempts WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player) THEN RAISE EXCEPTION 'Clause already attempted in this window' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player AND kind IN('offer','clause')) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
  IF v_window.clause_protection_limit>0 AND (SELECT count(*) FROM game.transfers WHERE window_id=v_window.id AND seller_club_id=v_seller AND kind='clause')>=v_window.clause_protection_limit THEN
    RAISE EXCEPTION 'Seller clause protection reached' USING ERRCODE='GM001';
  END IF;
  -- An accepted clause replaces this buyer's pending offer for the same player.
  SELECT coalesce(sum(amount),0),count(*) INTO v_reserved,v_held FROM game.offers WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player AND status='pending';
  PERFORM 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id IN(v_buyer,v_seller) ORDER BY id FOR UPDATE;
  SELECT id INTO v_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_buyer AND balance-reserved+v_reserved>=v_amount;
  IF v_account IS NULL THEN RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001'; END IF;
  IF NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=v_window.id AND club_id=v_buyer AND purchases_used+purchases_held-v_held<purchase_limit) THEN RAISE EXCEPTION 'No purchase slots available' USING ERRCODE='GM001'; END IF;
  v_rejected:=random()<0.25;
  v_result:=jsonb_build_object('operationId',v_op,'playerId',p_player,'amount',v_amount,'rejected',v_rejected);
  INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result) VALUES(v_op,v_tournament,'market_clause',v_key,v_payload,v_result);
  INSERT INTO game.clause_attempts(tournament_id,window_id,buyer_club_id,seller_club_id,player_id,operation_id,amount,outcome)
    VALUES(v_tournament,v_window.id,v_buyer,v_seller,p_player,v_op,v_amount,CASE WHEN v_rejected THEN 'rejected' ELSE 'accepted' END);
  IF v_rejected THEN RETURN v_result; END IF;
  FOR v_row IN SELECT id FROM game.offers WHERE tournament_id=v_tournament AND player_id=p_player AND status='pending' ORDER BY id LOOP
    PERFORM game.release_offer(v_row.id,'stale');
  END LOOP;
  SELECT id INTO v_seller_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_seller;
  IF v_seller_account IS NULL THEN RAISE EXCEPTION 'Missing counterparty account'; END IF;
  UPDATE game.market_limits SET purchases_used=purchases_used+1 WHERE window_id=v_window.id AND club_id=v_buyer;
  UPDATE game.accounts SET balance=balance-v_amount WHERE id=v_account;
  UPDATE game.accounts SET balance=balance+v_amount WHERE id=v_seller_account;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES(v_tournament,v_op,v_account,-v_amount),(v_tournament,v_op,v_seller_account,v_amount);
  SELECT is_icon INTO v_icon FROM game.players WHERE tournament_id=v_tournament AND player_id=p_player;
  UPDATE game.contracts SET ended_at=v_now WHERE id=v_contract.id;
  INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause,started_at)
    VALUES(v_tournament,p_player,v_buyer,v_amount,CASE WHEN v_icon THEN round(v_amount::numeric*1.3)::bigint ELSE v_amount END,v_now);
  INSERT INTO game.transfers(tournament_id,operation_id,window_id,buyer_club_id,seller_club_id,player_id,amount,kind)
    VALUES(v_tournament,v_op,v_window.id,v_buyer,v_seller,p_player,v_amount,'clause');
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.game_pay_clause(text,text,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_pay_clause(text,text,uuid,uuid) TO service_role;

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
    'limits',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',l.club_id,'used',l.purchases_used,'held',l.purchases_held,'limit',l.purchase_limit)) FROM game.market_limits l JOIN game.market_windows w ON w.id=l.window_id WHERE l.tournament_id=v_tournament AND w.status='open'),'[]'::jsonb),
    'freePlayers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'price',p.reference_price) ORDER BY p.name) FROM game.players p WHERE p.tournament_id=v_tournament AND NOT p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p.tournament_id AND c.player_id=p.player_id AND c.ended_at IS NULL)),'[]'::jsonb),
    'clauseAttempts',coalesce((SELECT jsonb_agg(jsonb_build_object('windowId',a.window_id,'buyerClubId',a.buyer_club_id,'buyer',b.name,'seller',s.name,'playerId',a.player_id,'playerName',p.name,'amount',a.amount,'outcome',a.outcome,'createdAt',a.created_at) ORDER BY a.created_at DESC) FROM game.clause_attempts a JOIN game.clubs b ON b.id=a.buyer_club_id JOIN game.clubs s ON s.id=a.seller_club_id JOIN game.players p ON p.tournament_id=a.tournament_id AND p.player_id=a.player_id WHERE a.tournament_id=v_tournament),'[]'::jsonb),
    'offers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'windowId',o.window_id,'playerId',o.player_id,'playerName',p.name,'buyerClubId',o.buyer_club_id,'sellerClubId',o.seller_club_id,'buyer',b.name,'seller',s.name,'amount',o.amount,'status',o.status,'proposedAmount',o.proposed_amount,'proposedByClubId',o.proposed_by_club_id,
      'revisions',coalesce((SELECT jsonb_agg(jsonb_build_object('revision',r.revision,'authorClubId',r.author_club_id,'amount',r.amount) ORDER BY r.revision) FROM game.offer_revisions r WHERE r.offer_id=o.id),'[]'::jsonb)) ORDER BY o.created_at DESC,o.id DESC) FROM game.offers o JOIN game.players p ON p.tournament_id=o.tournament_id AND p.player_id=o.player_id JOIN game.clubs b ON b.id=o.buyer_club_id JOIN game.clubs s ON s.id=o.seller_club_id WHERE o.tournament_id=v_tournament),'[]'::jsonb),
    'transfers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'playerId',tr.player_id,'playerName',p.name,'buyer',b.name,'seller',s.name,'amount',tr.amount,'kind',tr.kind,'createdAt',tr.created_at) ORDER BY tr.created_at DESC,tr.id DESC) FROM game.transfers tr JOIN game.players p ON p.tournament_id=tr.tournament_id AND p.player_id=tr.player_id JOIN game.clubs b ON b.id=tr.buyer_club_id LEFT JOIN game.clubs s ON s.id=tr.seller_club_id WHERE tr.tournament_id=v_tournament),'[]'::jsonb),
    'ledger',coalesce((SELECT jsonb_agg(jsonb_build_object('id',l.id,'amount',l.amount,'kind',o.kind,'createdAt',l.created_at) ORDER BY l.id DESC) FROM game.ledger l JOIN game.operations o ON o.id=l.operation_id JOIN game.accounts a ON a.id=l.account_id WHERE l.tournament_id=v_tournament AND a.club_id=v_club),'[]'::jsonb)) INTO v_result;
  RETURN v_result;
END $$;


NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000500','game_clause',ARRAY[$mercatto_source$ALTER TABLE game.market_windows ADD COLUMN clause_protection_limit integer NOT NULL DEFAULT 1 CHECK(clause_protection_limit BETWEEN 0 AND 10);
UPDATE game.market_windows w SET clause_protection_limit=greatest(0,least(10,t.clause_protection_limit)) FROM public.tournaments t WHERE t.id=w.tournament_id;
CREATE FUNCTION game.snapshot_clause_rules() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
  SELECT greatest(0,least(10,t.clause_protection_limit)) INTO NEW.clause_protection_limit FROM public.tournaments t WHERE t.id=NEW.tournament_id;
  RETURN NEW;
END $$;
CREATE TRIGGER snapshot_clause_rules BEFORE INSERT ON game.market_windows FOR EACH ROW EXECUTE FUNCTION game.snapshot_clause_rules();
ALTER TABLE game.transfers DROP CONSTRAINT transfers_kind_check;
ALTER TABLE game.transfers ADD CONSTRAINT transfers_kind_check CHECK(kind IN('offer','free','clause'));
CREATE UNIQUE INDEX one_managed_transfer_per_window ON game.transfers(window_id,player_id) WHERE kind IN('offer','clause');
CREATE TABLE game.clause_attempts (
  tournament_id uuid NOT NULL,
  window_id uuid NOT NULL,
  buyer_club_id uuid NOT NULL,
  seller_club_id uuid NOT NULL CHECK(seller_club_id<>buyer_club_id),
  player_id uuid NOT NULL,
  operation_id uuid NOT NULL UNIQUE,
  amount bigint NOT NULL CHECK(amount>0),
  outcome text NOT NULL CHECK(outcome IN('accepted','rejected')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(window_id,buyer_club_id,player_id),
  FOREIGN KEY(tournament_id,window_id) REFERENCES game.market_windows(tournament_id,id),
  FOREIGN KEY(tournament_id,buyer_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,seller_club_id) REFERENCES game.clubs(tournament_id,id),
  FOREIGN KEY(tournament_id,player_id) REFERENCES game.players(tournament_id,player_id),
  FOREIGN KEY(tournament_id,operation_id) REFERENCES game.operations(tournament_id,id)
);
ALTER TABLE game.clause_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.clause_attempts FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON game.clause_attempts TO service_role;
CREATE TRIGGER immutable_clause_attempts BEFORE UPDATE OR DELETE ON game.clause_attempts FOR EACH ROW EXECUTE FUNCTION game.immutable_history();

CREATE FUNCTION public.game_pay_clause(p_code text,p_token text,p_key uuid,p_player uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE
  v_member uuid; v_tournament uuid; v_buyer uuid; v_seller uuid; v_window game.market_windows; v_contract game.contracts;
  v_old game.operations; v_key text; v_payload jsonb; v_now timestamptz; v_amount bigint; v_icon boolean;
  v_reserved bigint; v_held integer; v_account uuid; v_seller_account uuid; v_op uuid:=gen_random_uuid();
  v_rejected boolean; v_result jsonb; v_row record;
BEGIN
  IF p_key IS NULL OR p_player IS NULL THEN RAISE EXCEPTION 'Invalid clause request'; END IF;
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  PERFORM 1 FROM game.tournaments WHERE id=v_tournament FOR UPDATE;
  v_now:=clock_timestamp(); v_key:='clause:'||v_member||':'||p_key; v_payload:=jsonb_build_object('player',p_player);
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  SELECT club_id INTO v_buyer FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  IF v_buyer IS NULL THEN RAISE EXCEPTION 'Choose a club first' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_window FROM game.market_windows WHERE tournament_id=v_tournament AND status='open' FOR UPDATE;
  IF v_window.id IS NULL THEN RAISE EXCEPTION 'No open market' USING ERRCODE='GM001'; END IF;
  IF v_now>=v_window.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL FOR UPDATE;
  IF v_contract.id IS NULL OR v_contract.club_id=v_buyer THEN RAISE EXCEPTION 'Player has no eligible seller' USING ERRCODE='GM001'; END IF;
  v_seller:=v_contract.club_id; v_amount:=v_contract.clause;
  IF NOT EXISTS(SELECT 1 FROM game.assignments WHERE tournament_id=v_tournament AND club_id=v_seller AND ended_at IS NULL) THEN RAISE EXCEPTION 'Seller club has no manager' USING ERRCODE='GM001'; END IF;
  IF v_amount IS NULL OR v_amount<=0 THEN RAISE EXCEPTION 'Player has no valid clause' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.clause_attempts WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player) THEN RAISE EXCEPTION 'Clause already attempted in this window' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player AND kind IN('offer','clause')) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
  IF v_window.clause_protection_limit>0 AND (SELECT count(*) FROM game.transfers WHERE window_id=v_window.id AND seller_club_id=v_seller AND kind='clause')>=v_window.clause_protection_limit THEN
    RAISE EXCEPTION 'Seller clause protection reached' USING ERRCODE='GM001';
  END IF;
  -- An accepted clause replaces this buyer's pending offer for the same player.
  SELECT coalesce(sum(amount),0),count(*) INTO v_reserved,v_held FROM game.offers WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player AND status='pending';
  PERFORM 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id IN(v_buyer,v_seller) ORDER BY id FOR UPDATE;
  SELECT id INTO v_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_buyer AND balance-reserved+v_reserved>=v_amount;
  IF v_account IS NULL THEN RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001'; END IF;
  IF NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=v_window.id AND club_id=v_buyer AND purchases_used+purchases_held-v_held<purchase_limit) THEN RAISE EXCEPTION 'No purchase slots available' USING ERRCODE='GM001'; END IF;
  v_rejected:=random()<0.25;
  v_result:=jsonb_build_object('operationId',v_op,'playerId',p_player,'amount',v_amount,'rejected',v_rejected);
  INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result) VALUES(v_op,v_tournament,'market_clause',v_key,v_payload,v_result);
  INSERT INTO game.clause_attempts(tournament_id,window_id,buyer_club_id,seller_club_id,player_id,operation_id,amount,outcome)
    VALUES(v_tournament,v_window.id,v_buyer,v_seller,p_player,v_op,v_amount,CASE WHEN v_rejected THEN 'rejected' ELSE 'accepted' END);
  IF v_rejected THEN RETURN v_result; END IF;
  FOR v_row IN SELECT id FROM game.offers WHERE tournament_id=v_tournament AND player_id=p_player AND status='pending' ORDER BY id LOOP
    PERFORM game.release_offer(v_row.id,'stale');
  END LOOP;
  SELECT id INTO v_seller_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_seller;
  IF v_seller_account IS NULL THEN RAISE EXCEPTION 'Missing counterparty account'; END IF;
  UPDATE game.market_limits SET purchases_used=purchases_used+1 WHERE window_id=v_window.id AND club_id=v_buyer;
  UPDATE game.accounts SET balance=balance-v_amount WHERE id=v_account;
  UPDATE game.accounts SET balance=balance+v_amount WHERE id=v_seller_account;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES(v_tournament,v_op,v_account,-v_amount),(v_tournament,v_op,v_seller_account,v_amount);
  SELECT is_icon INTO v_icon FROM game.players WHERE tournament_id=v_tournament AND player_id=p_player;
  UPDATE game.contracts SET ended_at=v_now WHERE id=v_contract.id;
  INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause,started_at)
    VALUES(v_tournament,p_player,v_buyer,v_amount,CASE WHEN v_icon THEN round(v_amount::numeric*1.3)::bigint ELSE v_amount END,v_now);
  INSERT INTO game.transfers(tournament_id,operation_id,window_id,buyer_club_id,seller_club_id,player_id,amount,kind)
    VALUES(v_tournament,v_op,v_window.id,v_buyer,v_seller,p_player,v_amount,'clause');
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION public.game_pay_clause(text,text,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_pay_clause(text,text,uuid,uuid) TO service_role;

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
    'limits',coalesce((SELECT jsonb_agg(jsonb_build_object('clubId',l.club_id,'used',l.purchases_used,'held',l.purchases_held,'limit',l.purchase_limit)) FROM game.market_limits l JOIN game.market_windows w ON w.id=l.window_id WHERE l.tournament_id=v_tournament AND w.status='open'),'[]'::jsonb),
    'freePlayers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',p.player_id,'name',p.name,'ovr',p.ovr,'price',p.reference_price) ORDER BY p.name) FROM game.players p WHERE p.tournament_id=v_tournament AND NOT p.is_icon AND NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=p.tournament_id AND c.player_id=p.player_id AND c.ended_at IS NULL)),'[]'::jsonb),
    'clauseAttempts',coalesce((SELECT jsonb_agg(jsonb_build_object('windowId',a.window_id,'buyerClubId',a.buyer_club_id,'buyer',b.name,'seller',s.name,'playerId',a.player_id,'playerName',p.name,'amount',a.amount,'outcome',a.outcome,'createdAt',a.created_at) ORDER BY a.created_at DESC) FROM game.clause_attempts a JOIN game.clubs b ON b.id=a.buyer_club_id JOIN game.clubs s ON s.id=a.seller_club_id JOIN game.players p ON p.tournament_id=a.tournament_id AND p.player_id=a.player_id WHERE a.tournament_id=v_tournament),'[]'::jsonb),
    'offers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',o.id,'windowId',o.window_id,'playerId',o.player_id,'playerName',p.name,'buyerClubId',o.buyer_club_id,'sellerClubId',o.seller_club_id,'buyer',b.name,'seller',s.name,'amount',o.amount,'status',o.status,'proposedAmount',o.proposed_amount,'proposedByClubId',o.proposed_by_club_id,
      'revisions',coalesce((SELECT jsonb_agg(jsonb_build_object('revision',r.revision,'authorClubId',r.author_club_id,'amount',r.amount) ORDER BY r.revision) FROM game.offer_revisions r WHERE r.offer_id=o.id),'[]'::jsonb)) ORDER BY o.created_at DESC,o.id DESC) FROM game.offers o JOIN game.players p ON p.tournament_id=o.tournament_id AND p.player_id=o.player_id JOIN game.clubs b ON b.id=o.buyer_club_id JOIN game.clubs s ON s.id=o.seller_club_id WHERE o.tournament_id=v_tournament),'[]'::jsonb),
    'transfers',coalesce((SELECT jsonb_agg(jsonb_build_object('id',tr.id,'playerId',tr.player_id,'playerName',p.name,'buyer',b.name,'seller',s.name,'amount',tr.amount,'kind',tr.kind,'createdAt',tr.created_at) ORDER BY tr.created_at DESC,tr.id DESC) FROM game.transfers tr JOIN game.players p ON p.tournament_id=tr.tournament_id AND p.player_id=tr.player_id JOIN game.clubs b ON b.id=tr.buyer_club_id LEFT JOIN game.clubs s ON s.id=tr.seller_club_id WHERE tr.tournament_id=v_tournament),'[]'::jsonb),
    'ledger',coalesce((SELECT jsonb_agg(jsonb_build_object('id',l.id,'amount',l.amount,'kind',o.kind,'createdAt',l.created_at) ORDER BY l.id DESC) FROM game.ledger l JOIN game.operations o ON o.id=l.operation_id JOIN game.accounts a ON a.id=l.account_id WHERE l.tournament_id=v_tournament AND a.club_id=v_club),'[]'::jsonb)) INTO v_result;
  RETURN v_result;
END $$;


NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005000600_game_clause_keys.sql
-- Clause and negotiation commands share actor-scoped idempotency keys.
CREATE OR REPLACE FUNCTION public.game_pay_clause(p_code text,p_token text,p_key uuid,p_player uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE
  v_member uuid; v_tournament uuid; v_buyer uuid; v_seller uuid; v_window game.market_windows; v_contract game.contracts;
  v_old game.operations; v_key text; v_payload jsonb; v_now timestamptz; v_amount bigint; v_icon boolean;
  v_reserved bigint; v_held integer; v_account uuid; v_seller_account uuid; v_op uuid:=gen_random_uuid();
  v_rejected boolean; v_result jsonb; v_row record;
BEGIN
  IF p_key IS NULL OR p_player IS NULL THEN RAISE EXCEPTION 'Invalid clause request'; END IF;
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  PERFORM 1 FROM game.tournaments WHERE id=v_tournament FOR UPDATE;
  v_now:=clock_timestamp(); v_key:='market:'||v_member||':'||p_key; v_payload:=jsonb_build_object('action','clause','player',p_player,'offer',NULL,'amount',NULL,'kind',NULL,'minutes',NULL);
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  -- Preserve already committed local attempts made before the unified market namespace.
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key='clause:'||v_member||':'||p_key;
  IF FOUND THEN
    IF v_old.payload<>jsonb_build_object('player',p_player) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  SELECT club_id INTO v_buyer FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  IF v_buyer IS NULL THEN RAISE EXCEPTION 'Choose a club first' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_window FROM game.market_windows WHERE tournament_id=v_tournament AND status='open' FOR UPDATE;
  IF v_window.id IS NULL THEN RAISE EXCEPTION 'No open market' USING ERRCODE='GM001'; END IF;
  IF v_now>=v_window.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL FOR UPDATE;
  IF v_contract.id IS NULL OR v_contract.club_id=v_buyer THEN RAISE EXCEPTION 'Player has no eligible seller' USING ERRCODE='GM001'; END IF;
  v_seller:=v_contract.club_id; v_amount:=v_contract.clause;
  IF NOT EXISTS(SELECT 1 FROM game.assignments WHERE tournament_id=v_tournament AND club_id=v_seller AND ended_at IS NULL) THEN RAISE EXCEPTION 'Seller club has no manager' USING ERRCODE='GM001'; END IF;
  IF v_amount IS NULL OR v_amount<=0 THEN RAISE EXCEPTION 'Player has no valid clause' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.clause_attempts WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player) THEN RAISE EXCEPTION 'Clause already attempted in this window' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player AND kind IN('offer','clause')) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
  IF v_window.clause_protection_limit>0 AND (SELECT count(*) FROM game.transfers WHERE window_id=v_window.id AND seller_club_id=v_seller AND kind='clause')>=v_window.clause_protection_limit THEN
    RAISE EXCEPTION 'Seller clause protection reached' USING ERRCODE='GM001';
  END IF;
  -- An accepted clause replaces this buyer's pending offer for the same player.
  SELECT coalesce(sum(amount),0),count(*) INTO v_reserved,v_held FROM game.offers WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player AND status='pending';
  PERFORM 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id IN(v_buyer,v_seller) ORDER BY id FOR UPDATE;
  SELECT id INTO v_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_buyer AND balance-reserved+v_reserved>=v_amount;
  IF v_account IS NULL THEN RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001'; END IF;
  IF NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=v_window.id AND club_id=v_buyer AND purchases_used+purchases_held-v_held<purchase_limit) THEN RAISE EXCEPTION 'No purchase slots available' USING ERRCODE='GM001'; END IF;
  v_rejected:=random()<0.25;
  v_result:=jsonb_build_object('operationId',v_op,'playerId',p_player,'amount',v_amount,'rejected',v_rejected);
  INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result) VALUES(v_op,v_tournament,'market_clause',v_key,v_payload,v_result);
  INSERT INTO game.clause_attempts(tournament_id,window_id,buyer_club_id,seller_club_id,player_id,operation_id,amount,outcome)
    VALUES(v_tournament,v_window.id,v_buyer,v_seller,p_player,v_op,v_amount,CASE WHEN v_rejected THEN 'rejected' ELSE 'accepted' END);
  IF v_rejected THEN RETURN v_result; END IF;
  FOR v_row IN SELECT id FROM game.offers WHERE tournament_id=v_tournament AND player_id=p_player AND status='pending' ORDER BY id LOOP
    PERFORM game.release_offer(v_row.id,'stale');
  END LOOP;
  SELECT id INTO v_seller_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_seller;
  IF v_seller_account IS NULL THEN RAISE EXCEPTION 'Missing counterparty account'; END IF;
  UPDATE game.market_limits SET purchases_used=purchases_used+1 WHERE window_id=v_window.id AND club_id=v_buyer;
  UPDATE game.accounts SET balance=balance-v_amount WHERE id=v_account;
  UPDATE game.accounts SET balance=balance+v_amount WHERE id=v_seller_account;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES(v_tournament,v_op,v_account,-v_amount),(v_tournament,v_op,v_seller_account,v_amount);
  SELECT is_icon INTO v_icon FROM game.players WHERE tournament_id=v_tournament AND player_id=p_player;
  UPDATE game.contracts SET ended_at=v_now WHERE id=v_contract.id;
  INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause,started_at)
    VALUES(v_tournament,p_player,v_buyer,v_amount,CASE WHEN v_icon THEN round(v_amount::numeric*1.3)::bigint ELSE v_amount END,v_now);
  INSERT INTO game.transfers(tournament_id,operation_id,window_id,buyer_club_id,seller_club_id,player_id,amount,kind)
    VALUES(v_tournament,v_op,v_window.id,v_buyer,v_seller,p_player,v_amount,'clause');
  RETURN v_result;
END $$;

NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000600','game_clause_keys',ARRAY[$mercatto_source$-- Clause and negotiation commands share actor-scoped idempotency keys.
CREATE OR REPLACE FUNCTION public.game_pay_clause(p_code text,p_token text,p_key uuid,p_player uuid) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE
  v_member uuid; v_tournament uuid; v_buyer uuid; v_seller uuid; v_window game.market_windows; v_contract game.contracts;
  v_old game.operations; v_key text; v_payload jsonb; v_now timestamptz; v_amount bigint; v_icon boolean;
  v_reserved bigint; v_held integer; v_account uuid; v_seller_account uuid; v_op uuid:=gen_random_uuid();
  v_rejected boolean; v_result jsonb; v_row record;
BEGIN
  IF p_key IS NULL OR p_player IS NULL THEN RAISE EXCEPTION 'Invalid clause request'; END IF;
  v_member:=game.require_member(p_code,p_token);
  SELECT tournament_id INTO v_tournament FROM public.members WHERE id=v_member;
  PERFORM 1 FROM game.tournaments WHERE id=v_tournament FOR UPDATE;
  v_now:=clock_timestamp(); v_key:='market:'||v_member||':'||p_key; v_payload:=jsonb_build_object('action','clause','player',p_player,'offer',NULL,'amount',NULL,'kind',NULL,'minutes',NULL);
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key=v_key;
  IF FOUND THEN
    IF v_old.payload<>v_payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  -- Preserve already committed local attempts made before the unified market namespace.
  SELECT * INTO v_old FROM game.operations WHERE tournament_id=v_tournament AND idempotency_key='clause:'||v_member||':'||p_key;
  IF FOUND THEN
    IF v_old.payload<>jsonb_build_object('player',p_player) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
    RETURN v_old.result;
  END IF;
  SELECT club_id INTO v_buyer FROM game.assignments WHERE tournament_id=v_tournament AND member_id=v_member AND ended_at IS NULL;
  IF v_buyer IS NULL THEN RAISE EXCEPTION 'Choose a club first' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_window FROM game.market_windows WHERE tournament_id=v_tournament AND status='open' FOR UPDATE;
  IF v_window.id IS NULL THEN RAISE EXCEPTION 'No open market' USING ERRCODE='GM001'; END IF;
  IF v_now>=v_window.closes_at THEN RAISE EXCEPTION 'Market deadline passed' USING ERRCODE='GM001'; END IF;
  SELECT * INTO v_contract FROM game.contracts WHERE tournament_id=v_tournament AND player_id=p_player AND ended_at IS NULL FOR UPDATE;
  IF v_contract.id IS NULL OR v_contract.club_id=v_buyer THEN RAISE EXCEPTION 'Player has no eligible seller' USING ERRCODE='GM001'; END IF;
  v_seller:=v_contract.club_id; v_amount:=v_contract.clause;
  IF NOT EXISTS(SELECT 1 FROM game.assignments WHERE tournament_id=v_tournament AND club_id=v_seller AND ended_at IS NULL) THEN RAISE EXCEPTION 'Seller club has no manager' USING ERRCODE='GM001'; END IF;
  IF v_amount IS NULL OR v_amount<=0 THEN RAISE EXCEPTION 'Player has no valid clause' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.clause_attempts WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player) THEN RAISE EXCEPTION 'Clause already attempted in this window' USING ERRCODE='GM001'; END IF;
  IF EXISTS(SELECT 1 FROM game.transfers WHERE window_id=v_window.id AND player_id=p_player AND kind IN('offer','clause')) THEN RAISE EXCEPTION 'Player already transferred in this window' USING ERRCODE='GM001'; END IF;
  IF v_window.clause_protection_limit>0 AND (SELECT count(*) FROM game.transfers WHERE window_id=v_window.id AND seller_club_id=v_seller AND kind='clause')>=v_window.clause_protection_limit THEN
    RAISE EXCEPTION 'Seller clause protection reached' USING ERRCODE='GM001';
  END IF;
  -- An accepted clause replaces this buyer's pending offer for the same player.
  SELECT coalesce(sum(amount),0),count(*) INTO v_reserved,v_held FROM game.offers WHERE window_id=v_window.id AND buyer_club_id=v_buyer AND player_id=p_player AND status='pending';
  PERFORM 1 FROM game.accounts WHERE tournament_id=v_tournament AND club_id IN(v_buyer,v_seller) ORDER BY id FOR UPDATE;
  SELECT id INTO v_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_buyer AND balance-reserved+v_reserved>=v_amount;
  IF v_account IS NULL THEN RAISE EXCEPTION 'Insufficient available balance' USING ERRCODE='GM001'; END IF;
  IF NOT EXISTS(SELECT 1 FROM game.market_limits WHERE window_id=v_window.id AND club_id=v_buyer AND purchases_used+purchases_held-v_held<purchase_limit) THEN RAISE EXCEPTION 'No purchase slots available' USING ERRCODE='GM001'; END IF;
  v_rejected:=random()<0.25;
  v_result:=jsonb_build_object('operationId',v_op,'playerId',p_player,'amount',v_amount,'rejected',v_rejected);
  INSERT INTO game.operations(id,tournament_id,kind,idempotency_key,payload,result) VALUES(v_op,v_tournament,'market_clause',v_key,v_payload,v_result);
  INSERT INTO game.clause_attempts(tournament_id,window_id,buyer_club_id,seller_club_id,player_id,operation_id,amount,outcome)
    VALUES(v_tournament,v_window.id,v_buyer,v_seller,p_player,v_op,v_amount,CASE WHEN v_rejected THEN 'rejected' ELSE 'accepted' END);
  IF v_rejected THEN RETURN v_result; END IF;
  FOR v_row IN SELECT id FROM game.offers WHERE tournament_id=v_tournament AND player_id=p_player AND status='pending' ORDER BY id LOOP
    PERFORM game.release_offer(v_row.id,'stale');
  END LOOP;
  SELECT id INTO v_seller_account FROM game.accounts WHERE tournament_id=v_tournament AND club_id=v_seller;
  IF v_seller_account IS NULL THEN RAISE EXCEPTION 'Missing counterparty account'; END IF;
  UPDATE game.market_limits SET purchases_used=purchases_used+1 WHERE window_id=v_window.id AND club_id=v_buyer;
  UPDATE game.accounts SET balance=balance-v_amount WHERE id=v_account;
  UPDATE game.accounts SET balance=balance+v_amount WHERE id=v_seller_account;
  INSERT INTO game.ledger(tournament_id,operation_id,account_id,amount) VALUES(v_tournament,v_op,v_account,-v_amount),(v_tournament,v_op,v_seller_account,v_amount);
  SELECT is_icon INTO v_icon FROM game.players WHERE tournament_id=v_tournament AND player_id=p_player;
  UPDATE game.contracts SET ended_at=v_now WHERE id=v_contract.id;
  INSERT INTO game.contracts(tournament_id,player_id,club_id,acquired_price,clause,started_at)
    VALUES(v_tournament,p_player,v_buyer,v_amount,CASE WHEN v_icon THEN round(v_amount::numeric*1.3)::bigint ELSE v_amount END,v_now);
  INSERT INTO game.transfers(tournament_id,operation_id,window_id,buyer_club_id,seller_club_id,player_id,amount,kind)
    VALUES(v_tournament,v_op,v_window.id,v_buyer,v_seller,p_player,v_amount,'clause');
  RETURN v_result;
END $$;

NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005000700_game_auctions.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000700','game_auctions',ARRAY[$mercatto_source$ALTER TABLE game.market_limits ADD COLUMN icons_used integer NOT NULL DEFAULT 0 CHECK(icons_used BETWEEN 0 AND 1),
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
$mercatto_source$]);

-- Migration 20261005000800_game_auction_worker.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000800','game_auction_worker',ARRAY[$mercatto_source$-- Avoid a table alias that shadows the worker window record; report expired auctions without writes.
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
$mercatto_source$]);

-- Migration 20261005000900_game_competition.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005000900','game_competition',ARRAY[$mercatto_source$-- Complete competition mode is opt-in for earlier disposable market prototypes.
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
$mercatto_source$]);

-- Migration 20261005001000_game_complete_market.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001000','game_complete_market',ARRAY[$mercatto_source$CREATE TABLE game.ballots (
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
$mercatto_source$]);

-- Migration 20261005001100_game_history_permissions.sql
-- Restore append-only grants after additive competition tables were installed.
REVOKE UPDATE ON game.clause_attempts,game.offer_revisions,game.auction_bids,
 game.lineups,game.lineup_confirmations,game.cards,game.suspension_servings,game.releases,
 game.daily_claims,game.draws,game.expenses,game.departures,game.ballot_options,game.electorate,game.votes FROM service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001100','game_history_permissions',ARRAY[$mercatto_source$-- Restore append-only grants after additive competition tables were installed.
REVOKE UPDATE ON game.clause_attempts,game.offer_revisions,game.auction_bids,
 game.lineups,game.lineup_confirmations,game.cards,game.suspension_servings,game.releases,
 game.daily_claims,game.draws,game.expenses,game.departures,game.ballot_options,game.electorate,game.votes FROM service_role;
$mercatto_source$]);

-- Migration 20261005001200_game_complete_guards.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001200','game_complete_guards',ARRAY[$mercatto_source$CREATE OR REPLACE FUNCTION public.game_competition_command(p_code text,p_token text,p_key uuid,p_action text,p_body jsonb DEFAULT '{}')
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
$mercatto_source$]);

-- Migration 20261005001300_game_finalization_guards.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001300','game_finalization_guards',ARRAY[$mercatto_source$CREATE OR REPLACE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,p_player uuid DEFAULT NULL,p_offer uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_minutes integer DEFAULT NULL)
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
$mercatto_source$]);

-- Migration 20261005001400_game_free_pool_social.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001400','game_free_pool_social',ARRAY[$mercatto_source$CREATE OR REPLACE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,p_player uuid DEFAULT NULL,p_offer uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_minutes integer DEFAULT NULL)
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
$mercatto_source$]);

-- Migration 20261005001500_game_local_cutover_access.sql
-- Apply with the new backend cutover; never independently to the legacy remote app.
-- Legacy rows are retained. Browser clients cannot mutate authentication or catalogue data.
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['tournaments','members','assignments','member_roster','listings','market_sessions','market_turns','market_transfers','market_offers','league_sessions','fixtures','matchday_rests','discipline','suspensions','icon_auctions','icon_activation_votes','icon_selection_votes','icon_bids','lineups','notifications','push_subscriptions','icon_votes','social_profiles','posts','post_likes'] LOOP
 EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon,authenticated',name);
 EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',name);
 END LOOP;
 FOREACH name IN ARRAY ARRAY['teams','players','team_players'] LOOP
 EXECUTE format('REVOKE INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON TABLE public.%I FROM anon,authenticated',name);
 END LOOP;
END $$;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001500','game_local_cutover_access',ARRAY[$mercatto_source$-- Apply with the new backend cutover; never independently to the legacy remote app.
-- Legacy rows are retained. Browser clients cannot mutate authentication or catalogue data.
DO $$ DECLARE name text; BEGIN
 FOREACH name IN ARRAY ARRAY['tournaments','members','assignments','member_roster','listings','market_sessions','market_turns','market_transfers','market_offers','league_sessions','fixtures','matchday_rests','discipline','suspensions','icon_auctions','icon_activation_votes','icon_selection_votes','icon_bids','lineups','notifications','push_subscriptions','icon_votes','social_profiles','posts','post_likes'] LOOP
 EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon,authenticated',name);
 EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',name);
 END LOOP;
 FOREACH name IN ARRAY ARRAY['teams','players','team_players'] LOOP
 EXECUTE format('REVOKE INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER ON TABLE public.%I FROM anon,authenticated',name);
 END LOOP;
END $$;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005001600_game_scope_constraints.sql
ALTER TABLE public.posts ADD CONSTRAINT posts_tournament_id_id_key UNIQUE(tournament_id,id);
ALTER TABLE public.posts ADD CONSTRAINT posts_scoped_parent FOREIGN KEY(tournament_id,parent_id) REFERENCES public.posts(tournament_id,id) NOT VALID;
CREATE FUNCTION game.guard_social_like_scope() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.posts p JOIN public.members m ON m.tournament_id=p.tournament_id WHERE p.id=NEW.post_id AND m.id=NEW.member_id) THEN RAISE EXCEPTION 'Like belongs to another tournament'; END IF;RETURN NEW;
END $$;
CREATE TRIGGER social_like_scope BEFORE INSERT OR UPDATE ON public.post_likes FOR EACH ROW EXECUTE FUNCTION game.guard_social_like_scope();
ALTER TABLE game.fixtures ADD CONSTRAINT fixture_season_scope UNIQUE(tournament_id,season_id,id);
ALTER TABLE game.cards ADD CONSTRAINT card_fixture_season_scope FOREIGN KEY(tournament_id,season_id,fixture_id) REFERENCES game.fixtures(tournament_id,season_id,id);
ALTER TABLE game.suspensions ADD CONSTRAINT sanction_fixture_season_scope FOREIGN KEY(tournament_id,season_id,origin_fixture_id) REFERENCES game.fixtures(tournament_id,season_id,id);
REVOKE ALL ON FUNCTION game.guard_social_like_scope() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION game.guard_social_like_scope() TO service_role;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001600','game_scope_constraints',ARRAY[$mercatto_source$ALTER TABLE public.posts ADD CONSTRAINT posts_tournament_id_id_key UNIQUE(tournament_id,id);
ALTER TABLE public.posts ADD CONSTRAINT posts_scoped_parent FOREIGN KEY(tournament_id,parent_id) REFERENCES public.posts(tournament_id,id) NOT VALID;
CREATE FUNCTION game.guard_social_like_scope() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.posts p JOIN public.members m ON m.tournament_id=p.tournament_id WHERE p.id=NEW.post_id AND m.id=NEW.member_id) THEN RAISE EXCEPTION 'Like belongs to another tournament'; END IF;RETURN NEW;
END $$;
CREATE TRIGGER social_like_scope BEFORE INSERT OR UPDATE ON public.post_likes FOR EACH ROW EXECUTE FUNCTION game.guard_social_like_scope();
ALTER TABLE game.fixtures ADD CONSTRAINT fixture_season_scope UNIQUE(tournament_id,season_id,id);
ALTER TABLE game.cards ADD CONSTRAINT card_fixture_season_scope FOREIGN KEY(tournament_id,season_id,fixture_id) REFERENCES game.fixtures(tournament_id,season_id,id);
ALTER TABLE game.suspensions ADD CONSTRAINT sanction_fixture_season_scope FOREIGN KEY(tournament_id,season_id,origin_fixture_id) REFERENCES game.fixtures(tournament_id,season_id,id);
REVOKE ALL ON FUNCTION game.guard_social_like_scope() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION game.guard_social_like_scope() TO service_role;
$mercatto_source$]);

-- Migration 20261005001700_game_daily_retry.sql
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
 IF NOT EXISTS(SELECT 1 FROM game.daily_claims WHERE operation_id=op) THEN
 INSERT INTO game.daily_claims VALUES(tid,club,(clock_timestamp() AT TIME ZONE 'America/Bogota')::date,coalesce(v_tier,(SELECT CASE WHEN ovr>=84 THEN 'premium' ELSE 'basic' END FROM game.players WHERE tournament_id=tid AND player_id=p_player)),op) ON CONFLICT DO NOTHING;
 END IF; END IF; END IF; RETURN result;
END $$;

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001700','game_daily_retry',ARRAY[$mercatto_source$CREATE OR REPLACE FUNCTION public.game_market_command(p_code text,p_token text,p_key uuid,p_action text,p_player uuid DEFAULT NULL,p_offer uuid DEFAULT NULL,p_amount bigint DEFAULT NULL,p_kind text DEFAULT NULL,p_minutes integer DEFAULT NULL)
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
 IF NOT EXISTS(SELECT 1 FROM game.daily_claims WHERE operation_id=op) THEN
 INSERT INTO game.daily_claims VALUES(tid,club,(clock_timestamp() AT TIME ZONE 'America/Bogota')::date,coalesce(v_tier,(SELECT CASE WHEN ovr>=84 THEN 'premium' ELSE 'basic' END FROM game.players WHERE tournament_id=tid AND player_id=p_player)),op) ON CONFLICT DO NOTHING;
 END IF; END IF; END IF; RETURN result;
END $$;
$mercatto_source$]);

-- Migration 20261005001800_game_creation_mode.sql
CREATE FUNCTION public.game_create_entry(p_key uuid,p_name text,p_display_name text,p_admin_token text,p_member_token text,p_teams uuid[],p_free_players uuid[],p_complete boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$ DECLARE old game.creation_requests; result jsonb; BEGIN
 IF p_key IS NULL OR p_complete IS NULL THEN RAISE EXCEPTION 'Invalid creation mode'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 SELECT * INTO old FROM game.creation_requests WHERE request_key=p_key;
 IF FOUND AND EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=old.tournament_id) IS DISTINCT FROM p_complete THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
 IF p_complete THEN result:=public.game_create_competition(p_key,p_name,p_display_name,p_admin_token,p_member_token,p_teams,p_free_players);
 ELSE result:=public.game_create_tournament(p_key,p_name,p_display_name,p_admin_token,p_member_token,p_teams,p_free_players); END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_create_entry(uuid,text,text,text,text,uuid[],uuid[],boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_create_entry(uuid,text,text,text,text,uuid[],uuid[],boolean) TO service_role;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001800','game_creation_mode',ARRAY[$mercatto_source$CREATE FUNCTION public.game_create_entry(p_key uuid,p_name text,p_display_name text,p_admin_token text,p_member_token text,p_teams uuid[],p_free_players uuid[],p_complete boolean DEFAULT true)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$ DECLARE old game.creation_requests; result jsonb; BEGIN
 IF p_key IS NULL OR p_complete IS NULL THEN RAISE EXCEPTION 'Invalid creation mode'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 SELECT * INTO old FROM game.creation_requests WHERE request_key=p_key;
 IF FOUND AND EXISTS(SELECT 1 FROM game.rules WHERE tournament_id=old.tournament_id) IS DISTINCT FROM p_complete THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
 IF p_complete THEN result:=public.game_create_competition(p_key,p_name,p_display_name,p_admin_token,p_member_token,p_teams,p_free_players);
 ELSE result:=public.game_create_tournament(p_key,p_name,p_display_name,p_admin_token,p_member_token,p_teams,p_free_players); END IF;
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_create_entry(uuid,text,text,text,text,uuid[],uuid[],boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_create_entry(uuid,text,text,text,text,uuid[],uuid[],boolean) TO service_role;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005001900_game_creation_settings.sql
-- Preserve the settings exposed by the original creation form, atomically.
CREATE TABLE game.creation_settings (
 request_key uuid PRIMARY KEY REFERENCES game.creation_requests(request_key),
 settings jsonb NOT NULL
);
ALTER TABLE game.creation_settings ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT ON game.creation_settings TO service_role;
CREATE FUNCTION public.game_create_configured(p_key uuid,p_name text,p_display_name text,p_admin_token text,p_member_token text,p_teams uuid[],p_free_players uuid[],p_complete boolean DEFAULT true,p_settings jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE result jsonb; tid uuid; prior jsonb;
BEGIN
 IF jsonb_typeof(p_settings)<>'object' OR p_settings IS NULL THEN RAISE EXCEPTION 'Invalid creation settings'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_settings) k WHERE k NOT IN('rerolls','maxTransfers','clauseProtection')) THEN RAISE EXCEPTION 'Invalid creation settings'; END IF;
 IF p_settings ? 'rerolls' AND (p_settings->>'rerolls')::integer NOT BETWEEN 0 AND 10 OR p_settings ? 'maxTransfers' AND (p_settings->>'maxTransfers')::integer NOT BETWEEN 1 AND 10 OR p_settings ? 'clauseProtection' AND (p_settings->>'clauseProtection')::integer NOT BETWEEN 0 AND 10 THEN RAISE EXCEPTION 'Invalid creation settings'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 SELECT settings INTO prior FROM game.creation_settings WHERE request_key=p_key;
 IF FOUND AND prior<>p_settings THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
 result:=public.game_create_entry(p_key,p_name,p_display_name,p_admin_token,p_member_token,p_teams,p_free_players,p_complete);
 IF prior IS NOT NULL THEN RETURN result; END IF;
 tid:=(result->>'id')::uuid;
 UPDATE public.tournaments SET max_transfers=coalesce((p_settings->>'maxTransfers')::integer,max_transfers),clause_protection_limit=coalesce((p_settings->>'clauseProtection')::integer,clause_protection_limit) WHERE id=tid;
 UPDATE game.rules SET rerolls=coalesce((p_settings->>'rerolls')::integer,rerolls) WHERE tournament_id=tid;
 INSERT INTO game.creation_settings VALUES(p_key,p_settings);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_create_configured(uuid,text,text,text,text,uuid[],uuid[],boolean,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_create_configured(uuid,text,text,text,text,uuid[],uuid[],boolean,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005001900','game_creation_settings',ARRAY[$mercatto_source$-- Preserve the settings exposed by the original creation form, atomically.
CREATE TABLE game.creation_settings (
 request_key uuid PRIMARY KEY REFERENCES game.creation_requests(request_key),
 settings jsonb NOT NULL
);
ALTER TABLE game.creation_settings ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT ON game.creation_settings TO service_role;
CREATE FUNCTION public.game_create_configured(p_key uuid,p_name text,p_display_name text,p_admin_token text,p_member_token text,p_teams uuid[],p_free_players uuid[],p_complete boolean DEFAULT true,p_settings jsonb DEFAULT '{}')
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE result jsonb; tid uuid; prior jsonb;
BEGIN
 IF jsonb_typeof(p_settings)<>'object' OR p_settings IS NULL THEN RAISE EXCEPTION 'Invalid creation settings'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_object_keys(p_settings) k WHERE k NOT IN('rerolls','maxTransfers','clauseProtection')) THEN RAISE EXCEPTION 'Invalid creation settings'; END IF;
 IF p_settings ? 'rerolls' AND (p_settings->>'rerolls')::integer NOT BETWEEN 0 AND 10 OR p_settings ? 'maxTransfers' AND (p_settings->>'maxTransfers')::integer NOT BETWEEN 1 AND 10 OR p_settings ? 'clauseProtection' AND (p_settings->>'clauseProtection')::integer NOT BETWEEN 0 AND 10 THEN RAISE EXCEPTION 'Invalid creation settings'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_key::text,0));
 SELECT settings INTO prior FROM game.creation_settings WHERE request_key=p_key;
 IF FOUND AND prior<>p_settings THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
 result:=public.game_create_entry(p_key,p_name,p_display_name,p_admin_token,p_member_token,p_teams,p_free_players,p_complete);
 IF prior IS NOT NULL THEN RETURN result; END IF;
 tid:=(result->>'id')::uuid;
 UPDATE public.tournaments SET max_transfers=coalesce((p_settings->>'maxTransfers')::integer,max_transfers),clause_protection_limit=coalesce((p_settings->>'clauseProtection')::integer,clause_protection_limit) WHERE id=tid;
 UPDATE game.rules SET rerolls=coalesce((p_settings->>'rerolls')::integer,rerolls) WHERE tournament_id=tid;
 INSERT INTO game.creation_settings VALUES(p_key,p_settings);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_create_configured(uuid,text,text,text,text,uuid[],uuid[],boolean,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_create_configured(uuid,text,text,text,text,uuid[],uuid[],boolean,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005002000_game_original_ui.sql
-- Compatibility data for the original screens. No legacy economic tables are written.
CREATE TABLE game.ui_lineups (
 tournament_id uuid NOT NULL, season_id uuid NOT NULL, club_id uuid NOT NULL,
 formation text NOT NULL, slots jsonb NOT NULL CHECK(jsonb_typeof(slots)='object'),
 PRIMARY KEY(season_id,club_id),
 FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
ALTER TABLE game.ui_lineups ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE ON game.ui_lineups TO service_role;

CREATE FUNCTION public.game_ui_snapshot(p_code text,p_token text,p_admin_token text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid; tid uuid; result jsonb;
BEGIN
 mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 result:=jsonb_build_object('state',public.game_state(p_code,p_token),'competition',public.game_competition_state(p_code,p_token),'market',public.game_market_state(p_code,p_token));
 RETURN result||jsonb_build_object(
 'meta',(SELECT jsonb_build_object('createdAt',t.created_at,'maxTransfers',t.max_transfers,'clauseProtection',t.clause_protection_limit,'slotsEnabled',t.slots_enabled,'isAdmin',coalesce(t.admin_token_hash=encode(sha256(convert_to(p_admin_token,'UTF8')),'hex'),false)) FROM public.tournaments t WHERE id=tid),
 'assets',coalesce((SELECT jsonb_agg(to_jsonb(p)||jsonb_build_object('headshot_url',catalog.headshot_url)) FROM game.players p LEFT JOIN public.players catalog ON catalog.id=p.player_id WHERE p.tournament_id=tid),'[]'),
 'clubs',coalesce((SELECT jsonb_agg(to_jsonb(c)) FROM game.clubs c WHERE c.tournament_id=tid),'[]'),
 'windows',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY opens_at DESC) FROM game.market_windows w WHERE w.tournament_id=tid),'[]'),
 'transfers',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY created_at DESC) FROM game.transfers t WHERE t.tournament_id=tid),'[]'),
 'assignments',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY started_at DESC) FROM game.assignments a WHERE a.tournament_id=tid),'[]'),
 'seasons',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY number DESC) FROM game.seasons s WHERE s.tournament_id=tid),'[]'),
 'draft',(SELECT to_jsonb(d) FROM game.ui_lineups d JOIN game.assignments a ON a.club_id=d.club_id AND a.season_id=d.season_id AND a.ended_at IS NULL WHERE a.member_id=mid AND d.tournament_id=tid),
 'votes',coalesce((SELECT jsonb_agg(to_jsonb(v)) FROM game.votes v JOIN game.assignments a ON a.club_id=v.club_id AND a.ended_at IS NULL WHERE v.tournament_id=tid AND a.member_id=mid),'[]')
 );
END $$;

CREATE FUNCTION public.game_ui_command(p_code text,p_token text,p_key uuid,p_action text,p_body jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; sid uuid; club uuid; k text; old game.operations; result jsonb:='{}'; players jsonb; row record; amount bigint;
BEGIN
 IF p_key IS NULL OR p_body IS NULL OR jsonb_typeof(p_body)<>'object' THEN RAISE EXCEPTION 'Invalid UI command'; END IF;
 IF p_action IN('market_open','remove_member','settings') THEN tid:=game.require_admin(p_code,p_token);
 ELSE mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 k:='ui:'||coalesce(mid::text,'admin')||':'||p_key;
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key=k;
 IF FOUND THEN IF old.payload<>jsonb_build_object('action',p_action,'body',p_body) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF; RETURN old.result; END IF;
 SELECT id INTO sid FROM game.seasons WHERE tournament_id=tid AND ended_at IS NULL;
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 IF p_action='save_lineup' THEN
  IF club IS NULL THEN PERFORM game.rule_error('Choose a club first'); END IF;
  IF p_body->>'formation' NOT IN('4-3-3','4-4-2','4-2-3-1','3-5-2','4-2-1-3','4-4-1-1','4-2-2-2','4-3-2-1','4-1-2-1-2','5-2-1-2','3-4-3','3-4-2-1','4-1-4-1','4-5-1') OR jsonb_typeof(p_body->'slots')<>'object' THEN RAISE EXCEPTION 'Invalid lineup'; END IF;
  SELECT coalesce(jsonb_agg(value),'[]') INTO players FROM jsonb_each(p_body->'slots') WHERE value<>'null';
  IF jsonb_array_length(players)>11 OR jsonb_array_length(players)<>(SELECT count(DISTINCT value) FROM jsonb_array_elements_text(players)) THEN RAISE EXCEPTION 'Invalid lineup'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(players) p WHERE NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=tid AND c.club_id=club AND c.player_id=p.value::uuid AND c.ended_at IS NULL)) THEN RAISE EXCEPTION 'Invalid lineup player'; END IF;
  INSERT INTO game.ui_lineups VALUES(tid,sid,club,p_body->>'formation',p_body->'slots') ON CONFLICT(season_id,club_id) DO UPDATE SET formation=excluded.formation,slots=excluded.slots;
 ELSIF p_action='confirm_lineup' THEN
  SELECT coalesce(jsonb_agg(p.value),'[]') INTO players FROM game.ui_lineups d CROSS JOIN LATERAL jsonb_each(d.slots) p WHERE d.season_id=sid AND d.club_id=club AND p.value<>'null';
  IF EXISTS(SELECT 1 FROM game.ui_lineups WHERE season_id=sid AND club_id=club) THEN result:=public.game_competition_command(p_code,p_token,p_key,'lineup',jsonb_build_object('fixtureId',p_body->>'fixtureId','players',players));
  ELSE result:=public.game_competition_command(p_code,p_token,p_key,'lineup',jsonb_build_object('fixtureId',p_body->>'fixtureId')); END IF;
 ELSIF p_action='market_open' THEN
  IF coalesce((p_body->>'resetBudgets')::boolean,false) THEN PERFORM game.rule_error('Club assets cannot be reset'); END IF;
  amount:=coalesce((p_body->>'budgetInjection')::bigint,0); IF amount NOT BETWEEN 0 AND 1000000000 THEN RAISE EXCEPTION 'Invalid budget injection'; END IF;
  UPDATE public.tournaments SET max_transfers=coalesce((p_body->>'maxTransfers')::integer,max_transfers),clause_protection_limit=coalesce((p_body->>'winterClauseProtection')::integer,(p_body->>'clauseProtection')::integer,clause_protection_limit) WHERE id=tid;
  UPDATE game.rules SET winter_limit=coalesce((p_body->>'winterMaxTransfers')::integer,winter_limit) WHERE tournament_id=tid;
  result:=public.game_market_command(p_code,p_token,p_key,'open',NULL,NULL,NULL,CASE WHEN p_body->>'marketType'='winter' THEN 'winter' ELSE 'summer' END,coalesce((p_body->>'durationHours')::integer,24)*60);
  IF amount>0 THEN FOR row IN SELECT id FROM game.clubs WHERE tournament_id=tid LOOP PERFORM game.cash(tid,row.id,amount,'season_income',k||':'||row.id,p_body); END LOOP; END IF;
 ELSIF p_action='remove_member' THEN
  IF EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid AND status='open') OR EXISTS(SELECT 1 FROM game.fixtures WHERE tournament_id=tid AND status='playing') THEN PERFORM game.rule_error('Close market and finish active matches first'); END IF;
  mid:=(p_body->>'memberId')::uuid;
  IF NOT EXISTS(SELECT 1 FROM public.members WHERE id=mid AND tournament_id=tid) THEN RAISE EXCEPTION 'Invalid member'; END IF;
  SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
  INSERT INTO game.departures(tournament_id,member_id) VALUES(tid,mid) ON CONFLICT DO NOTHING;
  UPDATE game.assignments SET ended_at=clock_timestamp() WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
  UPDATE game.entrants SET abandoned_at=clock_timestamp(),replacement_due=clock_timestamp()+make_interval(days=>(SELECT replacement_days FROM game.rules WHERE tournament_id=tid)) WHERE season_id=sid AND club_id=club;
 ELSIF p_action='settings' THEN
  UPDATE game.rules SET spin_fee=coalesce((p_body->>'slotMachinePrice')::bigint,spin_fee) WHERE tournament_id=tid;
  UPDATE public.tournaments SET slots_enabled=coalesce((p_body->>'slotsEnabled')::boolean,slots_enabled) WHERE id=tid;
 ELSE RAISE EXCEPTION 'Invalid UI action'; END IF;
 result:=result||'{"ok":true}'::jsonb;
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'ui_'||p_action,k,jsonb_build_object('action',p_action,'body',p_body),result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_ui_snapshot(text,text,text),public.game_ui_command(text,text,uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_ui_snapshot(text,text,text),public.game_ui_command(text,text,uuid,text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002000','game_original_ui',ARRAY[$mercatto_source$-- Compatibility data for the original screens. No legacy economic tables are written.
CREATE TABLE game.ui_lineups (
 tournament_id uuid NOT NULL, season_id uuid NOT NULL, club_id uuid NOT NULL,
 formation text NOT NULL, slots jsonb NOT NULL CHECK(jsonb_typeof(slots)='object'),
 PRIMARY KEY(season_id,club_id),
 FOREIGN KEY(tournament_id,season_id) REFERENCES game.seasons(tournament_id,id),
 FOREIGN KEY(tournament_id,club_id) REFERENCES game.clubs(tournament_id,id)
);
ALTER TABLE game.ui_lineups ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT,UPDATE ON game.ui_lineups TO service_role;

CREATE FUNCTION public.game_ui_snapshot(p_code text,p_token text,p_admin_token text DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid; tid uuid; result jsonb;
BEGIN
 mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 result:=jsonb_build_object('state',public.game_state(p_code,p_token),'competition',public.game_competition_state(p_code,p_token),'market',public.game_market_state(p_code,p_token));
 RETURN result||jsonb_build_object(
 'meta',(SELECT jsonb_build_object('createdAt',t.created_at,'maxTransfers',t.max_transfers,'clauseProtection',t.clause_protection_limit,'slotsEnabled',t.slots_enabled,'isAdmin',coalesce(t.admin_token_hash=encode(sha256(convert_to(p_admin_token,'UTF8')),'hex'),false)) FROM public.tournaments t WHERE id=tid),
 'assets',coalesce((SELECT jsonb_agg(to_jsonb(p)||jsonb_build_object('headshot_url',catalog.headshot_url)) FROM game.players p LEFT JOIN public.players catalog ON catalog.id=p.player_id WHERE p.tournament_id=tid),'[]'),
 'clubs',coalesce((SELECT jsonb_agg(to_jsonb(c)) FROM game.clubs c WHERE c.tournament_id=tid),'[]'),
 'windows',coalesce((SELECT jsonb_agg(to_jsonb(w) ORDER BY opens_at DESC) FROM game.market_windows w WHERE w.tournament_id=tid),'[]'),
 'transfers',coalesce((SELECT jsonb_agg(to_jsonb(t) ORDER BY created_at DESC) FROM game.transfers t WHERE t.tournament_id=tid),'[]'),
 'assignments',coalesce((SELECT jsonb_agg(to_jsonb(a) ORDER BY started_at DESC) FROM game.assignments a WHERE a.tournament_id=tid),'[]'),
 'seasons',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY number DESC) FROM game.seasons s WHERE s.tournament_id=tid),'[]'),
 'draft',(SELECT to_jsonb(d) FROM game.ui_lineups d JOIN game.assignments a ON a.club_id=d.club_id AND a.season_id=d.season_id AND a.ended_at IS NULL WHERE a.member_id=mid AND d.tournament_id=tid),
 'votes',coalesce((SELECT jsonb_agg(to_jsonb(v)) FROM game.votes v JOIN game.assignments a ON a.club_id=v.club_id AND a.ended_at IS NULL WHERE v.tournament_id=tid AND a.member_id=mid),'[]')
 );
END $$;

CREATE FUNCTION public.game_ui_command(p_code text,p_token text,p_key uuid,p_action text,p_body jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; sid uuid; club uuid; k text; old game.operations; result jsonb:='{}'; players jsonb; row record; amount bigint;
BEGIN
 IF p_key IS NULL OR p_body IS NULL OR jsonb_typeof(p_body)<>'object' THEN RAISE EXCEPTION 'Invalid UI command'; END IF;
 IF p_action IN('market_open','remove_member','settings') THEN tid:=game.require_admin(p_code,p_token);
 ELSE mid:=game.require_member(p_code,p_token); SELECT tournament_id INTO tid FROM public.members WHERE id=mid; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 k:='ui:'||coalesce(mid::text,'admin')||':'||p_key;
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key=k;
 IF FOUND THEN IF old.payload<>jsonb_build_object('action',p_action,'body',p_body) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF; RETURN old.result; END IF;
 SELECT id INTO sid FROM game.seasons WHERE tournament_id=tid AND ended_at IS NULL;
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 IF p_action='save_lineup' THEN
  IF club IS NULL THEN PERFORM game.rule_error('Choose a club first'); END IF;
  IF p_body->>'formation' NOT IN('4-3-3','4-4-2','4-2-3-1','3-5-2','4-2-1-3','4-4-1-1','4-2-2-2','4-3-2-1','4-1-2-1-2','5-2-1-2','3-4-3','3-4-2-1','4-1-4-1','4-5-1') OR jsonb_typeof(p_body->'slots')<>'object' THEN RAISE EXCEPTION 'Invalid lineup'; END IF;
  SELECT coalesce(jsonb_agg(value),'[]') INTO players FROM jsonb_each(p_body->'slots') WHERE value<>'null';
  IF jsonb_array_length(players)>11 OR jsonb_array_length(players)<>(SELECT count(DISTINCT value) FROM jsonb_array_elements_text(players)) THEN RAISE EXCEPTION 'Invalid lineup'; END IF;
  IF EXISTS(SELECT 1 FROM jsonb_array_elements_text(players) p WHERE NOT EXISTS(SELECT 1 FROM game.contracts c WHERE c.tournament_id=tid AND c.club_id=club AND c.player_id=p.value::uuid AND c.ended_at IS NULL)) THEN RAISE EXCEPTION 'Invalid lineup player'; END IF;
  INSERT INTO game.ui_lineups VALUES(tid,sid,club,p_body->>'formation',p_body->'slots') ON CONFLICT(season_id,club_id) DO UPDATE SET formation=excluded.formation,slots=excluded.slots;
 ELSIF p_action='confirm_lineup' THEN
  SELECT coalesce(jsonb_agg(p.value),'[]') INTO players FROM game.ui_lineups d CROSS JOIN LATERAL jsonb_each(d.slots) p WHERE d.season_id=sid AND d.club_id=club AND p.value<>'null';
  IF EXISTS(SELECT 1 FROM game.ui_lineups WHERE season_id=sid AND club_id=club) THEN result:=public.game_competition_command(p_code,p_token,p_key,'lineup',jsonb_build_object('fixtureId',p_body->>'fixtureId','players',players));
  ELSE result:=public.game_competition_command(p_code,p_token,p_key,'lineup',jsonb_build_object('fixtureId',p_body->>'fixtureId')); END IF;
 ELSIF p_action='market_open' THEN
  IF coalesce((p_body->>'resetBudgets')::boolean,false) THEN PERFORM game.rule_error('Club assets cannot be reset'); END IF;
  amount:=coalesce((p_body->>'budgetInjection')::bigint,0); IF amount NOT BETWEEN 0 AND 1000000000 THEN RAISE EXCEPTION 'Invalid budget injection'; END IF;
  UPDATE public.tournaments SET max_transfers=coalesce((p_body->>'maxTransfers')::integer,max_transfers),clause_protection_limit=coalesce((p_body->>'winterClauseProtection')::integer,(p_body->>'clauseProtection')::integer,clause_protection_limit) WHERE id=tid;
  UPDATE game.rules SET winter_limit=coalesce((p_body->>'winterMaxTransfers')::integer,winter_limit) WHERE tournament_id=tid;
  result:=public.game_market_command(p_code,p_token,p_key,'open',NULL,NULL,NULL,CASE WHEN p_body->>'marketType'='winter' THEN 'winter' ELSE 'summer' END,coalesce((p_body->>'durationHours')::integer,24)*60);
  IF amount>0 THEN FOR row IN SELECT id FROM game.clubs WHERE tournament_id=tid LOOP PERFORM game.cash(tid,row.id,amount,'season_income',k||':'||row.id,p_body); END LOOP; END IF;
 ELSIF p_action='remove_member' THEN
  IF EXISTS(SELECT 1 FROM game.market_windows WHERE tournament_id=tid AND status='open') OR EXISTS(SELECT 1 FROM game.fixtures WHERE tournament_id=tid AND status='playing') THEN PERFORM game.rule_error('Close market and finish active matches first'); END IF;
  mid:=(p_body->>'memberId')::uuid;
  IF NOT EXISTS(SELECT 1 FROM public.members WHERE id=mid AND tournament_id=tid) THEN RAISE EXCEPTION 'Invalid member'; END IF;
  SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
  INSERT INTO game.departures(tournament_id,member_id) VALUES(tid,mid) ON CONFLICT DO NOTHING;
  UPDATE game.assignments SET ended_at=clock_timestamp() WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
  UPDATE game.entrants SET abandoned_at=clock_timestamp(),replacement_due=clock_timestamp()+make_interval(days=>(SELECT replacement_days FROM game.rules WHERE tournament_id=tid)) WHERE season_id=sid AND club_id=club;
 ELSIF p_action='settings' THEN
  UPDATE game.rules SET spin_fee=coalesce((p_body->>'slotMachinePrice')::bigint,spin_fee) WHERE tournament_id=tid;
  UPDATE public.tournaments SET slots_enabled=coalesce((p_body->>'slotsEnabled')::boolean,slots_enabled) WHERE id=tid;
 ELSE RAISE EXCEPTION 'Invalid UI action'; END IF;
 result:=result||'{"ok":true}'::jsonb;
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'ui_'||p_action,k,jsonb_build_object('action',p_action,'body',p_body),result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_ui_snapshot(text,text,text),public.game_ui_command(text,text,uuid,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_ui_snapshot(text,text,text),public.game_ui_command(text,text,uuid,text,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005002100_game_ui_settings.sql
-- Local baseline lacked the original slots visibility preference.
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS slots_enabled boolean NOT NULL DEFAULT false;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002100','game_ui_settings',ARRAY[$mercatto_source$-- Local baseline lacked the original slots visibility preference.
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS slots_enabled boolean NOT NULL DEFAULT false;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005002200_game_admin_auction_close.sql
-- Preserve the original administrator's End Auction action, with audited settlement.
CREATE OR REPLACE FUNCTION game.settle_auction(p_auction uuid,p_reason text DEFAULT 'deadline') RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a game.auctions;w game.market_windows;v_op uuid:=gen_random_uuid();v_result jsonb;v_account uuid;v_clearing uuid;v_now timestamptz;
BEGIN
  SELECT * INTO a FROM game.auctions WHERE id=p_auction;
  IF NOT FOUND THEN RAISE EXCEPTION 'Auction not found' USING ERRCODE='GM001'; END IF;
  PERFORM 1 FROM game.tournaments WHERE id=a.tournament_id FOR UPDATE;
  SELECT * INTO a FROM game.auctions WHERE id=p_auction FOR UPDATE;
  IF a.status<>'active' THEN SELECT result INTO v_result FROM game.operations WHERE tournament_id=a.tournament_id AND idempotency_key='auction-settle:'||a.id; RETURN v_result; END IF;
  v_now:=clock_timestamp();SELECT * INTO w FROM game.market_windows WHERE id=a.window_id FOR UPDATE;
  IF p_reason IS NULL OR p_reason NOT IN('deadline','market_close','admin_close') THEN RAISE EXCEPTION 'Invalid settlement reason'; END IF;
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


CREATE FUNCTION public.game_ui_end_auction(p_code text,p_token text,p_key uuid,p_auction uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; previous game.operations; k text; result jsonb;
BEGIN
 tid:=game.require_admin(p_code,p_token);
 IF p_key IS NULL OR p_auction IS NULL THEN RAISE EXCEPTION 'Invalid auction closure'; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 k:='ui-auction-end:'||p_key;
 SELECT * INTO previous FROM game.operations WHERE tournament_id=tid AND idempotency_key=k;
 IF FOUND THEN
  IF previous.payload<>jsonb_build_object('auctionId',p_auction) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
  RETURN previous.result;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM game.auctions WHERE tournament_id=tid AND id=p_auction) THEN RAISE EXCEPTION 'Auction not found' USING ERRCODE='GM001'; END IF;
 result:=game.settle_auction(p_auction,'admin_close');
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'ui_auction_end',k,jsonb_build_object('auctionId',p_auction),result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_ui_end_auction(text,text,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_ui_end_auction(text,text,uuid,uuid) TO service_role;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002200','game_admin_auction_close',ARRAY[$mercatto_source$-- Preserve the original administrator's End Auction action, with audited settlement.
CREATE OR REPLACE FUNCTION game.settle_auction(p_auction uuid,p_reason text DEFAULT 'deadline') RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE a game.auctions;w game.market_windows;v_op uuid:=gen_random_uuid();v_result jsonb;v_account uuid;v_clearing uuid;v_now timestamptz;
BEGIN
  SELECT * INTO a FROM game.auctions WHERE id=p_auction;
  IF NOT FOUND THEN RAISE EXCEPTION 'Auction not found' USING ERRCODE='GM001'; END IF;
  PERFORM 1 FROM game.tournaments WHERE id=a.tournament_id FOR UPDATE;
  SELECT * INTO a FROM game.auctions WHERE id=p_auction FOR UPDATE;
  IF a.status<>'active' THEN SELECT result INTO v_result FROM game.operations WHERE tournament_id=a.tournament_id AND idempotency_key='auction-settle:'||a.id; RETURN v_result; END IF;
  v_now:=clock_timestamp();SELECT * INTO w FROM game.market_windows WHERE id=a.window_id FOR UPDATE;
  IF p_reason IS NULL OR p_reason NOT IN('deadline','market_close','admin_close') THEN RAISE EXCEPTION 'Invalid settlement reason'; END IF;
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


CREATE FUNCTION public.game_ui_end_auction(p_code text,p_token text,p_key uuid,p_auction uuid) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; previous game.operations; k text; result jsonb;
BEGIN
 tid:=game.require_admin(p_code,p_token);
 IF p_key IS NULL OR p_auction IS NULL THEN RAISE EXCEPTION 'Invalid auction closure'; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 k:='ui-auction-end:'||p_key;
 SELECT * INTO previous FROM game.operations WHERE tournament_id=tid AND idempotency_key=k;
 IF FOUND THEN
  IF previous.payload<>jsonb_build_object('auctionId',p_auction) THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
  RETURN previous.result;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM game.auctions WHERE tournament_id=tid AND id=p_auction) THEN RAISE EXCEPTION 'Auction not found' USING ERRCODE='GM001'; END IF;
 result:=game.settle_auction(p_auction,'admin_close');
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'ui_auction_end',k,jsonb_build_object('auctionId',p_auction),result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_ui_end_auction(text,text,uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_ui_end_auction(text,text,uuid,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005002300_game_ui_result_cards.sql
-- The original confirmation form lets each manager declare their own cards.
CREATE FUNCTION public.game_ui_confirm_result(p_code text,p_token text,p_key uuid,p_fixture uuid,p_cards jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; club uuid; f game.fixtures; old game.operations; k text; payload jsonb; cards jsonb; result jsonb;
BEGIN
 mid:=game.require_member(p_code,p_token);
 SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 IF p_key IS NULL OR p_fixture IS NULL OR p_cards IS NULL OR jsonb_typeof(p_cards)<>'array' THEN RAISE EXCEPTION 'Invalid result confirmation'; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 k:='ui-result-confirm:'||mid||':'||p_key;
 payload:=jsonb_build_object('fixtureId',p_fixture,'cards',p_cards);
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key=k;
 IF FOUND THEN
  IF old.payload<>payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
  RETURN old.result;
 END IF;
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 SELECT * INTO f FROM game.fixtures WHERE tournament_id=tid AND id=p_fixture FOR UPDATE;
 IF f.id IS NULL OR club IS NULL OR club NOT IN(f.home_club_id,f.away_club_id) THEN RAISE EXCEPTION 'Fixture not found' USING ERRCODE='GM001'; END IF;
 IF f.proposal IS NULL OR f.proposer_club_id=club THEN PERFORM game.rule_error('Other club must confirm result'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_cards) c WHERE c->>'kind' NOT IN('yellow','red') OR NOT EXISTS(SELECT 1 FROM game.lineups l WHERE l.fixture_id=f.id AND l.player_id=(c->>'playerId')::uuid AND l.selected)) THEN RAISE EXCEPTION 'Invalid cards'; END IF;
 -- Preserve the rival's declared cards; only replace this manager's own cards.
 SELECT coalesce(jsonb_agg(c),'[]') INTO cards FROM jsonb_array_elements(f.proposal->'cards') c WHERE EXISTS(SELECT 1 FROM game.lineups l WHERE l.fixture_id=f.id AND l.player_id=(c->>'playerId')::uuid AND l.club_id<>club);
 SELECT cards||coalesce(jsonb_agg(c),'[]') INTO cards FROM jsonb_array_elements(p_cards) c WHERE EXISTS(SELECT 1 FROM game.lineups l WHERE l.fixture_id=f.id AND l.player_id=(c->>'playerId')::uuid AND l.club_id=club);
 UPDATE game.fixtures SET proposal=jsonb_set(proposal,'{cards}',cards) WHERE id=f.id;
 result:=public.game_competition_command(p_code,p_token,p_key,'result_confirm',jsonb_build_object('fixtureId',p_fixture));
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'ui_result_confirm',k,payload,result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_ui_confirm_result(text,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_ui_confirm_result(text,text,uuid,uuid,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002300','game_ui_result_cards',ARRAY[$mercatto_source$-- The original confirmation form lets each manager declare their own cards.
CREATE FUNCTION public.game_ui_confirm_result(p_code text,p_token text,p_key uuid,p_fixture uuid,p_cards jsonb) RETURNS jsonb
LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; club uuid; f game.fixtures; old game.operations; k text; payload jsonb; cards jsonb; result jsonb;
BEGIN
 mid:=game.require_member(p_code,p_token);
 SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 IF p_key IS NULL OR p_fixture IS NULL OR p_cards IS NULL OR jsonb_typeof(p_cards)<>'array' THEN RAISE EXCEPTION 'Invalid result confirmation'; END IF;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 k:='ui-result-confirm:'||mid||':'||p_key;
 payload:=jsonb_build_object('fixtureId',p_fixture,'cards',p_cards);
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key=k;
 IF FOUND THEN
  IF old.payload<>payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF;
  RETURN old.result;
 END IF;
 SELECT club_id INTO club FROM game.assignments WHERE tournament_id=tid AND member_id=mid AND ended_at IS NULL;
 SELECT * INTO f FROM game.fixtures WHERE tournament_id=tid AND id=p_fixture FOR UPDATE;
 IF f.id IS NULL OR club IS NULL OR club NOT IN(f.home_club_id,f.away_club_id) THEN RAISE EXCEPTION 'Fixture not found' USING ERRCODE='GM001'; END IF;
 IF f.proposal IS NULL OR f.proposer_club_id=club THEN PERFORM game.rule_error('Other club must confirm result'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_cards) c WHERE c->>'kind' NOT IN('yellow','red') OR NOT EXISTS(SELECT 1 FROM game.lineups l WHERE l.fixture_id=f.id AND l.player_id=(c->>'playerId')::uuid AND l.selected)) THEN RAISE EXCEPTION 'Invalid cards'; END IF;
 -- Preserve the rival's declared cards; only replace this manager's own cards.
 SELECT coalesce(jsonb_agg(c),'[]') INTO cards FROM jsonb_array_elements(f.proposal->'cards') c WHERE EXISTS(SELECT 1 FROM game.lineups l WHERE l.fixture_id=f.id AND l.player_id=(c->>'playerId')::uuid AND l.club_id<>club);
 SELECT cards||coalesce(jsonb_agg(c),'[]') INTO cards FROM jsonb_array_elements(p_cards) c WHERE EXISTS(SELECT 1 FROM game.lineups l WHERE l.fixture_id=f.id AND l.player_id=(c->>'playerId')::uuid AND l.club_id=club);
 UPDATE game.fixtures SET proposal=jsonb_set(proposal,'{cards}',cards) WHERE id=f.id;
 result:=public.game_competition_command(p_code,p_token,p_key,'result_confirm',jsonb_build_object('fixtureId',p_fixture));
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'ui_result_confirm',k,payload,result);
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION public.game_ui_confirm_result(text,text,uuid,uuid,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_ui_confirm_result(text,text,uuid,uuid,jsonb) TO service_role;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005002400_game_postponements.sql
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

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002400','game_postponements',ARRAY[$mercatto_source$-- Postponements are scoped to unfinished fixtures; completed history is untouched.
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
$mercatto_source$]);

-- Migration 20261005002500_game_postponement_lineup_permissions.sql
-- Only this authenticated, tournament-scoped RPC may clear unfinished lineups.
-- Do not grant general DELETE privileges on frozen lineups to service_role.
ALTER FUNCTION public.game_fixture_schedule(text,text,uuid,uuid,text,boolean,boolean) SECURITY DEFINER;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002500','game_postponement_lineup_permissions',ARRAY[$mercatto_source$-- Only this authenticated, tournament-scoped RPC may clear unfinished lineups.
-- Do not grant general DELETE privileges on frozen lineups to service_role.
ALTER FUNCTION public.game_fixture_schedule(text,text,uuid,uuid,text,boolean,boolean) SECURITY DEFINER;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005002600_game_postponed_lineup_archive.sql
-- Keep every frozen selection when a match is postponed and needs a new XI.
CREATE TABLE game.postponed_lineup_archive (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tournament_id uuid NOT NULL,
 fixture_id uuid NOT NULL, source_table text NOT NULL CHECK(source_table IN('lineups','lineup_confirmations')),
 snapshot jsonb NOT NULL, archived_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(tournament_id,fixture_id) REFERENCES game.fixtures(tournament_id,id)
);
ALTER TABLE game.postponed_lineup_archive ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.postponed_lineup_archive FROM PUBLIC,anon,authenticated;
GRANT SELECT ON game.postponed_lineup_archive TO service_role;
CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON game.postponed_lineup_archive FOR EACH ROW EXECUTE FUNCTION game.immutable_history();
CREATE FUNCTION game.archive_postponed_lineup() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP<>'DELETE' OR NOT EXISTS(SELECT 1 FROM game.fixtures WHERE id=OLD.fixture_id AND tournament_id=OLD.tournament_id AND status='postponed') THEN
  RAISE EXCEPTION 'Frozen lineup history is immutable';
 END IF;
 INSERT INTO game.postponed_lineup_archive(tournament_id,fixture_id,source_table,snapshot) VALUES(OLD.tournament_id,OLD.fixture_id,TG_TABLE_NAME,to_jsonb(OLD));
 RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION game.archive_postponed_lineup() FROM PUBLIC,anon,authenticated;
DROP TRIGGER immutable_history ON game.lineups;
DROP TRIGGER immutable_history ON game.lineup_confirmations;
CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON game.lineups FOR EACH ROW EXECUTE FUNCTION game.archive_postponed_lineup();
CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON game.lineup_confirmations FOR EACH ROW EXECUTE FUNCTION game.archive_postponed_lineup();
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002600','game_postponed_lineup_archive',ARRAY[$mercatto_source$-- Keep every frozen selection when a match is postponed and needs a new XI.
CREATE TABLE game.postponed_lineup_archive (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tournament_id uuid NOT NULL,
 fixture_id uuid NOT NULL, source_table text NOT NULL CHECK(source_table IN('lineups','lineup_confirmations')),
 snapshot jsonb NOT NULL, archived_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(tournament_id,fixture_id) REFERENCES game.fixtures(tournament_id,id)
);
ALTER TABLE game.postponed_lineup_archive ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.postponed_lineup_archive FROM PUBLIC,anon,authenticated;
GRANT SELECT ON game.postponed_lineup_archive TO service_role;
CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON game.postponed_lineup_archive FOR EACH ROW EXECUTE FUNCTION game.immutable_history();
CREATE FUNCTION game.archive_postponed_lineup() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF TG_OP<>'DELETE' OR NOT EXISTS(SELECT 1 FROM game.fixtures WHERE id=OLD.fixture_id AND tournament_id=OLD.tournament_id AND status='postponed') THEN
  RAISE EXCEPTION 'Frozen lineup history is immutable';
 END IF;
 INSERT INTO game.postponed_lineup_archive(tournament_id,fixture_id,source_table,snapshot) VALUES(OLD.tournament_id,OLD.fixture_id,TG_TABLE_NAME,to_jsonb(OLD));
 RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION game.archive_postponed_lineup() FROM PUBLIC,anon,authenticated;
DROP TRIGGER immutable_history ON game.lineups;
DROP TRIGGER immutable_history ON game.lineup_confirmations;
CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON game.lineups FOR EACH ROW EXECUTE FUNCTION game.archive_postponed_lineup();
CREATE TRIGGER immutable_history BEFORE UPDATE OR DELETE ON game.lineup_confirmations FOR EACH ROW EXECUTE FUNCTION game.archive_postponed_lineup();
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005002700_sofifa_catalog_identity.sql
-- Stable external identity replaces name/rating/position as the import key.
ALTER TABLE public.players ADD COLUMN sofifa_id bigint UNIQUE CHECK(sofifa_id>0),
 ADD COLUMN sofifa_revision integer, ADD COLUMN sofifa_updated_at timestamptz;
ALTER TABLE public.teams ADD COLUMN sofifa_id bigint UNIQUE CHECK(sofifa_id>0),
 ADD COLUMN sofifa_revision integer, ADD COLUMN sofifa_updated_at timestamptz;
ALTER TABLE public.players DROP CONSTRAINT players_name_ovr_position_unique;
CREATE TABLE public.sofifa_imports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), revision integer NOT NULL,
 digest text NOT NULL UNIQUE, imported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 team_count integer NOT NULL, player_count integer NOT NULL
);
ALTER TABLE public.sofifa_imports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sofifa_imports FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.sofifa_imports TO service_role;
NOTIFY pgrst,'reload schema';

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002700','sofifa_catalog_identity',ARRAY[$mercatto_source$-- Stable external identity replaces name/rating/position as the import key.
ALTER TABLE public.players ADD COLUMN sofifa_id bigint UNIQUE CHECK(sofifa_id>0),
 ADD COLUMN sofifa_revision integer, ADD COLUMN sofifa_updated_at timestamptz;
ALTER TABLE public.teams ADD COLUMN sofifa_id bigint UNIQUE CHECK(sofifa_id>0),
 ADD COLUMN sofifa_revision integer, ADD COLUMN sofifa_updated_at timestamptz;
ALTER TABLE public.players DROP CONSTRAINT players_name_ovr_position_unique;
CREATE TABLE public.sofifa_imports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), revision integer NOT NULL,
 digest text NOT NULL UNIQUE, imported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 team_count integer NOT NULL, player_count integer NOT NULL
);
ALTER TABLE public.sofifa_imports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sofifa_imports FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.sofifa_imports TO service_role;
NOTIFY pgrst,'reload schema';
$mercatto_source$]);

-- Migration 20261005002800_catalog_single_owner.sql
-- Catalogue membership is a single current club, independently of game contracts.
-- Intentionally fails on an unreconciled old catalogue instead of deleting duplicates.
CREATE UNIQUE INDEX team_players_single_owner ON public.team_players(player_id);

INSERT INTO supabase_migrations.schema_migrations(version,name,statements) VALUES('20261005002800','catalog_single_owner',ARRAY[$mercatto_source$-- Catalogue membership is a single current club, independently of game contracts.
-- Intentionally fails on an unreconciled old catalogue instead of deleting duplicates.
CREATE UNIQUE INDEX team_players_single_owner ON public.team_players(player_id);
$mercatto_source$]);

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(1,'Arsenal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/1/f9dad5aa49f659e93068d248a09e62365cf8e8927f470bfa0848209e804f15a3.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(220901,'David Raya Martín',88,'GK','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/220901/b07e936fcf344986c41660a7c2d6d35648080d030b9484023727c657f9097409.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=220901;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231936,'Benjamin White',81,'RB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231936/b9cadf8f56143a1c65cd7e4d2281d38bb663bc58d8a594871b060d9250453b34.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=231936;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(264846,'Cristhian Mosquera Ibargüen',78,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/264846/e96ac2039d5a19a3106ff408052ae9ee5be6f3128095a95f9539f6f89d70ec3a.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=264846;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(232580,'Gabriel dos S. Magalhães',89,'CB','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/232580/2b0077a4df03b0ca7ddc2d57127cd8361528e4b5071fc29534f6b0440d599a17.png',85000000,127500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=232580;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(257711,'Riccardo Calafiori',82,'LB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/257711/dc1329b8ed447ed6ce0626a3227ae0ed6e85e21c811abd34eafc4f2d1a6b96ab.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=257711;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(247851,'Bruno Guimarães Moura',86,'CM','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/247851/9578ab7d9225b349f2051564a6a4a0ad94e248428c45e8a9f7578920d39df6fa.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=247851;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(234378,'Declan Rice',88,'CDM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/234378/0414234dfb9476e00a3179437e0e070aa0395972184504807da912b15c4a8f79.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=234378;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(246669,'Bukayo Saka',87,'RW','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/246669/a672633345b8b6a630d670e653ab7c51feb5e5eede25223b0c9546fcd8e3cbcd.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=246669;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256948,'Christos Tzolis',82,'LW','Greece','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256948/91f3ae576aa7f9b9a3a193c54aabb46a7b9ccba322c3f75157d3c1464600bb28.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=256948;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(222665,'Martin Ødegaard',86,'CM','Norway','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/222665/b0b9f76e4b5c9c433c83eb84deb7f028b6a9e9692f99914b729042c2a3ae999e.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=222665;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(235790,'Kai Havertz',81,'ST','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/235790/d3a5fd01e42a5b3c978e0fe4ce34cb7cf70f8b47c28b654958664e7a5d2fdbad.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=235790;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(235794,'Eberechi Eze',84,'CAM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/235794/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=235794;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(248148,'Martín Zubimendi Ibáñez',84,'CDM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/248148/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=248148;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(225193,'Mikel Merino Zazón',83,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/225193/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=225193;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(227678,'Ezri Konsa',84,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/227678/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=227678;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256197,'Piero Hincapié',84,'LB','Ecuador','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256197/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=256197;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278773,'Myles Lewis-Skelly',78,'LB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278773/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=278773;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(206585,'Kepa Arrizabalaga',78,'GK','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/206585/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=206585;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(254796,'Noni Madueke',80,'RW','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/254796/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=254796;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241651,'Viktor Gyökeres',86,'ST','Sweden','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241651/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=241651;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(251805,'Jurriën Timber',84,'RB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/251805/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=251805;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(242656,'Illan Meslier',71,'GK','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/242656/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=242656;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243715,'William Saliba',88,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243715/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=1 AND p.sofifa_id=243715;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(5,'Chelsea','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/5/4435eab32c52a62841304317d43663f2e8b3378ff4e1ad310474dd9be1640ba9.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(202811,'Emiliano Martínez',85,'GK','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/202811/aca3a50b75cc7dadb9fb499054abf599e7372236902704a90811ddebfc95cf10.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=202811;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(248695,'Wesley Fofana',79,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/248695/e25d60a8eeb9bbff1b5b0c937a49d13cc56cf984a88d561792ddbda7c6749de7.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=248695;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(244067,'Maxence Lacroix',82,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/244067/1e1f9a6b7fb6ffd1b93b690cf6bab33549ae099686022459bb80f76c05ee3035.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=244067;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(262859,'Levi Colwill',80,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/262859/2f4185af1a8f39244b10a1da4a7ae31c0efe837e86de6854afcb59bc499ded2f.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=262859;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(238616,'Pedro Lomba Neto',81,'RM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/238616/b7c4a7ef79a8e2acd7a5205e1f3b5e9d5f51eb5de224d21742b8ebb064da11ad.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=238616;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(238074,'Reece James',84,'RB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/238074/10fcd2404023714819c1ae289dfa6381a5030a719a37ff3f3a6de0b23b03cddc.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=238074;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256079,'Moisés Caicedo',86,'CDM','Ecuador','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256079/5a53c3df6e9771a75bd5857d6de71f33a5cf107e552613a3fffa9c5cf4e6176c.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=256079;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(272978,'Jorrel Hato',78,'LB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/272978/acd5f8b35de8f16947d0a656bb34aef4beaef4d497122016e50557d91b40253b.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=272978;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(257534,'Cole Palmer',85,'CAM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/257534/4e9625559738fd9bbd38af6d0de53a6210c756cbecf7ce4a60c43d19017c85ed.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=257534;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(260247,'Morgan Rogers',84,'CAM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/260247/bc75b93c1a0370d4008e1698dea7f8d72fe28f3ae38264f72e795fb2a2476ab8.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=260247;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(252042,'João Pedro Junqueira de Jesus',83,'ST','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/252042/0d84eafaff9054c1626cbad09b357c67cf71a78cddea1cca4870b77aca32e9a3.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=252042;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(263370,'Valentín Barco',79,'CM','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/263370/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=263370;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(263620,'Roméo Lavia',78,'CDM','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/263620/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=263620;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(279044,'Geovany Tcherno Quenda',76,'RM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/279044/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=279044;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(258371,'Josep María Chavarría Pérez',79,'LB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/258371/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=258371;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259307,'Malo Gusto',79,'RB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259307/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=259307;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(71651,'Josh Acheampong',75,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/71651/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=71651;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(270821,'Mike Penders',78,'GK','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/270821/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=270821;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(76687,'Estêvão Willian Almeida',80,'RM','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/76687/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=76687;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(186146,'Danny Welbeck',80,'ST','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/186146/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=186146;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(266032,'Jamie Gittens',77,'LM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/266032/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=266032;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(183711,'Jordan Henderson',78,'CDM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/183711/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=183711;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(258437,'Emanuel Emegha',78,'ST','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/258437/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=258437;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278339,'Marco Palestra',78,'RB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278339/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=278339;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278455,'Aarón Anselmino',72,'CB','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278455/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=278455;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(248158,'Gabriel Slonina',68,'GK','United States','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/248158/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=248158;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(257126,'Teddy Sharman-Lowe',64,'GK','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/257126/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=257126;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(88586,'Olutayo Subuloye',62,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/88586/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=88586;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(274559,'Kendry Páez',74,'CAM','Ecuador','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/274559/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=5 AND p.sofifa_id=274559;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(9,'Liverpool','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/9/cf584dc7781e2bef2f8d1bbc0d3369be2e0c1f3bfc972c0e13ef90c395297ef6.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(212831,'Alisson Ramses Becker',87,'GK','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/212831/ab76a06ec3ef32995c951571062c736367dc33da481f8d867fed69c26123a079.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=212831;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(253163,'Ronald Araujo',80,'CB','Uruguay','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/253163/1c2de86d68ff53cb1bf3c4432091c23d54c5307a726cbd0abd5d8e45ca3dbf7e.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=253163;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278903,'Jérémy Jacquet',78,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278903/8147a825db4f03fedd50d516d3371688d299ad728730cd6182340b579923f012.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=278903;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(203376,'Virgil van Dijk',88,'CB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/203376/6bd888eb51e5eb09a939e657f3048c51b13e5faf78700cf5cd4ad67f2a714fe8.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=203376;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(260908,'Milos Kerkez',81,'LB','Hungary','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/260908/10e4b4ce4fc47b3d27697513c8cfcfcf0b360565c64c3300de2b52f24933274f.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=260908;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(236772,'Dominik Szoboszlai',86,'CAM','Hungary','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/236772/cb40b5c53c269a89286d9a09587ff6186666f084975503c058add53d56b427d0.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=236772;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(246104,'Ryan Gravenberch',85,'CDM','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/246104/14a63563d835e510189c894f6aa38f2d458a0c286163c73b2566bc1cc55b594d.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=246104;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(76042,'Víctor Muñoz Villanueva',79,'LM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/76042/87aaf78df046cadc26dfb78866734e5fa23aa70e05327597e10d1f92ee53c9e4.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=76042;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(242516,'Cody Gakpo',82,'LM','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/242516/ff39429a3fb2d6d58eae9d6fcfbfa2329d44a49b8cc31b14fc907b330055610f.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=242516;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256630,'Florian Wirtz',86,'CAM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256630/87ba5b1082a99be89ad4ada380bfc88a95d7d868178d593a61b8c0d6e51b6640.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=256630;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(233731,'Alexander Isak',86,'ST','Sweden','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/233731/630a7bc240402a1e1c8b81db635078eda2c506cc50175bdf72c2f5306d0e07b0.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=233731;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239837,'Alexis Mac Allister',84,'CM','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239837/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=239837;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(232487,'Wataru Endo',78,'CDM','Japan','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/232487/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=232487;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(70994,'Lewis Koumas',70,'LM','Wales','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/70994/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=70994;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(279128,'Trey Nyoni',69,'CM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/279128/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=279128;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(253149,'Jeremie Frimpong',81,'RB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/253149/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=253149;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(232223,'Kostas Tsimikas',76,'LB','Greece','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/232223/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=232223;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(262621,'Giorgi Mamardashvili',83,'GK','Georgia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/262621/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=262621;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(80376,'Rio Ngumoha',75,'LM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/80376/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=80376;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(264652,'Bradley Barcola',85,'LW','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/264652/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=264652;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(225100,'Joe Gomez',79,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/225100/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=225100;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(235805,'Federico Chiesa',80,'RM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/235805/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=235805;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278292,'James McConnell',68,'CDM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278292/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=278292;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(253428,'Vítězslav Jaroš',72,'GK','Czechia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/253428/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=253428;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(70824,'Giovanni Leoni',71,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/70824/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=70824;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(222514,'Freddie Woodman',71,'GK','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/222514/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=222514;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(271977,'Harvey Davies',61,'GK','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/271977/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=271977;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(257289,'Hugo Ekitiké',85,'ST','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/257289/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=257289;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(264298,'Conor Bradley',79,'RB','Northern Ireland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/264298/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=9 AND p.sofifa_id=264298;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(10,'Manchester City','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/10/8fa5671b0e46a1d8b8f03f56c9a38579658886cec47565134cc96dd3e12898e2.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(230621,'Gianluigi Donnarumma',89,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/230621/e9b2b153e382c2325463a835a0ef142c5e792755a6402aad04296e9567cc5bc2.png',85000000,127500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=230621;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(253124,'Matheus Luiz Nunes',83,'RB','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/253124/02d8518019494e56a72b87fcb0732fcf425e56c3b731b9a95e27e98654f908d2.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=253124;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239818,'Rúben Santos Gato Alves Dias',87,'CB','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239818/7b189b6635483a339d001669efe6203f452564ae694df2ec7ae2d69cf1da309e.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=239818;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241159,'Marc Guéhi',85,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241159/8dda390843bd07ff04a01537344db98fbe3e73ad73c4cbd4128444461ae60754.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=241159;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(251517,'Joško Gvardiol',85,'CB','Croatia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/251517/fa277ed25d4b09cefad7b1e64c8d90271378b2f23683f708533d1236fcffdc8f.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=251517;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(247090,'Enzo Fernández',86,'CM','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/247090/8e1a6e43526d787e5eaca211a9f4671db37f335d5ce01f2c97fcbcf2a7d6f807.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=247090;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(254243,'Elliot Anderson',84,'CDM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/254243/006e0b939734f20e18edb8a8d02cf1cd775ff05018a61d51daad5e979f57583e.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=254243;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241236,'Antoine Semenyo',85,'RW','Ghana','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241236/458aadd8ca8b56f4bd3af1350ed1e26ba06033f2f751a20beca47ab8b6288d24.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=241236;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(261188,'Iliman Ndiaye',82,'LM','Senegal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/261188/e501d786bdd8a3c9aac0c4a41c9e83cfb761ca3767ee6ae2a2e71ce935273744.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=261188;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(251570,'Rayan Cherki',86,'RW','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/251570/610f26f545e06305072fd1e5151b9b9828bef212d932ef30ea41f3ae37715089.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=251570;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239085,'Erling Haaland',91,'ST','Norway','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239085/138967fa639e1d4d9034dfb7c4f3b070ab8c676c06e22290c871586019e5f5d0.png',120000000,180000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=239085;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(207410,'Mateo Kovačić',81,'CM','Croatia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/207410/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=207410;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278901,'Ayyoub Bouaddi',80,'CDM','Morocco','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278901/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=278901;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277427,'Nico O''Reilly',83,'LB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277427/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=277427;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277031,'Abdukodir Khusanov',82,'CB','Uzbekistan','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277031/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=277031;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(242641,'Rayan Aït-Nouri',81,'LB','Algeria','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/242641/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=242641;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(271574,'Rico Lewis',77,'RB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/271574/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=271574;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(215316,'Gerónimo Rulli',80,'GK','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/215316/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=215316;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(237692,'Phil Foden',84,'CAM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/237692/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=237692;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(89738,'Allan Andrade Elias',77,'RW','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/89738/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=89738;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(246420,'Jérémy Doku',84,'LW','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/246420/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=246420;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(76624,'Vitor Reis',76,'CB','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/76624/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=76624;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(81685,'Ryan McAidoo',66,'RW','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/81685/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=81685;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(88560,'Kaden Braithwaite',65,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/88560/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=88560;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(88662,'Floyd Samba',64,'CM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/88662/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=88662;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(204246,'Marcus Bettinelli',69,'GK','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/204246/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=10 AND p.sofifa_id=204246;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(11,'Manchester United','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/11/268112a9e79f4cc6dec49319add20dc8f517312f22a9dee9756c8cd41240b762.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(254803,'Senne Lammens',82,'GK','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/254803/6091afb90e478904842c2cbf166de719a3d3e04f55ba15b209ae743915eee437.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=254803;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(234574,'José Diogo Dalot Teixeira',78,'RB','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/234574/0ab7291d82231911448dcec7a784c2cbaa98b27d70d73c1b50ec6f77c3c53065.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=234574;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(203263,'Harry Maguire',82,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/203263/3d675ca3ecc781139fc0c4ff2decf62196821b0977f8db0422f7d1bb62fa3aa7.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=203263;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239301,'Lisandro Martínez',82,'CB','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239301/9f9e90bccee9d92416da87ee38a7dac9eebb19937f8db196f205299297eff36b.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=239301;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(205988,'Luke Shaw',79,'LB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/205988/3c482147bf6d6a89995e6a973a953449fa044d36e5120596369bcd603f78ac41.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=205988;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(216393,'Youri Tielemans',85,'CM','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/216393/6bfb5fbb607cd73afc6475c4b8ebc0916b573a6a0080a6cd2f60abe77e277ac9.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=216393;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(269136,'Kobbie Mainoo',81,'CDM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/269136/7a778ba300e0cac889c9ba56c0ded544c0049e51864928526b6c9bd41227503a.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=269136;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243014,'Bryan Mbeumo',84,'RM','Cameroon','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243014/a958abdb27a0362ac5d6e8fef780f8e64af524dd93d3f96bb113bbac011ffcde.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=243014;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231677,'Marcus Rashford',82,'LW','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231677/c21b589c8ffb496b7a5596a6a01c929d8351b9af890b59e2af644482ee5b5448.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=231677;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(212198,'Bruno Miguel Borges Fernandes',89,'CAM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/212198/5bee1dd6302f650b0fe20af5aa81571020ddd8bf707b802a25859a03eaf55dc4.png',85000000,127500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=212198;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(240243,'Matheus Santos Carneiro da Cunha',84,'LM','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/240243/d3124a122ee74c0cfe8cbf66cac286b161820572fcc60f63e94f2b21566526e5.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=240243;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(272500,'Carlos Baleba',80,'CDM','Cameroon','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/272500/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=272500;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(273018,'Andrey N. dos Santos',80,'CM','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/273018/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=273018;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(233064,'Mason Mount',78,'CAM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/233064/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=233064;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277432,'Patrick Dorgu',78,'LM','Denmark','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277432/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=277432;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(236401,'Noussair Mazraoui',80,'RB','Morocco','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/236401/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=236401;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(269087,'Leny Yoro',78,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/269087/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=269087;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(193331,'Karl Darlow',76,'GK','Wales','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/193331/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=193331;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(250961,'Joshua Zirkzee',77,'ST','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/250961/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=250961;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(260592,'Benjamin Šeško',82,'ST','Slovenia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/260592/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=260592;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(75087,'Ayden Heaven',75,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/75087/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=75087;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278124,'Shea Lacey',65,'RM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278124/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=278124;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(254088,'Amad Diallo',79,'RM','Côte d''Ivoire','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/254088/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=254088;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(235243,'Matthijs de Ligt',82,'CB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/235243/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=235243;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(253306,'Manuel Ugarte',77,'CDM','Uruguay','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/253306/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=253306;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(273599,'Harry Amass',69,'LB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/273599/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=273599;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(163264,'Tom Heaton',67,'GK','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/163264/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=163264;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(82899,'Tyler Fletcher',65,'CM','Scotland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/82899/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=82899;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(75439,'Jack Fletcher',63,'CM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/75439/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=75439;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(268415,'Dermot Mee',59,'GK','Northern Ireland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/268415/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=11 AND p.sofifa_id=268415;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(18,'Tottenham Hotspur','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/18/d50de4957ad5acb90cbf02a7a0ad111957104db4eb1a1cb982c63f9755d6cc1e.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(73580,'Antonín Kinský',77,'GK','Czechia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/73580/498dd4c94220a669ddd4961a103cf2d5f7a7428c686dd0fa110b1ce66f281154.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=73580;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243576,'Pedro Antonio Porro Sauceda',83,'RB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243576/0425a14de034d4edfd61c00411043cffc49a7caa6562298bab53fa45bd24e01c.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=243576;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(258908,'Jan Paul van Hecke',81,'CB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/258908/e5fc39ae184d2093bf577724c77ada15288387634ada822cc2e6cf988c009725.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=258908;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(264453,'Micky van de Ven',81,'CB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/264453/ad906aa5f5aa1ad5c7be7b1570ba9e806212ef3592125405bcbb21e2e5095f4c.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=264453;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(216267,'Andrew Robertson',80,'LB','Scotland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/216267/99a42ad31cb35fca8c417fa03a2df7dee8ea5ee786fefcb73197e647f6fb056d.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=216267;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(227535,'Rodrigo Bentancur',79,'CDM','Uruguay','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/227535/66148c3715408fb95041d2cfbc42b21ab52312449e8b15b956900e5ff9bc5846.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=227535;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241096,'Sandro Tonali',85,'CDM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241096/d20f1010386e9c6b46c5f006064373b5c5c03dd28923448f1a275faac2422935.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=241096;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(270409,'Sávio Moreira de Oliveira',80,'RW','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/270409/45aa8da5e070a7dcbb7d8f654a9cd6344129a2519b69db0657b09ce20c9afd3c.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=270409;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(268421,'Mathys Tel',78,'LM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/268421/90e203474bf0eb02966409e0d04dc33b47f572999f3140264a9d998fc8672936.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=268421;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(270857,'Mateus Gonçalo Espanha Fernandes',80,'CM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/270857/ab791e7d9bff90d4dba10c8cce57648ae243a8b795d5752f2b1dfca16dd525e0.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=270857;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256675,'Omar Marmoush',82,'LW','Egypt','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256675/7faf69849e5e83eb5c0e9027d7fa1511411e41fef9bc9f17c7a2027a6baaeec0.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=256675;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(220697,'James Maddison',82,'CM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/220697/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=220697;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(238216,'Conor Gallagher',78,'CM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/238216/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=238216;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(272926,'Lucas Bergvall',78,'CM','Sweden','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/272926/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=272926;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(270208,'Archie Gray',77,'CDM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/270208/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=270208;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(236506,'Marcos Senesi',82,'CB','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/236506/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=236506;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259583,'Destiny Udogie',79,'LB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259583/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=259583;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(220407,'Martin Dúbravka',77,'GK','Slovakia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/220407/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=220407;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(225539,'Dominic Solanke',79,'ST','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/225539/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=225539;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(245155,'Mohammed Kudus',81,'RM','Ghana','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/245155/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=245155;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(222104,'Tosin Adarabioyo',77,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/222104/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=222104;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(205923,'Ben Davies',74,'CB','Wales','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/205923/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=205923;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(246340,'Mykhailo Mudryk',75,'LM','Ukraine','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/246340/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=246340;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(236568,'Brandon Austin',67,'GK','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/236568/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=236568;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231943,'Richarlison de Andrade',78,'ST','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231943/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=231943;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(245367,'Xavi Simons',81,'CAM','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/245367/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=245367;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(247394,'Dejan Kulusevski',81,'CM','Sweden','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/247394/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=247394;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(270579,'Wilson Odobert',78,'LM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/270579/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=18 AND p.sofifa_id=270579;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(243,'Real Madrid','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/243/1d09ab1602cd9eabc9fff26d9a50626bb28a47c46c014723f65794a20b5fe744.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(192119,'Thibaut Courtois',90,'GK','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/192119/1df578cb463d87172761d9c9f5a8161e668c8e62dde44e020285717669b0b69d.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=192119;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(233096,'Denzel Dumfries',83,'RB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/233096/962d409a20e41229f7f8d6d9233b1222e60c0b112354772137e561daffd0bfa2.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=233096;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(237678,'Ibrahima Konaté',84,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/237678/50b95ed46fa2952ea0869b8f78af3822c4c308b852dbda55cfe5cded3c1296fc.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=237678;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278349,'Dean Huijsen',81,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278349/cd6d1e709c4e797ed1f2a7d421f28c496e77bd73791bca171d533ae23e71133d.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=278349;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239231,'Marc Cucurella Saseta',86,'LB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239231/abe9d02ccb7dcff45d48425a58df9c3f9d9dbd234a4213571d161dd94996befa.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=239231;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239053,'Federico Valverde',87,'CM','Uruguay','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239053/a22da609c91c3d64f248d1b6542e3dbe0db6a19d5b3f86b75e688af587b4f8ad.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=239053;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241637,'Aurélien Tchouaméni',84,'CDM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241637/e879f636374fa7025dacaf4e3ab174b758e08f68229e851ab114eb88c843741d.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=241637;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(252371,'Jude Bellingham',90,'CAM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/252371/cc05c8338c8440f4da77ad5bb9a69344577f6170bc6186410c7b64c708a8f0b1.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=252371;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(264309,'Arda Güler',84,'RM','Türkiye','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/264309/674bc658ea39ac034f4d2e82edf2aa65a1558f51ddbdcfcbf5c6ceb09f0a65c1.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=264309;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231747,'Kylian Mbappé',91,'ST','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231747/2fadf67a9131454e2083696c8783a9fc047a4e69f318d8ec926391447142e957.png',120000000,180000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=231747;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(238794,'Vinícius José de Oliveira Júnior',89,'LW','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/238794/7d52e848b4b608217be6fd79f1b59acf36ce6a49fbc0997fdf2fe5079721134e.png',85000000,127500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=238794;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(78012,'Yan Diomande',84,'RW','Côte d''Ivoire','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/78012/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=78012;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(70967,'Carlos Espí Escrihuela',77,'ST','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/70967/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=70967;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(218667,'Bernardo Mota Carvalho e Silva',84,'CM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/218667/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=218667;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231281,'Trent Alexander-Arnold',84,'RB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231281/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=231281;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(240130,'Éder Gabriel Militão',84,'CB','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/240130/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=240130;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(268889,'Álvaro Fernández Carreras',81,'LB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/268889/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=268889;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243952,'Andriy Lunin',80,'GK','Ukraine','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243952/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=243952;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(205452,'Antonio Rüdiger',83,'CB','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/205452/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=205452;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231410,'Brahim Díaz',81,'RM','Morocco','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231410/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=231410;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(272505,'Endrick Felipe Moreira de Sousa',79,'ST','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/272505/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=272505;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(248243,'Eduardo Camavinga',81,'CM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/248243/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=248243;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(75605,'Raúl Asencio del Rosario',78,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/75605/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=75605;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(82756,'Jorge Cestero Sancho',64,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/82756/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=82756;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(75572,'Jesús Fortea Tejedo',63,'RB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/75572/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=75572;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(88073,'Alexis Ciria Flores',65,'LW','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/88073/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=88073;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(272503,'Sergio Mestre Sánchez',61,'GK','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/272503/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=272503;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(75917,'Daniel Yáñez Barla',64,'RW','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/75917/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=75917;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(80807,'Thiago Pitarch Pinar',70,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/80807/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=80807;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(80659,'Sergio Martínez Montero',64,'CDM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/80659/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=80659;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243812,'Rodrygo Silva de Goes',84,'LW','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243812/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=243812;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(228618,'Ferland Mendy',80,'LB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/228618/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=243 AND p.sofifa_id=228618;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(241,'FC Barcelona','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/241/5e841e1b3721d5ebac15e05a238954e0d3fe161615734f5b1c2fff60803237b3.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259532,'Joan García Pons',86,'GK','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259532/cd7f66b836c7e3b394c5359021a643d8e17edeef8e6e594c9344a26fd46d431b.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=259532;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(245037,'Eric García Martret',85,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/245037/465c76f62c9f0f5852d4af7db1f23f893f55da3bc14a051ffc0901e92328c926.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=245037;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278046,'Pau Cubarsí Paredes',86,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278046/e72cf9b9c2d7b418caa72faa87a8e58f16c9f4e2fb1333bb6cea19624e7d3760.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=278046;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(74462,'Gerard Martín Langreo',79,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/74462/69648d84df8a17e158ebded49e17027c4264acd2d3a17099aa9c793a557a0e7e.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=74462;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(210514,'João Pedro Cavaco Cancelo',83,'LB','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/210514/d6b576d68e6c12bbcd18d2c93f8112d8f75197bb01af7402377f6ad4c755367c.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=210514;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231866,'Rodrigo Hernández Cascante',90,'CDM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231866/c7f5b5f5daa77c229901193bc8add41f778e22d4f96c1cd71d3ce5be2cb19717.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=231866;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(251854,'Pedro González López',90,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/251854/a2004c3a9730200fb9b452265b33d7564ae67669f60e4515b447c7af86508ab4.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=251854;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277179,'Fermín López Marín',85,'CAM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277179/d40fe2ec5bbccf9ab5cb28f4ef11bbe2aae54e824a217f7d9d37d6a351c076ef.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=277179;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277643,'Lamine Yamal Nasraoui Ebana',90,'RW','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277643/35a56d2d70b4ee463f85792ab84545fb4769153c06ea95f077f32531ae3305f7.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=277643;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(233419,'Raphael Dias Belloli',89,'LW','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/233419/73715aec3b202953c8902b2ce41aedc1bffb702702d9f44e60977c2d0058cc9b.png',85000000,127500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=233419;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(242964,'Anthony Gordon',82,'LW','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/242964/ce230b430794f564986d8c006a14976cc5f30514fda082c16deda92bdd1bd3c2.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=242964;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(251852,'Karim Adeyemi',82,'LW','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/251852/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=251852;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(230666,'Gabriel Fernando de Jesus',79,'ST','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/230666/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=230666;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(244260,'Daniel Olmo Carvajal',84,'CAM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/244260/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=244260;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(264240,'Pablo Martín Páez Gavira',82,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/264240/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=264240;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241486,'Jules Koundé',85,'RB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241486/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=241486;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(213661,'Andreas Christensen',79,'CB','Denmark','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/213661/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=213661;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241671,'Dominik Livaković',78,'GK','Croatia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241671/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=241671;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(81863,'Xavi Espart Font',71,'RB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/81863/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=81863;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(74463,'Marc Bernal Casas',78,'CDM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/74463/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=74463;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(263578,'Alejandro Balde Martínez',82,'LB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/263578/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=263578;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(88043,'Jesse Eugen Bisiwu',67,'LW','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/88043/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=88043;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(86106,'Hamza Abdelkarim',65,'ST','Egypt','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/86106/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=86106;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(186153,'Wojciech Szczęsny',80,'GK','Poland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/186153/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=186153;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(89427,'Brian Fariñas Pérez',65,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/89427/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=89427;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(228702,'Frenkie de Jong',86,'CM','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/228702/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=228702;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(265600,'Roony Bardghji',74,'RW','Sweden','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/265600/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=241 AND p.sofifa_id=265600;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(240,'Atlético Madrid','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/240/f9363716e496ef5218627961128eef15f64679611c858339b595ee7d399ac2e4.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(200389,'Jan Oblak',88,'GK','Slovenia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/200389/3deddd0fe0b2a61a14ea643708d35e0b04518233348e3a5958fe19382db3802a.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=200389;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(266039,'Marc Pubill Pagès',81,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/266039/6e9b9d07291cb90af7a82ada419dcf505a3dd9bc028e1c3e6c9a812c77515a90.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=266039;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(232488,'Cristian Romero',82,'CB','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/232488/0429ae03a4005a3129cd1f3489a4c242bb3c2f04e2bfe5daa6e57ae4583ed622.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=232488;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(247103,'Dávid Hancko',83,'CB','Slovakia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/247103/debf0e2cdcbfc2223f4d16ceba8cd94beef705a89f5d13e03c0688ce95d7b0a2.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=247103;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(226161,'Marcos Llorente Moreno',85,'RB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/226161/42889050c53a2f7c30e04e84fcfd97a47362943fa8d7f622e06c6b0bf4fa0b74.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=226161;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(272449,'Pablo Barrios Rivas',83,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/272449/7788f6cc6a94dfa7b1a50d73b80753c0a607736135d49dfc78292cc4c688372a.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=272449;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(244669,'Morten Hjulmand',83,'CDM','Denmark','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/244669/fbf69189c1fa63811c86a4f649ec4f6023be962334ddcd056c45d2d8d586c4bf.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=244669;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(210035,'Alejandro Grimaldo García',85,'LM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/210035/07c0855b24dadcde737ce9db32c862ef8ef38fe92f068698e0b2b101c76927f2.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=210035;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243780,'Kang In Lee',81,'RW','Korea Republic','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243780/91f0da2ae6b11ea593f9cd2e909ff5041c11579f08acd9fe0093313e8ba20dfa.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=243780;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(257279,'Alejandro Baena Rodríguez',83,'LM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/257279/bff2139c7bcff86e294b3ea023c1d802858f8fdfaae93c1f0d90aad105dc31c3.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=257279;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(246191,'Julián Alvarez',86,'ST','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/246191/21c43949fbaa2394c236af69952600b37edc9f3638f2bc067e22f173abfcf356.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=246191;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(216549,'Alexander Sørloth',83,'ST','Norway','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/216549/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=216549;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(230899,'Ademola Lookman',82,'ST','Nigeria','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/230899/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=230899;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(253396,'Giuliano Simeone',82,'RM','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/253396/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=253396;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(193747,'Jorge Resurrección',81,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/193747/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=193747;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259516,'João Lucas de Souza Cardoso',80,'CDM','United States','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259516/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=259516;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(233486,'Robin Le Normand',81,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/233486/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=233486;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(214979,'Juan Musso',82,'GK','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/214979/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=214979;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(264738,'Arnau Ortiz Sánchez',71,'LW','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/264738/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=264738;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243630,'Jonathan David',80,'ST','Canada','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243630/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=243630;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(263701,'Obed Vargas',72,'CDM','Mexico','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/263701/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=263701;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278523,'Rodrigo Mendoza Martínez',72,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278523/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=278523;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(82755,'Daniel Martinez Moreno',64,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/82755/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=82755;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(85338,'Miguel Llorente Cubo',63,'ST','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/85338/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=85338;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(80673,'Salvador Esquivel Gámez',64,'GK','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/80673/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=240 AND p.sofifa_id=80673;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(45,'Juventus','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/45/e57c348a6e9e40cd5638e5f4e198cbf316abc517b36cc986ac930d81ebb2b2cc.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(240091,'Guglielmo Vicario',80,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/240091/bd2604a4be706712784874f6b78e22b3c9c705f5b18277faff0fbac12a899c78.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=240091;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(255654,'Pierre Kalulu',81,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/255654/443d492fd19116d39e432c062098be59771ab8bf7d6e4ddc6af730d06997f143.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=255654;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239580,'Gleison Bremer Silva Nascimento',86,'CB','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239580/87ad6f01935347c6e4c2fd3d1113136cd013efe1aca7d6219e81833f5658948b.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=239580;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231207,'Jhon Lucumí',76,'CB','Colombia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231207/d5cd318c086d6a840a591c4f14a919cb65a9eb83f2e3e87044718ce8445ca316.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=231207;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(224490,'Zeki Çelik',79,'RB','Türkiye','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/224490/309b1f608fc6fc8fc685d77b36f39242cb201a8e20eebe9d65ef1e49d227c40b.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=224490;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(236499,'Douglas Luiz Soares de Paulo',78,'CDM','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/236499/c090a9dbb70f25a374452680cc2b3c74ce80c415176b6894c776a1d60c49c30b.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=236499;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(240679,'Teun Koopmeiners',78,'CAM','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/240679/25c0a5350607d262e12f2a325ed478e9c68cd2e725ce6e019307c47e7e34daff.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=240679;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(261050,'Francisco Conceição',80,'CAM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/261050/25dc8da75be3ef2784b3a2c105e3314c459b53bc2ec3de1a828200eee2abc6c5.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=261050;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(75533,'Kerim Alajbegović',71,'CAM','Bosnia and Herzegovina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/75533/e87ef45a3f5b734d01e704ecd60d79188155a6ea407fd8b184089f2db12f8881.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=75533;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(240690,'Nico González',79,'LM','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/240690/4c1abd6b598c3ac550401747f9122e9034b3fde5ab887b021dfff867707b2b75.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=240690;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(237679,'Randal Kolo Muani',77,'ST','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/237679/cc2401fafa3192c10a035b5e32e5c74fc5b535a599b3fe56014c96c76bb9aa71.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=237679;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(254022,'Nick Woltemade',80,'ST','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/254022/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=254022;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(238744,'Weston McKennie',80,'CM','United States','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/238744/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=238744;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(224422,'Jérémie Boga',78,'CAM','Côte d''Ivoire','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/224422/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=224422;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239763,'Edon Zhegrova',78,'RM','Kosovo','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239763/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=239763;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(266872,'Federico Gatti',79,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/266872/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=266872;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231512,'Lloyd Kelly',77,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231512/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=231512;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(189342,'Carlo Pinsoglio',68,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/189342/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=189342;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(211320,'Daniele Rugani',74,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/211320/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=211320;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259868,'Pape Matar Sarr',79,'CM','Senegal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259868/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=259868;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(228383,'Kamil Grabara',81,'GK','Poland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/228383/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=228383;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(251870,'Juan David Cabal',74,'LB','Colombia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/251870/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=251870;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(258966,'Andrea Cambiaso',80,'LB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/258966/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=258966;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(222077,'Manuel Locatelli',84,'CDM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/222077/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=222077;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(247246,'Khéphren Thuram',81,'CM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/247246/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=247246;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277954,'Kenan Yıldız',84,'CAM','Türkiye','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277954/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=277954;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(74485,'Jeff Ekhator',68,'ST','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/74485/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=74485;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(205175,'Arkadiusz Milik',76,'ST','Poland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/205175/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=205175;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(87860,'Justin Oke Oboavwoduo',65,'ST','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/87860/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=87860;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(194404,'Norberto Murara Neto',72,'GK','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/194404/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=45 AND p.sofifa_id=194404;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(44,'Inter','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/44/d6791064ddb69d34e564b5de47d72a919f0e71f0f28b2de38a5085f913fe4442.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243311,'Josep Martínez Riera',76,'GK','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243311/497171bac3c30dc74548b9bea05607dcf601e7e5b131e91670225d2256e66f98.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=243311;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(268534,'Andy Diouf',76,'CM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/268534/f01cd1819426fd4f846781dbe571547fb9098252987fe598f379e0a7a60040bf.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=268534;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241736,'Yann Bisseck',78,'CB','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241736/bd4c3e673c536b23a0f0ea05994097cd4e848be83ddf0b506c6092492669ee87.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=241736;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(229237,'Manuel Akanji',83,'CB','Switzerland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/229237/c1f6ff0a41bc25426dd199c88a265ed510303b321a084b3ed0623ef4a70afd8b.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=229237;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(237383,'Alessandro Bastoni',86,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/237383/ce440753babf9606fb2d336af3a6950fd6702742e95ecdefeeef28a5a5077cd6.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=237383;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(226268,'Federico Dimarco',86,'LB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/226268/9f1297fd66dee920c569a23416a7ea85402130066c22e4e8112381bfece84c57.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=226268;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(210406,'Piotr Zieliński',82,'CM','Poland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/210406/aa7f6b9eff103237dbca14de2b2d56c15623c249969d4552dfc9d943559dbf7e.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=210406;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(224232,'Nicolò Barella',87,'CM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/224232/9a387919b8a7c5a2c316a8b27d412eeacb89f15d061533d3a867cc1749161896.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=224232;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(276278,'Petar Sučić',78,'CM','Croatia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/276278/3ca046a7d3f33a8c225962dcad354a9ab772de0848409666354a9c6cad63a91a.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=276278;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277327,'Francesco Pio Esposito',77,'ST','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277327/3a39ff384cd73debe74f3eab520cb238d6fe559bb1c41d72725f9a39679b0152.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=277327;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231478,'Lautaro Martínez',87,'ST','Argentina','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231478/f9f1b7aba5245695b8018715907e1345f6e3dac5d833543c5a844029dbb0f8cd.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=231478;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(228093,'Marcus Thuram',85,'ST','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/228093/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=228093;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259565,'Yoan Bonny',78,'ST','Côte d''Ivoire','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259565/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=259565;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(208128,'Hakan Çalhanoğlu',85,'CDM','Türkiye','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/208128/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=208128;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(242434,'Curtis Jones',80,'CM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/242434/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=242434;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(226851,'Benjamin Pavard',80,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/226851/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=226851;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256632,'Luis Henrique Tomaz de Lima',77,'RB','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256632/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=256632;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(224987,'Ivan Provedel',83,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/224987/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=224987;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(203574,'John Stones',82,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/203574/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=203574;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(258648,'Carlos Augusto Zopolato Neves',80,'LB','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/258648/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=258648;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(219715,'Raffaele Di Gennaro',68,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/219715/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=219715;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243702,'Djed Spence',80,'LB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243702/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=243702;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278318,'Aleksandar Stanković',76,'CDM','Serbia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278318/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=278318;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(192883,'Henrikh Mkhitaryan',81,'CM','Armenia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/192883/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=44 AND p.sofifa_id=192883;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(47,'AC Milan','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/47/4ee1bde61024fdef2a2502e6ccb96754ba2f40e47163ca46c816e644f974cdda.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(215698,'Mike Maignan',87,'GK','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/215698/1498de65f55cd4b4876409b069bbd295c0cf9dec29e76d89ec51c7cccfb5eedf.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=215698;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(268804,'Mario Gila Fuentes',81,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/268804/0a2708f968659c605c2f712d2f170add12879693d5e4098169155e0737d2400c.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=268804;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(265774,'Koni De Winter',75,'CB','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/265774/37cab17ea94ef90bb47a2d3fe56f924844ce691011bc9c810e2cef3a1f18b99f.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=265774;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(254840,'Strahinja Pavlović',78,'CB','Serbia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/254840/af93710c2ec48d1948c0233c764f6e4bd2003318989ad7a9722f858457b22188.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=254840;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(246172,'Samuel Chukwueze',78,'RM','Nigeria','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/246172/0e7aec338e1618946242df13fe8b726c42e98b1168292dc3a3b78e24faf97f52.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=246172;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(177003,'Luka Modrić',85,'CM','Croatia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/177003/900defdd0fa70f3aa0008034b1268ec23f12c934d646cdb1b62ace09027b7a77.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=177003;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(210008,'Adrien Rabiot',85,'CM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/210008/87c12989425982538a8365ea91d5fd60aa7c2e913b83b7e80c279d08e1b2df4d.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=210008;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(237942,'Pervis Estupiñán',78,'LB','Ecuador','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/237942/d7ae29891c5501502d07f9ea51e8ed7fbecb5cd22600ae78f433fd40714195f8.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=237942;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(227796,'Christian Pulisic',83,'CAM','United States','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/227796/720cd956c453b71da79e4ddafa13987bef3689fd25dd34c7b7e8d405bf0bf9c0.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=227796;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(213666,'Ruben Loftus-Cheek',79,'CAM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/213666/daf3c8c2adb5591586d58d3f110fbe02a1a6bcc04ffcb755bfebe5f2dd6fb0dc.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=213666;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256903,'Gonçalo Matias Ramos',80,'ST','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256903/062a821472fdac0f7f64d0032a16f4654c1780c9079a2b7976ae037518e01e92.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=256903;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(270039,'Diego Manuel J. da Silva Moreira',79,'RM','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/270039/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=270039;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(257186,'Ardon Jashari',76,'CDM','Switzerland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/257186/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=257186;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(253177,'Yunus Musah',74,'CM','United States','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/253177/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=253177;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278326,'Alphadjo Cissè',68,'CAM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278326/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=278326;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(240277,'Matteo Gabbia',80,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/240277/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=240277;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278237,'Davide Bartesaghi',74,'LB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278237/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=278237;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(205812,'Pietro Terracciano',76,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/205812/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=205812;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(242664,'Alexis Saelemaekers',80,'RB','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/242664/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=242664;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(279202,'Francesco Camarda',66,'ST','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/279202/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=279202;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(72179,'Lorenzo Torriani',62,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/72179/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=72179;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(74510,'Sankhoun Diawara',69,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/74510/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=74510;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(271579,'Filippo Terracciano',71,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/271579/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=271579;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(232756,'Fikayo Tomori',80,'CB','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/232756/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=232756;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(85891,'Valeri Ivanov Vladimirov',60,'CB','Bulgaria','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/85891/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=85891;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(257353,'Warren Bondo',70,'CDM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/257353/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=257353;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(80597,'Christian Comotto',65,'CM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/80597/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=80597;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(260145,'Omari Hutchinson',76,'RM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/260145/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=47 AND p.sofifa_id=260145;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(48,'Napoli','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/48/1891292ab026fc173a7653ec206742017812fb8a1156f20ef92f8fd8ad240507.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(225116,'Alex Meret',81,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/225116/dd198d05e944076e6757987a0535908a83da93e6710c46fb64ae89923fe93411.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=225116;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(217870,'Giovanni Di Lorenzo',82,'RB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/217870/e89a626cbae93c339d9ec3fbdcf342b4917d3915fc417a6eb266cfdfb541bb63.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=217870;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(244263,'Amir Rrahmani',83,'CB','Kosovo','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/244263/dd35c1bad5e603263b34e2634c2cf67cbe5bfdc8393be0809f789e091a8c9ca7.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=244263;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277244,'Rafael Marín Zamora',76,'CB','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277244/c400240a528ec38e9d15bd687586c1e1236e1d5489ab4a26cb435f5efd45f14c.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=277244;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(202884,'Leonardo Spinazzola',80,'LB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/202884/abeceda3b008ee5e00eaa4bc528dfce5646235d6402bbae1caf6be7c1b67f968.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=202884;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(245992,'Billy Gilmour',75,'CM','Scotland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/245992/6aa6ed4550f2d9b16b637bff28ee7744d64ac43fa13a5e092498d09ac742054d.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=245992;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(216435,'Stanislav Lobotka',83,'CM','Slovakia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/216435/44d68f44968548c034b101878f36a6ee3a9b69863b1a563518d1d00e70cb8adc.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=216435;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(216409,'Matteo Politano',80,'RW','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/216409/1d19ae002e24e87c312fd408f5b54c2b5948cf3e432eb595451d6bc5fd0f4300.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=216409;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(239380,'Noa Lang',79,'LM','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/239380/048b4158380d971849780f9a632722cba462a3a67c5d548559af2fb9bcf38516.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=239380;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(192985,'Kevin De Bruyne',85,'CAM','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/192985/90947a19ffa3504e94bf38a3ce95f39a0e71e75d0cf12617ea5704c3e7aae08c.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=192985;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259399,'Rasmus Højlund',78,'ST','Denmark','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259399/bc009ae46a53ac6a976005dddde7bdcdaebcf20868ee617563a3ddaf07243325.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=259399;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(268474,'Lorenzo Lucca',75,'ST','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/268474/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=268474;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(79270,'Alisson de Almeida Santos',74,'CAM','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/79270/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=79270;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(276706,'Antonio Vergara',69,'CAM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/276706/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=276706;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(277870,'Costantino Favasuli',69,'RM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/277870/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=277870;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(240716,'Mathías Olivera',77,'LB','Uruguay','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/240716/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=240716;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(242578,'Benoît Badiashile',76,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/242578/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=242578;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(224836,'Vanja Milinković-Savić',80,'GK','Serbia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/224836/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=224836;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(227236,'André-Franck Zambo Anguissa',82,'CM','Cameroon','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/227236/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=227236;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(236632,'David Neres Campos',81,'LW','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/236632/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=236632;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(220532,'Nikita Contini',67,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/220532/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=220532;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(262394,'Sam Beukema',78,'CB','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/262394/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=262394;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(243241,'Alessandro Buongiorno',81,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/243241/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=243241;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(278319,'Luca Marianucci',68,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/278319/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=278319;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(237238,'Scott McTominay',86,'CM','Scotland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/237238/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=237238;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(80283,'Giovane Santana',71,'ST','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/80283/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=48 AND p.sofifa_id=80283;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(21,'FC Bayern München','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/21/060ca57d280430a70d934e0e2ed283d089c61ecc8d5d33ca1a021186ee1c1f5d.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(167495,'Manuel Neuer',81,'GK','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/167495/737c08a1ead540749b70485712403deeb59c2e627c4567b97852f42a21790f0f.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=167495;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(225375,'Konrad Laimer',85,'RB','Austria','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/225375/2de7d858852260facb52fb52b07d26f9769574f66fa58e395a293ac90ffa0210.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=225375;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(229558,'Dayot Upamecano',87,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/229558/3a10065966cebfbb2a47000147a9ad1b465d1bde94ac05658b19e0353394489e.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=229558;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(213331,'Jonathan Tah',87,'CB','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/213331/318e8fc275794a0098d5aa0ccb55c549a7ac1003468a1d1d811c4e1e5903c76b.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=213331;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(234396,'Alphonso Davies',82,'LB','Canada','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/234396/9e9043925e565e390e065332168c7630b8ef4d51937dd6b7a2e81367f0d46cbc.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=234396;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(212622,'Joshua Kimmich',88,'CDM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/212622/f9fdb0ff0ceb8b9ec509266422ac6f56c67ddaa5ab926e4846f7240aef65114b.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=212622;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(275298,'Aleksandar Pavlović',83,'CDM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/275298/16969fdc7002d4a80e4848ce83f517217305a0e2f7acae13404e6a5a3fe16fde.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=275298;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(78063,'Lennart Karl',77,'RM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/78063/3bb8870aa766a2ea7972ecb6368297e372eff224d623e4c4fb4ab001ab2c9565.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=78063;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241084,'Luis Díaz',88,'LM','Colombia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241084/658c377e077b8f4144e2fa9e2f9714c18ad8dad138b3e7054e20f11c1fe6b3ab.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=241084;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(247827,'Michael Olise',90,'RM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/247827/ce1895252a0d404a2d1f128c781f8f95088962e77faf5b8d6d692b3b169586ea.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=247827;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(202126,'Harry Kane',90,'ST','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/202126/6e54f25032d01832a2afc3a147ad6a17a8fb6e7967e56b55b81670a581ac0947.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=202126;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256790,'Jamal Musiala',87,'CAM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256790/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=256790;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(263765,'Tom Bischof',79,'CM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/263765/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=263765;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(237086,'Min Jae Kim',83,'CB','Korea Republic','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/237086/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=237086;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(269701,'Nathaniel Brown',81,'LB','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/269701/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=269701;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(250955,'Josip Stanišić',80,'RB','Croatia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/250955/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=250955;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(234205,'Hiroki Ito',78,'CB','Japan','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/234205/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=234205;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(263887,'Jonas Urbig',79,'GK','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/263887/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=263887;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259480,'Ismael Saibari',83,'CAM','Morocco','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259480/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=259480;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(206113,'Serge Gnabry',83,'CAM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/206113/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=206113;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(186569,'Sven Ulreich',73,'GK','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/186569/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',2000000,3000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=186569;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(85225,'Bara Sapoko Ndiaye',64,'CM','Senegal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/85225/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=85225;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(84386,'Maycon Douglas Normanha Cardozo',59,'RM','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/84386/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=84386;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(79317,'David Santos Daiber',59,'CDM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/79317/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=79317;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(248266,'Sacha Boey',75,'RB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/248266/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=21 AND p.sofifa_id=248266;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(22,'Borussia Dortmund','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/22/bc551b2c99eb640677e3e0237a87a6325f8903e1b189a162f58007ddde1ccd99.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(235073,'Gregor Kobel',87,'GK','Switzerland','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/235073/4ac3e29741b38f228655b1cce0a2c431f8357e57a8e7c14944703f150c8f1929.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=235073;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(71350,'Joane Gadou',70,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/71350/4aa877a8c7896b1e053f9dda2ecff116fd787605e46f2508b6f7b624f65d4669.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=71350;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(229476,'Waldemar Anton',84,'CB','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/229476/4c5d29caecd9e3d3a43d5035e9bc7be23cc8fd3653028b8110c6206b7f9dd676.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=229476;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(247819,'Nico Schlotterbeck',87,'CB','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/247819/c194b09527c55dfc73ae42589c1529996448eb08b8ee03df14ba02a8b07bce57.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=247819;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(229891,'Julian Ryerson',82,'RB','Norway','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/229891/892440d9c5dad1789216b44d7adae1631ac7761ee82860b6aa9efabdfe90633e.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=229891;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(253109,'Joey Veerman',82,'CM','Netherlands','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/253109/502c4592a9a253cbf3cc8d53daf252874d3240ea1689daafe63463a398f22ec5.png',20000000,30000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=253109;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(246863,'Felix Nmecha',85,'CM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/246863/95f8898562ef80616275c13d0f8346748e4714248e81a7742016dc1493ea1c1e.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=246863;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259716,'Daniel Svensson',79,'LB','Sweden','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259716/354d27dc11540dfad09544a599df2eabaeb753dea3b3f104dad4b6d2b80a436b.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=259716;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(70497,'Konstantinos Karetsas',76,'CAM','Greece','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/70497/b8681873b18eaa063486f1ca54e437e2418de0552cc98edd05c262adae43a34e.png',5000000,7500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=70497;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(252037,'Fábio Daniel Soares Silva',78,'ST','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/252037/9cea1c14d1e87d303d261607e5344218b14f4af0b7e5e1d1a72792f70005f831.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=252037;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(215441,'Serhou Guirassy',85,'ST','Guinea','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/215441/7ea24308857affa3b48003104154a31d48dae713c0da3811b2ef2a232a036568.png',40000000,60000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=215441;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(204923,'Marcel Sabitzer',81,'CM','Austria','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/204923/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=204923;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259356,'Carney Chukwuemeka',78,'CAM','Austria','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259356/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=259356;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(270964,'Jobe Bellingham',77,'CM','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/270964/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',6500000,10000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=270964;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(83748,'Samuele Inácio',70,'CAM','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/83748/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=83748;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(224196,'Ramy Bensebaini',79,'CB','Algeria','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/224196/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=224196;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(83476,'Kauã Prates de Almeida',67,'LB','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/83476/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=83476;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241050,'Alexander Meyer',74,'GK','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241050/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3000000,4500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=241050;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(271807,'Ethan Nwaneri',75,'RW','England','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/271807/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',3500000,5500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=271807;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(254117,'Maximilian Beier',81,'CAM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/254117/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=254117;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(80873,'Mathis Albert',66,'LM','United States','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/80873/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=80873;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(83751,'Luca Reggiani',67,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/83751/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1000000,1500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=83751;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(208333,'Emre Can',81,'CB','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/208333/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=208333;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(73016,'Filippo Mané',65,'CB','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/73016/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=73016;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(259633,'Giannis Konstantelias',79,'CAM','Greece','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/259633/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=259633;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(210772,'Patrick Drewes',71,'GK','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/210772/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=210772;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(72419,'Justin Lerma',66,'CAM','Ecuador','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/72419/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=72419;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(78577,'Mussa Kaba',62,'CDM','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/78577/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=78577;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(86362,'Enzo dos Santos',61,'CM','Luxembourg','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/86362/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=86362;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(266906,'Silas Ostrzinski',63,'GK','Germany','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/266906/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=22 AND p.sofifa_id=266906;

INSERT INTO public.teams(sofifa_id,name,crest_url,sofifa_revision,sofifa_updated_at) VALUES(73,'Paris Saint-Germain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/teams/73/402fa559e6660954de011c7ddecb136169ede9dfc739f7b3b9563ae1d8f510a8.png',270004,now());
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(240225,'Matvey Safonov',83,'GK','Russia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/240225/e69ab68dc13325f947d05b0118d12330a996fc7659ca75bc3f670dfb55f8d3ee.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=240225;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(235212,'Achraf Hakimi',88,'RB','Morocco','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/235212/8c0ebcfcac281e73e19f3520a7750e17ba201354ef7b4a28ab8835f0f06e8acc.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=235212;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(207865,'Marcos Aoás Corrêa',87,'CB','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/207865/30044ef62f2807e6f63363c1c572d19d1b78ceebd4faf5d28e529900270416b7.png',60000000,90000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=207865;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(256196,'Willian Pacho',89,'CB','Ecuador','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/256196/082cf34205171ff434897d15daa5a73d4c32e5e49d66c664ab8930c31f7dc296.png',85000000,127500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=256196;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(252145,'Nuno Alexandre Tavares Mendes',89,'LB','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/252145/42853f74dfca9d230847cf20fcaa5d096ecc2d7b739e21394b24e3e3862c099a.png',85000000,127500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=252145;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(272834,'João Pedro Gonçalves Neves',88,'CM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/272834/af333910c5227f982c473f2282907e53f1e06297e3d4816de6452d6ff661461e.png',70000000,105000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=272834;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(255253,'Vítor Machado Ferreira',90,'CM','Portugal','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/255253/7a2b17b9142567c7a5f17da3fc42ef74a376456a29ee77ee5325ec4685718a12.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=255253;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(226271,'Fabián Ruiz Peña',86,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/226271/1d6027fb527262318d17ef748fb21dfde66d78aa2bb448190000b60447afd2c7.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=226271;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(271421,'Désiré Doué',86,'RW','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/271421/be8cc85ac5e395fef42100ff7f27629f03ab28df508f51a06b3f868500566d70.png',50000000,75000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=271421;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(231443,'Ousmane Dembélé',90,'ST','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/231443/e7981b03b19e8a0893bb5a12b9b748da5ecadd88f174beb8924f535089f41856.png',100000000,150000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=231443;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(247635,'Khvicha Kvaratskhelia',89,'LW','Georgia','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/247635/24e418719ba87a7da7d1cf18fa78bfc13a5697da3bd17bf476e19c69ebc2c225.png',85000000,127500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=247635;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(270673,'Warren Zaïre-Emery',83,'CM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/270673/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',26000000,39000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=270673;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(264862,'Maghnes Akliouche',81,'CAM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/264862/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=264862;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(279709,'Lucas Lopes Beraldo',79,'CDM','Brazil','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/279709/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=279709;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(80674,'Pedro Fernández',73,'CM','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/80674/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',2000000,3000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=80674;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(200458,'Lucas Digne',80,'LB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/200458/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=200458;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(258781,'Illia Zabarnyi',80,'CB','Ukraine','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/258781/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=258781;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(251752,'Lucas Chevalier',80,'GK','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/251752/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',13000000,19500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=251752;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(258378,'Mika Godts',78,'LW','Belgium','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/258378/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',8000000,12000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=258378;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(241461,'Ferran Torres García',84,'ST','Spain','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/241461/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',32000000,48000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=241461;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(220814,'Lucas Hernández',81,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/220814/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',16000000,24000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=220814;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(70004,'Senny Mayulu',79,'CM','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/70004/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',10000000,15000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=70004;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(86857,'Alessandro Longoni',65,'GK','Italy','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/86857/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=86857;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(78549,'Quentin Ndjantou',70,'LW','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/78549/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',1500000,2500000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=78549;
INSERT INTO public.players(sofifa_id,name,ovr,position,country_name,headshot_url,price,clause,is_icon,sofifa_revision,sofifa_updated_at) VALUES(85652,'Dimitri Lucea',64,'CB','France','https://fczlwqgpjzghqdyjnyes.supabase.co/storage/v1/object/public/sofifa-assets/players/85652/a24361f71a2b7052eb974a6d9b1e9eeec6488c01d2e97508fc24317145fe1638.png',500000,1000000,false,270004,now());
INSERT INTO public.team_players(team_id,player_id) SELECT t.id,p.id FROM public.teams t,public.players p WHERE t.sofifa_id=73 AND p.sofifa_id=85652;
INSERT INTO public.sofifa_imports(revision,digest,team_count,player_count) VALUES(270004,'8019ac1eb6f77851e83ca5ed33c81da501b74d19b530b855c3dd5b7f2faca7fb',16,437);
DO $verify$ BEGIN
 IF (SELECT count(*) FROM public.teams)<>16 OR (SELECT count(*) FROM public.players)<>437 OR (SELECT count(*) FROM public.team_players)<>437 OR (SELECT count(*) FROM public.tournaments)<>0 THEN RAISE EXCEPTION 'Verificacion final fallo'; END IF;
 IF EXISTS(SELECT player_id FROM public.team_players GROUP BY player_id HAVING count(*)<>1) THEN RAISE EXCEPTION 'Jugador duplicado'; END IF;
END $verify$;
NOTIFY pgrst,'reload schema';
COMMIT;
SELECT 'OK' AS resultado,16 AS equipos,437 AS jugadores,437 AS relaciones,270004 AS revision;
-- Copiar el resultado como variable MERCATTO_GAME_TEAM_IDS en Vercel:
SELECT string_agg(id::text,',' ORDER BY sofifa_id) AS "MERCATTO_GAME_TEAM_IDS" FROM public.teams;
SELECT t.name,count(tp.player_id) AS jugadores FROM public.teams t JOIN public.team_players tp ON tp.team_id=t.id GROUP BY t.id,t.name ORDER BY t.name;
