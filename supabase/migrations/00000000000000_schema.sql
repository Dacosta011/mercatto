-- ============================================================================
-- Mercatto — Complete schema from production
-- ============================================================================

create table if not exists tournaments
(
    id                      uuid                     default gen_random_uuid() not null
        primary key,
    name                    text                                               not null,
    code                    text                                               not null
        unique,
    admin_token_hash        text                                               not null,
    status                  text                     default 'lobby'::text     not null,
    created_at              timestamp with time zone default now()             not null,
    rerolls_allowed         integer                  default 1                 not null,
    max_transfers           integer                  default 3                 not null,
    clause_protection       boolean                  default true              not null,
    clause_protection_limit integer                  default 1                 not null
);

grant delete, insert, references, select, trigger, truncate, update on tournaments to anon;
grant delete, insert, references, select, trigger, truncate, update on tournaments to authenticated;
grant delete, insert, references, select, trigger, truncate, update on tournaments to service_role;

create table if not exists members
(
    id                uuid                     default gen_random_uuid() not null
        primary key,
    tournament_id     uuid                                               not null
        references tournaments
            on delete cascade,
    display_name      text                                               not null,
    member_token_hash text                                               not null,
    created_at        timestamp with time zone default now()             not null,
    rerolls_used      integer                  default 0                 not null,
    budget            bigint,
    market_purchases  integer                  default 0                 not null,
    icon_slot_used    boolean                  default false             not null,
    budget_reserved   bigint                   default 0                 not null,
    unique (tournament_id, display_name)
);

create index if not exists idx_members_tournament
    on members (tournament_id);

grant delete, insert, references, select, trigger, truncate, update on members to anon;
grant delete, insert, references, select, trigger, truncate, update on members to authenticated;
grant delete, insert, references, select, trigger, truncate, update on members to service_role;

create table if not exists teams
(
    id        uuid default gen_random_uuid() not null
        primary key,
    name      text                           not null
        unique,
    crest_url text
);

grant delete, insert, references, select, trigger, truncate, update on teams to anon;
grant delete, insert, references, select, trigger, truncate, update on teams to authenticated;
grant delete, insert, references, select, trigger, truncate, update on teams to service_role;

create table if not exists players
(
    id             uuid                     default gen_random_uuid() not null
        primary key,
    name           text                                               not null,
    ovr            integer                                            not null,
    position       text,
    price          integer                                            not null,
    clause         integer,
    created_at     timestamp with time zone default now()             not null,
    country_name   text,
    country_code   text,
    card_image_url text,
    headshot_url   text,
    is_icon        boolean                  default false,
    constraint players_name_ovr_position_unique
        unique (name, ovr, position)
);

create index if not exists idx_players_ovr on players (ovr);
create index if not exists idx_players_country on players (country_code);
create index if not exists idx_players_position on players (position);

grant delete, insert, references, select, trigger, truncate, update on players to anon;
grant delete, insert, references, select, trigger, truncate, update on players to authenticated;
grant delete, insert, references, select, trigger, truncate, update on players to service_role;

create table if not exists assignments
(
    tournament_id uuid              not null
        references tournaments on delete cascade,
    member_id     uuid              not null
        references members on delete cascade,
    team_id       uuid              not null
        references teams,
    rerolls_used  integer default 0 not null,
    primary key (tournament_id, member_id),
    unique (tournament_id, team_id)
);

grant delete, insert, references, select, trigger, truncate, update on assignments to anon;
grant delete, insert, references, select, trigger, truncate, update on assignments to authenticated;
grant delete, insert, references, select, trigger, truncate, update on assignments to service_role;

create table if not exists member_roster
(
    tournament_id uuid                                   not null
        references tournaments on delete cascade,
    member_id     uuid                                   not null
        references members on delete cascade,
    player_id     uuid                                   not null
        references players on delete restrict,
    acquired_at   timestamp with time zone default now() not null,
    primary key (tournament_id, member_id, player_id)
);

create index if not exists idx_member_roster_member
    on member_roster (tournament_id, member_id);

grant delete, insert, references, select, trigger, truncate, update on member_roster to anon;
grant delete, insert, references, select, trigger, truncate, update on member_roster to authenticated;
grant delete, insert, references, select, trigger, truncate, update on member_roster to service_role;

