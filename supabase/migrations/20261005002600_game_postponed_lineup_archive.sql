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
