-- Catalogue membership is a single current club, independently of game contracts.
-- Intentionally fails on an unreconciled old catalogue instead of deleting duplicates.
CREATE UNIQUE INDEX team_players_single_owner ON public.team_players(player_id);
