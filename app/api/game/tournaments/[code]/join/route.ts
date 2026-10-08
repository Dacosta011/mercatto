import { NextResponse } from 'next/server';
import { randomUUID } from 'node:crypto';
import { gameError, gameRpc, jsonBody, requestKey } from '@/lib/game-server';
type Params = { params: Promise<{ code: string }> };
export async function POST(request: Request, { params }: Params) {
  try {
    const { code } = await params;
    const key = requestKey(request);
    const body = await jsonBody(request);
    if (typeof body.displayName !== 'string') throw new Error('INVALID_BODY');
    const joined=await gameRpc('game_join_tournament', { p_code: code, p_name: body.displayName, p_key: key, p_token: randomUUID() });
    const state=await gameRpc('game_state',{p_code:joined.code,p_token:joined.memberToken});
    return NextResponse.json({...joined,tournamentName:state.name,displayName:state.members.find((m:{id:string})=>m.id===joined.memberId)?.name}, { status: 201, headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return gameError(error); }
}
