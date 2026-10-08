-- Additive bugfix; preserves catalogues and existing game history.
ALTER TABLE public.players ADD COLUMN IF NOT EXISTS salary bigint DEFAULT 0;
CREATE TABLE game.guests (
 member_id uuid PRIMARY KEY REFERENCES public.members(id) ON DELETE CASCADE,
 tournament_id uuid NOT NULL REFERENCES game.tournaments(id)
);
ALTER TABLE game.guests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON game.guests FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT ON game.guests TO service_role;

CREATE FUNCTION public.game_join_guest(p_code text,p_name text,p_token text,p_key uuid)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE tid uuid; mid uuid; old game.operations; result jsonb; payload jsonb;
BEGIN
 IF p_key IS NULL OR length(trim(coalesce(p_name,''))) NOT BETWEEN 1 AND 40 OR length(coalesce(p_token,''))<32 THEN RAISE EXCEPTION 'Invalid guest parameters'; END IF;
 SELECT t.id INTO tid FROM public.tournaments t JOIN game.tournaments g ON g.id=t.id WHERE t.code=upper(p_code) FOR UPDATE OF g;
 IF tid IS NULL THEN RAISE EXCEPTION 'Tournament not found'; END IF;
 payload:=jsonb_build_object('name',trim(p_name));
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key='guest:'||p_key;
 IF FOUND THEN IF old.payload<>payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF; RETURN old.result; END IF;
 IF NOT EXISTS(SELECT 1 FROM game.seasons WHERE tournament_id=tid AND ended_at IS NULL AND phase IN('league','finished')) THEN PERFORM game.rule_error('Guests require an active or finished league'); END IF;
 IF EXISTS(SELECT 1 FROM public.members WHERE tournament_id=tid AND lower(display_name)=lower(trim(p_name))) THEN RAISE EXCEPTION 'Display name already in use'; END IF;
 INSERT INTO public.members(tournament_id,display_name,member_token_hash) VALUES(tid,trim(p_name),encode(sha256(convert_to(p_token,'UTF8')),'hex')) RETURNING id INTO mid;
 INSERT INTO game.guests VALUES(mid,tid);
 INSERT INTO public.social_profiles(member_id,tournament_id,username) VALUES(mid,tid,trim(p_name));
 result:=jsonb_build_object('memberId',mid,'memberToken',p_token,'displayName',trim(p_name),'tournamentName',(SELECT name FROM public.tournaments WHERE id=tid),'code',upper(p_code),'isGuest',true);
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'guest_join','guest:'||p_key,payload,result);
 RETURN result;
END $$;
CREATE FUNCTION game.reject_guest_assignment() RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN IF EXISTS(SELECT 1 FROM game.guests WHERE member_id=NEW.member_id) THEN RAISE EXCEPTION 'Guests cannot manage clubs' USING ERRCODE='28000'; END IF; RETURN NEW; END $$;
CREATE TRIGGER reject_guest_assignment BEFORE INSERT OR UPDATE ON game.assignments FOR EACH ROW EXECUTE FUNCTION game.reject_guest_assignment();

ALTER FUNCTION public.game_state(text,text) RENAME TO game_state_before_guests;
CREATE FUNCTION public.game_state(p_code text,p_token text) RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE result jsonb; BEGIN
 result:=public.game_state_before_guests(p_code,p_token);
 RETURN result||jsonb_build_object('isGuest',EXISTS(SELECT 1 FROM game.guests WHERE member_id=(result->>'memberId')::uuid),'guestIds',(SELECT coalesce(jsonb_agg(member_id),'[]'::jsonb) FROM game.guests WHERE tournament_id=(result->>'id')::uuid));
END $$;

CREATE FUNCTION public.game_social_post(p_code text,p_token text,p_key uuid,p_content text,p_image text DEFAULT NULL,p_parent uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SET search_path='' AS $$
DECLARE mid uuid;tid uuid;old game.operations;payload jsonb;result jsonb;post_id uuid; BEGIN
 mid:=game.require_member(p_code,p_token);SELECT tournament_id INTO tid FROM public.members WHERE id=mid;
 PERFORM 1 FROM game.tournaments WHERE id=tid FOR UPDATE;
 IF p_key IS NULL OR length(coalesce(p_content,''))>2000 OR (length(trim(coalesce(p_content,'')))=0 AND p_image IS NULL) THEN RAISE EXCEPTION 'Invalid post'; END IF;
 IF p_image IS NOT NULL AND (length(p_image)>2800000 OR p_image !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$') THEN RAISE EXCEPTION 'Invalid image'; END IF;
 payload:=jsonb_build_object('content',p_content,'image',p_image,'parent',p_parent);
 SELECT * INTO old FROM game.operations WHERE tournament_id=tid AND idempotency_key='social-post:'||mid||':'||p_key;
 IF FOUND THEN IF old.payload<>payload THEN RAISE EXCEPTION 'Idempotency key reused with different payload'; END IF; RETURN old.result; END IF;
 IF p_parent IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.posts WHERE id=p_parent AND tournament_id=tid) THEN PERFORM game.rule_error('Post not found in tournament'); END IF;
 INSERT INTO public.posts(member_id,tournament_id,content,image_url,parent_id) VALUES(mid,tid,nullif(trim(p_content),''),p_image,p_parent) RETURNING id INTO post_id;
 result:=jsonb_build_object('postId',post_id);
 INSERT INTO game.operations(tournament_id,kind,idempotency_key,payload,result) VALUES(tid,'social_post_image','social-post:'||mid||':'||p_key,payload,result);
 RETURN result;
END $$;
ALTER TABLE public.push_subscriptions DROP CONSTRAINT IF EXISTS push_subscriptions_endpoint_key;
CREATE UNIQUE INDEX push_subscriptions_member_endpoint ON public.push_subscriptions(member_id,endpoint);
ALTER TABLE public.notifications ADD COLUMN push_attempted_at timestamptz;
ALTER TABLE public.notifications ADD COLUMN push_sent_at timestamptz;

REVOKE ALL ON FUNCTION public.game_join_guest(text,text,text,uuid),public.game_state(text,text),public.game_social_post(text,text,uuid,text,text,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.game_join_guest(text,text,text,uuid),public.game_state(text,text),public.game_social_post(text,text,uuid,text,text,uuid) TO service_role;
NOTIFY pgrst,'reload schema';
