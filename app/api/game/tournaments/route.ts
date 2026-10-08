import { NextResponse } from 'next/server';
import { randomUUID } from 'node:crypto';
import { gameError, gameRpc, jsonBody, requestKey, UUID, localGameClient } from '@/lib/game-server';

export async function POST(request: Request) {
  try {
    const key = requestKey(request);
    const body = await jsonBody(request);
    let teams = process.env.MERCATTO_GAME_TEAM_IDS?.split(',').filter(Boolean) || [];
    if (teams.length === 0 && process.env.MERCATTO_GAME_MODEL === 'clubs') {
      const selected=[1,5,9,10,11,18,243,241,240,45,44,47,48,21,22,73];
      const {data,error}=await localGameClient().from('teams').select('id,sofifa_id').in('sofifa_id',selected);
      if(error)throw error;
      if(data?.length!==selected.length)throw new Error('LOCAL_GAME_CONFIG');
      teams=data.map(t=>t.id);
    }
    let freePlayers = process.env.MERCATTO_GAME_FREE_PLAYER_IDS?.split(',').filter(Boolean) || [];
    if(freePlayers.length===0){
      const {data,error}=await localGameClient().from('players').select('id').eq('is_icon',true);
      if(error)throw error;
      freePlayers=(data||[]).map(p=>p.id);
    }
    if (teams.length === 0 || [...teams, ...freePlayers].some(id => !UUID.test(id))) throw new Error('LOCAL_GAME_CONFIG');
    if (typeof body.name !== 'string' || typeof body.displayName !== 'string') throw new Error('INVALID_BODY');
    if ('complete' in body && typeof body.complete !== 'boolean') throw new Error('INVALID_BODY');
    const settings: Record<string,number> = {};
    for (const field of ['rerolls','maxTransfers','clauseProtection']) if (field in body) {
      const value=body[field];
      if (typeof value!=='number'||!Number.isSafeInteger(value)||value<(field==='maxTransfers'?1:0)||value>10) throw new Error('INVALID_NUMBER');
      settings[field]=value;
    }
    const data = await gameRpc('game_create_configured', {
      p_key: key, p_name: body.name, p_display_name: body.displayName,
      p_admin_token: randomUUID(), p_member_token: randomUUID(), p_teams: teams, p_free_players: freePlayers,p_complete:body.complete!==false,p_settings:settings,
    });
    return NextResponse.json(data, { status: 201, headers: { 'Cache-Control': 'no-store' } });
  } catch (error) { return gameError(error); }
}
