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