create table if not exists listings
(
    id            uuid                     default gen_random_uuid() not null
        primary key,
    tournament_id uuid                                               not null
        references tournaments on delete cascade,
    seller_id     uuid                                               not null
        references members on delete cascade,
    player_id     uuid                                               not null
        references players,
    price         integer                                            not null,
    status        text                     default 'active'::text    not null,
    created_at    timestamp with time zone default now()             not null
);

create index if not exists idx_listings_tournament
    on listings (tournament_id);

grant delete, insert, references, select, trigger, truncate, update on listings to anon;
grant delete, insert, references, select, trigger, truncate, update on listings to authenticated;
grant delete, insert, references, select, trigger, truncate, update on listings to service_role;

create table if not exists market_sessions
(
    id                       uuid                     default gen_random_uuid() not null
        primary key,
    tournament_id            uuid
        unique
        references tournaments on delete cascade,
    status                   text                     default 'pending'::text   not null,
    current_round            integer                  default 1                 not null,
    total_rounds             integer                  default 3                 not null,
    started_at               timestamp with time zone,
    finished_at              timestamp with time zone,
    created_at               timestamp with time zone default now(),
    opens_at                 timestamp with time zone,
    closes_at                timestamp with time zone,
    duration_hours           integer                  default 24                not null,
    market_type              text                     default 'regular'::text   not null,
    winter_max_transfers     integer,
    winter_clause_protection boolean
);

grant delete, insert, references, select, trigger, truncate, update on market_sessions to anon;
grant delete, insert, references, select, trigger, truncate, update on market_sessions to authenticated;
grant delete, insert, references, select, trigger, truncate, update on market_sessions to service_role;

create table if not exists market_turns
(
    id           uuid default gen_random_uuid() not null
        primary key,
    session_id   uuid
        references market_sessions on delete cascade,
    round_num    integer                        not null,
    position     integer                        not null,
    member_id    uuid
        references members on delete cascade,
    status       text default 'pending'::text   not null,
    completed_at timestamp with time zone,
    unique (session_id, round_num, position)
);

grant delete, insert, references, select, trigger, truncate, update on market_turns to anon;
grant delete, insert, references, select, trigger, truncate, update on market_turns to authenticated;
grant delete, insert, references, select, trigger, truncate, update on market_turns to service_role;

create table if not exists market_transfers
(
    id             uuid                     default gen_random_uuid() not null
        primary key,
    session_id     uuid
        references market_sessions on delete cascade,
    turn_id        uuid
        references market_turns,
    buyer_id       uuid
        references members,
    seller_id      uuid
        references members,
    seller_team_id uuid
        references teams,
    player_id      uuid
        references players,
    transfer_type  text                                               not null,
    amount         bigint                   default 0                 not null,
    created_at     timestamp with time zone default now()
);

grant delete, insert, references, select, trigger, truncate, update on market_transfers to anon;
grant delete, insert, references, select, trigger, truncate, update on market_transfers to authenticated;
grant delete, insert, references, select, trigger, truncate, update on market_transfers to service_role;

create table if not exists market_offers
(
    id              uuid                     default gen_random_uuid() not null
        primary key,
    session_id      uuid
        references market_sessions on delete cascade,
    turn_id         uuid
        references market_turns,
    buyer_id        uuid
        references members,
    seller_id       uuid
        references members,
    player_id       uuid
        references players,
    amount          bigint                                             not null,
    status          text                     default 'pending'::text   not null,
    created_at      timestamp with time zone default now(),
    responded_at    timestamp with time zone,
    expires_at      timestamp with time zone,
    counter_amount  bigint,
    parent_offer_id uuid
        references market_offers
);

grant delete, insert, references, select, trigger, truncate, update on market_offers to anon;
grant delete, insert, references, select, trigger, truncate, update on market_offers to authenticated;
grant delete, insert, references, select, trigger, truncate, update on market_offers to service_role;

create table if not exists team_players
(
    team_id   uuid not null
        references teams on delete cascade,
    player_id uuid not null
        references players on delete cascade,
    primary key (team_id, player_id)
);

