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
