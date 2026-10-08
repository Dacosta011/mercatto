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