create index if not exists idx_team_players_team
    on team_players (team_id);

grant delete, insert, references, select, trigger, truncate, update on team_players to anon;
grant delete, insert, references, select, trigger, truncate, update on team_players to authenticated;
grant delete, insert, references, select, trigger, truncate, update on team_players to service_role;

create table if not exists league_sessions
(
    id               uuid                     default gen_random_uuid() not null
        primary key,
    tournament_id    uuid
        unique
        references tournaments on delete cascade,
    status           text                     default 'pending'::text   not null,
    current_matchday integer                  default 1                 not null,
    total_matchdays  integer                  default 0                 not null,
    started_at       timestamp with time zone,
    finished_at      timestamp with time zone,
    created_at       timestamp with time zone default now()
);

grant delete, insert, references, select, trigger, truncate, update on league_sessions to anon;
grant delete, insert, references, select, trigger, truncate, update on league_sessions to authenticated;
grant delete, insert, references, select, trigger, truncate, update on league_sessions to service_role;

create table if not exists fixtures
(
    id                      uuid                     default gen_random_uuid() not null
        primary key,
    session_id              uuid
        references league_sessions on delete cascade,
    matchday                integer                                            not null,
    home_member_id          uuid references members,
    away_member_id          uuid references members,
    status                  text                     default 'pending'::text   not null,
    home_confirmed          boolean                  default false             not null,
    away_confirmed          boolean                  default false             not null,
    pending_home_goals      integer,
    pending_away_goals      integer,
    pending_home_yellow     integer,
    pending_away_yellow     integer,
    pending_home_red        integer,
    pending_away_red        integer,
    result_submitter_id     uuid references members,
    home_goals              integer,
    away_goals              integer,
    home_yellow             integer                  default 0                 not null,
    away_yellow             integer                  default 0                 not null,
    home_red                integer                  default 0                 not null,
    away_red                integer                  default 0                 not null,
    started_at              timestamp with time zone,
    finished_at             timestamp with time zone,
    created_at              timestamp with time zone default now(),
    pending_cards           jsonb                    default '[]'::jsonb,
    postpone_requested_by   uuid references members,
    reactivate_requested_by uuid references members
);

grant delete, insert, references, select, trigger, truncate, update on fixtures to anon;
grant delete, insert, references, select, trigger, truncate, update on fixtures to authenticated;
grant delete, insert, references, select, trigger, truncate, update on fixtures to service_role;

create table if not exists matchday_rests
(
    id         uuid default gen_random_uuid() not null
        primary key,
    session_id uuid
        references league_sessions on delete cascade,
    matchday   integer                        not null,
    member_id  uuid references members,
    unique (session_id, matchday)
);

grant delete, insert, references, select, trigger, truncate, update on matchday_rests to anon;
grant delete, insert, references, select, trigger, truncate, update on matchday_rests to authenticated;
grant delete, insert, references, select, trigger, truncate, update on matchday_rests to service_role;

create table if not exists discipline
(
    id          uuid                     default gen_random_uuid() not null
        primary key,
    session_id  uuid
        references league_sessions on delete cascade,
    member_id   uuid references members,
    fixture_id  uuid references fixtures,
    card_type   text                                               not null,
    matchday    integer                                            not null,
    created_at  timestamp with time zone default now(),
    player_id   uuid references players,
    player_name text
);

grant delete, insert, references, select, trigger, truncate, update on discipline to anon;
grant delete, insert, references, select, trigger, truncate, update on discipline to authenticated;
grant delete, insert, references, select, trigger, truncate, update on discipline to service_role;

create table if not exists suspensions
(
    id                uuid                     default gen_random_uuid() not null
        primary key,
    session_id        uuid
        references league_sessions on delete cascade,
    member_id         uuid references members,
    reason            text                                               not null,
    from_matchday     integer                                            not null,
    matches_remaining integer                  default 1                 not null,
    created_at        timestamp with time zone default now(),
    player_id         uuid references players,
    player_name       text
);

grant delete, insert, references, select, trigger, truncate, update on suspensions to anon;
grant delete, insert, references, select, trigger, truncate, update on suspensions to authenticated;
grant delete, insert, references, select, trigger, truncate, update on suspensions to service_role;

