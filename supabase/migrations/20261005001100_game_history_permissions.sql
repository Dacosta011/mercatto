-- Restore append-only grants after additive competition tables were installed.
REVOKE UPDATE ON game.clause_attempts,game.offer_revisions,game.auction_bids,
 game.lineups,game.lineup_confirmations,game.cards,game.suspension_servings,game.releases,
 game.daily_claims,game.draws,game.expenses,game.departures,game.ballot_options,game.electorate,game.votes FROM service_role;
