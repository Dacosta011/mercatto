import { NextResponse } from 'next/server';
import { bearer, gameError, gameRpc, requestKey } from '@/lib/game-server';
type Params = { params: Promise<{ code: string }> };
export async function POST(request: Request, { params }: Params) {
  try {
    const { code } = await params;
    return NextResponse.json(await gameRpc('game_next_season', { p_code: code, p_token: bearer(request), p_key: requestKey(request) }));
  } catch (error) { return gameError(error); }
}
