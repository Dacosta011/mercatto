-- Local baseline lacked the original slots visibility preference.
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS slots_enabled boolean NOT NULL DEFAULT false;
NOTIFY pgrst,'reload schema';
