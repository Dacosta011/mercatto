import { NextResponse } from 'next/server';
import { bearer, gameError, gameRpc } from '@/lib/game-server';
type Params = { params: Promise<{ code: string }> };
export async function GET(request: Request, { params }: Params) {
  try {
    const { code } = await params;
    return NextResponse.json(await gameRpc('game_state', { p_code: code, p_token: bearer(request) }), { headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return gameError(error); }
}
