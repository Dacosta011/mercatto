import { NextResponse } from 'next/server';
import { bearer, gameError, gameRpc, jsonBody, requestKey, UUID } from '@/lib/game-server';
type Params = { params: Promise<{ code: string }> };
const activity = ['vote_open','vote_close','vote','spin','spin_claim','spin_reject'];
const commands = ['configure','draw','release','league_start','lineup','result_submit','result_confirm','result_dispute','result_force','round_close','leave','replace','forfeit','season_next','pay_debt',...activity];
export async function GET(request: Request,{params}: Params) {
  try { const {code}=await params; return NextResponse.json(await gameRpc('game_competition_state',{p_code:code,p_token:bearer(request)}),{headers:{'Cache-Control':'no-store'}}); }
  catch(error){return gameError(error);}
}
export async function POST(request: Request,{params}: Params) {
  try {
    const {code}=await params, body=await jsonBody(request);
    if(typeof body.action!=='string'||!commands.includes(body.action)) throw new Error('INVALID_ACTION');
    const required:Record<string,string[]>={release:['playerId'],vote:['ballotId','playerId'],vote_close:['ballotId'],vote_open:['minutes','auctionMinutes'],spin_claim:['spinId'],spin_reject:['spinId'],lineup:['fixtureId'],result_submit:['fixtureId','homeGoals','awayGoals'],result_confirm:['fixtureId'],result_dispute:['fixtureId'],result_force:['fixtureId','homeGoals','awayGoals'],forfeit:['fixtureId'],replace:['memberId','clubId']};
    if((required[body.action]||[]).some(field=>!(field in body)))throw new Error('INVALID_BODY');
    for(const field of ['playerId','fixtureId','ballotId','spinId','memberId','clubId']) if(field in body && (typeof body[field]!=='string'||!UUID.test(body[field] as string))) throw new Error('INVALID_ID');
    for(const field of ['homeGoals','awayGoals','minSquad','maxSquad','dailyBasic','dailyPremium','rerolls','winterLimit','seasonIncome','spinFee','replacementDays','minutes','auctionMinutes','legs']) if(field in body && (typeof body[field]!=='number'||!Number.isSafeInteger(body[field])||body[field]<0)) throw new Error('INVALID_NUMBER');
    if('players' in body && (!Array.isArray(body.players)||body.players.length>60||body.players.some(p=>typeof p!=='string'||!UUID.test(p)))) throw new Error('INVALID_LINEUP');
    if('cards' in body && (!Array.isArray(body.cards)||body.cards.length>120||body.cards.some(c=>!c||typeof c!=='object'||typeof c.playerId!=='string'||!UUID.test(c.playerId)||!['yellow','red'].includes(c.kind)))) throw new Error('INVALID_CARDS');
    const {action,...payload}=body;
    return NextResponse.json(await gameRpc(activity.includes(action)?'game_activity_command':'game_competition_command',{p_code:code,p_token:bearer(request),p_key:requestKey(request),p_action:action,p_body:payload}),{headers:{'Cache-Control':'no-store'}});
  } catch(error){return gameError(error);}
}
