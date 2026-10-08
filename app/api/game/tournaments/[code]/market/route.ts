import { NextResponse } from 'next/server';
import { bearer, gameError, gameRpc, jsonBody, requestKey, UUID } from '@/lib/game-server';
type Params = { params: Promise<{ code: string }> };
export async function GET(request: Request, { params }: Params) {
  try {
    const { code } = await params;
    return NextResponse.json(await gameRpc('game_market_state', { p_code: code, p_token: bearer(request) }), { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return gameError(error); }
}
export async function POST(request: Request, { params }: Params) {
  try {
    const { code } = await params;
    const body = await jsonBody(request);
    const action = body.action;
    if (typeof action !== 'string' || !['open','close','offer','accept','reject','cancel','sign','counter','clause','auction_open','auction_bid'].includes(action)) throw new Error('INVALID_ACTION');
    const player = ['offer','sign','clause','auction_open'].includes(action) ? body.playerId : null;
    const offer = ['accept','reject','cancel','counter'].includes(action) ? body.offerId : null;
    if (player !== null && (typeof player !== 'string' || !UUID.test(player))) throw new Error('INVALID_PLAYER');
    if (offer !== null && (typeof offer !== 'string' || !UUID.test(offer))) throw new Error('INVALID_OFFER');
    if (['offer','counter','auction_bid'].includes(action) && (typeof body.amount !== 'number' || !Number.isSafeInteger(body.amount) || body.amount <= 0)) throw new Error('INVALID_AMOUNT');
    if (action === 'auction_open' && (typeof body.minutes !== 'number' || !Number.isInteger(body.minutes) || body.minutes < 1 || body.minutes > 1440)) throw new Error('INVALID_SETTINGS');
    if (action === 'auction_bid' && (typeof body.auctionId !== 'string' || !UUID.test(body.auctionId))) throw new Error('INVALID_AUCTION');
    if (action === 'open' && (!['summer','winter'].includes(String(body.kind)) || typeof body.minutes !== 'number' || !Number.isInteger(body.minutes) || body.minutes < 1 || body.minutes > 1440)) throw new Error('INVALID_SETTINGS');
    if (action === 'clause') return NextResponse.json(await gameRpc('game_pay_clause', {
      p_code: code, p_token: bearer(request), p_key: requestKey(request), p_player: player,
    }), { headers: { 'Cache-Control': 'no-store' } });
    if (['auction_open','auction_bid'].includes(action)) return NextResponse.json(await gameRpc('game_auction_command', {
      p_code: code, p_token: bearer(request), p_key: requestKey(request), p_action: action,
      p_player: player, p_auction: action==='auction_bid' ? body.auctionId : null,
      p_amount: action==='auction_bid' ? body.amount : null, p_minutes: action==='auction_open' ? body.minutes : null,
    }), { headers: { 'Cache-Control': 'no-store' } });
    return NextResponse.json(await gameRpc('game_market_command', {
      p_code: code, p_token: bearer(request), p_key: requestKey(request), p_action: action,
      p_player: player, p_offer: offer, p_amount: ['offer','counter'].includes(action) ? body.amount : null,
      p_kind: action === 'open' ? body.kind : null, p_minutes: action === 'open' ? body.minutes : null,
    }), { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return gameError(error); }
}
