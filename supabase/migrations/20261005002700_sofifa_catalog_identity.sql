-- Stable external identity replaces name/rating/position as the import key.
ALTER TABLE public.players ADD COLUMN sofifa_id bigint UNIQUE CHECK(sofifa_id>0),
 ADD COLUMN sofifa_revision integer, ADD COLUMN sofifa_updated_at timestamptz;
ALTER TABLE public.teams ADD COLUMN sofifa_id bigint UNIQUE CHECK(sofifa_id>0),
 ADD COLUMN sofifa_revision integer, ADD COLUMN sofifa_updated_at timestamptz;
ALTER TABLE public.players DROP CONSTRAINT players_name_ovr_position_unique;
CREATE TABLE public.sofifa_imports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), revision integer NOT NULL,
 digest text NOT NULL UNIQUE, imported_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 team_count integer NOT NULL, player_count integer NOT NULL
);
ALTER TABLE public.sofifa_imports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.sofifa_imports FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.sofifa_imports TO service_role;
NOTIFY pgrst,'reload schema';
