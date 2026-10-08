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
