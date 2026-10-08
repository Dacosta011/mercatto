-- Only this authenticated, tournament-scoped RPC may clear unfinished lineups.
-- Do not grant general DELETE privileges on frozen lineups to service_role.
ALTER FUNCTION public.game_fixture_schedule(text,text,uuid,uuid,text,boolean,boolean) SECURITY DEFINER;
NOTIFY pgrst,'reload schema';
