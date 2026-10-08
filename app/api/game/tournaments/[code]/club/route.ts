import { NextResponse } from 'next/server';
import { bearer, gameError, gameRpc, jsonBody, requestKey, UUID } from '@/lib/game-server';
type Params = { params: Promise<{ code: string }> };
export async function POST(request: Request, { params }: Params) {
  try {
    const { code } = await params;
    const key = requestKey(request);
    const body = await jsonBody(request);
    if (typeof body.clubId !== 'string' || !UUID.test(body.clubId)) throw new Error('INVALID_BODY');
    return NextResponse.json(await gameRpc('game_choose_club', { p_code: code, p_token: bearer(request), p_club: body.clubId, p_key: key }));
  } catch (error) { return gameError(error); }
}