create table if not exists icon_auctions
(
    id                   uuid                     default gen_random_uuid()       not null
        primary key,
    session_id           uuid                                                     not null
        references market_sessions on delete cascade,
    round_num            integer                                                  not null,
    phase                text                     default 'vote_activation'::text not null,
    presented_icon_ids   jsonb                    default '[]'::jsonb             not null,
    selected_icon_id     uuid references players,
    bidder_order         jsonb,
    current_bidder_index integer                  default 0,
    highest_bid          bigint                   default 0,
    highest_bidder_id    uuid references members,
    consecutive_passes   integer                  default 0,
    winner_id            uuid references members,
    final_amount         bigint,
    created_at           timestamp with time zone default now(),
    reroll_votes         jsonb                    default '[]'::jsonb,
    starts_at            timestamp with time zone,
    ends_at              timestamp with time zone,
    min_bid              bigint                   default 0                       not null,
    vote_ends_at         timestamp with time zone,
    candidate_ids        uuid[]                   default '{}'::uuid[],
    unique (session_id, round_num)
);

grant delete, insert, references, select, trigger, truncate, update on icon_auctions to anon;
grant delete, insert, references, select, trigger, truncate, update on icon_auctions to authenticated;
grant delete, insert, references, select, trigger, truncate, update on icon_auctions to service_role;

create table if not exists icon_activation_votes
(
    id         uuid                     default gen_random_uuid() not null
        primary key,
    auction_id uuid                                               not null
        references icon_auctions on delete cascade,
    member_id  uuid                                               not null
        references members on delete cascade,
    vote       boolean                                            not null,
    created_at timestamp with time zone default now(),
    unique (auction_id, member_id)
);

grant delete, insert, references, select, trigger, truncate, update on icon_activation_votes to anon;
grant delete, insert, references, select, trigger, truncate, update on icon_activation_votes to authenticated;
grant delete, insert, references, select, trigger, truncate, update on icon_activation_votes to service_role;

create table if not exists icon_selection_votes
(
    id         uuid                     default gen_random_uuid() not null
        primary key,
    auction_id uuid                                               not null
        references icon_auctions on delete cascade,
    member_id  uuid                                               not null
        references members on delete cascade,
    icon_id    uuid                                               not null
        references players,
    created_at timestamp with time zone default now(),
    unique (auction_id, member_id)
);

grant delete, insert, references, select, trigger, truncate, update on icon_selection_votes to anon;
grant delete, insert, references, select, trigger, truncate, update on icon_selection_votes to authenticated;
grant delete, insert, references, select, trigger, truncate, update on icon_selection_votes to service_role;

create table if not exists icon_bids
(
    id         uuid                     default gen_random_uuid() not null
        primary key,
    auction_id uuid                                               not null
        references icon_auctions on delete cascade,
    member_id  uuid                                               not null
        references members on delete cascade,
    amount     bigint                                             not null,
    passed     boolean                  default false             not null,
    created_at timestamp with time zone default now()
);

grant delete, insert, references, select, trigger, truncate, update on icon_bids to anon;
grant delete, insert, references, select, trigger, truncate, update on icon_bids to authenticated;
grant delete, insert, references, select, trigger, truncate, update on icon_bids to service_role;

create table if not exists lineups
(
    id         uuid                     default gen_random_uuid() not null
        primary key,
    member_id  uuid unique references members on delete cascade,
    formation  text                     default '4-3-3'::text     not null,
    slots      jsonb                    default '{}'::jsonb       not null,
    updated_at timestamp with time zone default now()
);

grant delete, insert, references, select, trigger, truncate, update on lineups to anon;
grant delete, insert, references, select, trigger, truncate, update on lineups to authenticated;
grant delete, insert, references, select, trigger, truncate, update on lineups to service_role;

create table if not exists notifications
(
    id            uuid                     default gen_random_uuid() not null
        primary key,
    member_id     uuid                                               not null
        references members on delete cascade,
    tournament_id uuid                                               not null
        references tournaments on delete cascade,
    type          text                                               not null,
    title         text                                               not null,
    body          text,
    metadata      jsonb                    default '{}'::jsonb,
    read          boolean                  default false             not null,
    created_at    timestamp with time zone default now()
);

