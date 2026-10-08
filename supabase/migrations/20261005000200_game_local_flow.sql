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
