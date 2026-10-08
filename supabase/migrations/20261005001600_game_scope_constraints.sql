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