create index if not exists idx_notifications_member
    on notifications (member_id asc, read asc, created_at desc);

grant delete, insert, references, select, trigger, truncate, update on notifications to anon;
grant delete, insert, references, select, trigger, truncate, update on notifications to authenticated;
grant delete, insert, references, select, trigger, truncate, update on notifications to service_role;

create table if not exists push_subscriptions
(
    id         uuid                     default gen_random_uuid() not null
        primary key,
    member_id  uuid                                               not null
        references members on delete cascade,
    endpoint   text                                               not null unique,
    p256dh     text                                               not null,
    auth       text                                               not null,
    created_at timestamp with time zone default now()
);

grant delete, insert, references, select, trigger, truncate, update on push_subscriptions to anon;
grant delete, insert, references, select, trigger, truncate, update on push_subscriptions to authenticated;
grant delete, insert, references, select, trigger, truncate, update on push_subscriptions to service_role;

create table if not exists icon_votes
(
    id         uuid                     default gen_random_uuid() not null
        primary key,
    auction_id uuid                                               not null
        references icon_auctions on delete cascade,
    member_id  uuid                                               not null
        references members on delete cascade,
    icon_id    uuid                                               not null,
    created_at timestamp with time zone default now(),
    unique (auction_id, member_id)
);

grant delete, insert, references, select, trigger, truncate, update on icon_votes to anon;
grant delete, insert, references, select, trigger, truncate, update on icon_votes to authenticated;
grant delete, insert, references, select, trigger, truncate, update on icon_votes to service_role;

create table if not exists social_profiles
(
    id            uuid                     default gen_random_uuid() not null
        primary key,
    member_id     uuid                                               not null
        references members on delete cascade,
    tournament_id uuid                                               not null
        references tournaments on delete cascade,
    username      text                                               not null
        constraint social_profiles_username_check
            check (char_length(TRIM(BOTH FROM username)) >= 2),
    photo_url     text,
    created_at    timestamp with time zone default now(),
    updated_at    timestamp with time zone default now(),
    unique (member_id, tournament_id)
);

grant delete, insert, references, select, trigger, truncate, update on social_profiles to anon;
grant delete, insert, references, select, trigger, truncate, update on social_profiles to authenticated;
grant delete, insert, references, select, trigger, truncate, update on social_profiles to service_role;

create table if not exists posts
(
    id            uuid                     default gen_random_uuid() not null
        primary key,
    member_id     uuid                                               not null
        references members on delete cascade,
    tournament_id uuid                                               not null
        references tournaments on delete cascade,
    content       text,
    image_url     text,
    created_at    timestamp with time zone default now(),
    parent_id     uuid references posts on delete cascade,
    constraint content_or_image
        check ((content IS NOT NULL) OR (image_url IS NOT NULL))
);

create index if not exists idx_posts_parent_id on posts (parent_id);

grant delete, insert, references, select, trigger, truncate, update on posts to anon;
grant delete, insert, references, select, trigger, truncate, update on posts to authenticated;
grant delete, insert, references, select, trigger, truncate, update on posts to service_role;

create table if not exists post_likes
(
    id         uuid                     default gen_random_uuid() not null
        primary key,
    post_id    uuid                                               not null
        references posts on delete cascade,
    member_id  uuid                                               not null
        references members on delete cascade,
    created_at timestamp with time zone default now(),
    unique (post_id, member_id)
);

grant delete, insert, references, select, trigger, truncate, update on post_likes to anon;
grant delete, insert, references, select, trigger, truncate, update on post_likes to authenticated;
grant delete, insert, references, select, trigger, truncate, update on post_likes to service_role;

-- Realtime subscriptions
alter publication supabase_realtime add table fixtures;
alter publication supabase_realtime add table league_sessions;
alter publication supabase_realtime add table suspensions;
alter publication supabase_realtime add table notifications;
alter publication supabase_realtime add table icon_auctions;
alter publication supabase_realtime add table icon_activation_votes;
alter publication supabase_realtime add table icon_selection_votes;
alter publication supabase_realtime add table icon_bids;
alter publication supabase_realtime add table icon_votes;
