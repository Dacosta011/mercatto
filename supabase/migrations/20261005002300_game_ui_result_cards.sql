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
