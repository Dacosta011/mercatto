export interface GameClub {
  id: string;
  teamId: string;
  name: string;
  budget: number;
  reserved: number;
  memberId: string | null;
  manager: string | null;
  squad: { id: string; name: string; ovr: number; position: string | null; price: number; clause: number | null }[];
}
export interface GameState {
  id: string;
  name: string;
  code: string;
  memberId: string;
  season: number;
  clubs: GameClub[];
  members: { id: string; name: string }[];
}
export interface GameMarket {
  window: { id: string; kind: 'summer' | 'winter'; status: 'open' | 'closed' | 'expired'; closesAt: string; purchaseLimit: number; clauseProtectionLimit: number } | null;
  limits: { clubId: string; used: number; held: number; limit: number; iconsUsed: number; iconsHeld: number }[];
  auctionIcons: { id: string; name: string; ovr: number; minBid: number }[];
  auctions: { id: string; windowId: string; playerId: string; playerName: string; status: 'active' | 'expired' | 'settled' | 'unsold'; endsAt: string; minBid: number; highestBid: number; highestClubId: string | null; highestClub: string | null; bids: { id: number; clubId: string; club: string; amount: number; createdAt: string }[] }[];
  freePlayers: { id: string; name: string; ovr: number; price: number }[];
  clauseAttempts: { windowId: string; buyerClubId: string; buyer: string; seller: string; playerId: string; playerName: string; amount: number; outcome: 'accepted' | 'rejected'; createdAt: string }[];
  offers: { id: string; windowId: string; playerId: string; playerName: string; buyerClubId: string; sellerClubId: string; buyer: string; seller: string; amount: number; status: string; proposedAmount: number | null; proposedByClubId: string | null; revisions: { revision: number; authorClubId: string; amount: number }[] }[];
  transfers: { id: string; playerId: string; playerName: string; buyer: string; seller: string | null; amount: number; kind: string; createdAt: string }[];
  ledger: { id: number; amount: number; kind: string; createdAt: string }[];
}

export interface GameCompetition {
  enabled: boolean; phase: 'assignment'|'league'|'finished'; seasonId: string; round: number|null;
  rules: { min_squad:number; max_squad:number; daily_basic:number; daily_premium:number; rerolls:number; winter_limit:number; season_income:number; spin_fee:number; replacement_days:number }|null;
  seasons: {id:string;number:number;phase:string}[];
  rounds: {number:number;closed:boolean}[];
  fixtures: {id:string;seasonId:string;round:number;homeClubId:string;awayClubId:string;status:string;homeGoals:number|null;awayGoals:number|null;proposal:{homeGoals:number;awayGoals:number;cards:{playerId:string;kind:string}[]}|null;proposerClubId:string|null;postponeRequestedClubId?:string|null;reactivateRequestedClubId?:string|null;confirmedClubs:string[];lineups:{clubId:string;playerId:string;name:string;ovr:number;position:string|null;price:number;selected:boolean}[];cards:{playerId:string;kind:string}[];expenses:{clubId:string;playerId:string;kind:string;amount:number}[]}[];
  suspensions:{id:string;seasonId:string;playerId:string;matches:number;served:number;expired:boolean}[];
  releases:{playerId:string;clubId:string;windowId:string|null;refund:number;automatic:boolean;createdAt:string}[];
  daily:{clubId:string;tier:string;used:number}[];
  debts:{clubId:string;amount:number}[];
  departures:string[];entrants:{clubId:string;replacementDue:string|null}[];
  draws:{memberId:string;clubId:string;seasonId:string}[];
  spins:{id:string;clubId:string;playerId:string;status:string;fee:number;expiresAt:string}[];
  ballots:{id:string;windowId:string;status:string;endsAt:string;winner:string|null;auctionId:string|null;options:{playerId:string;name:string;votes:number}[];votedClubs:string[];electorate:number}[];
}
