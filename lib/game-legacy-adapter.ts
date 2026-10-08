import 'server-only';
import { NextResponse } from 'next/server';
import { gameRpc, gameError, bearer, requestKey, localGameClient, UUID } from './game-server';
import type { GameState, GameMarket, GameCompetition, GameClub } from './game-types';

// This boundary translates the original UI contracts; economic writes remain RPCs.
// Raw compatibility records mirror Postgres JSON, while core state stays typed.
/* eslint-disable @typescript-eslint/no-explicit-any */
type Snapshot={state:GameState;market:GameMarket;competition:GameCompetition;meta:any;assets:any[];clubs:any[];windows:any[];transfers:any[];assignments:any[];seasons:any[];draft:any;votes:any[]};
const json=(value:unknown,status=200)=>NextResponse.json(value,{status,headers:{'Cache-Control':'no-store'}});
const reject=(message:string,status=409)=>json({error:message},status);
const id=(value:unknown)=>{if(typeof value!=='string'||!UUID.test(value))throw new Error('INVALID_ID');return value;};
const number=(value:unknown)=>{if(typeof value!=='number'||!Number.isSafeInteger(value)||value<0)throw new Error('INVALID_NUMBER');return value;};

export function legacyView(d:Snapshot){
 const {state:s,market:m,competition:c}=d;
 const mine=s.clubs.find(cl=>cl.memberId===s.memberId);
 const asset=(pid:string)=>d.assets.find(p=>p.player_id===pid);
 const club=(cid:string)=>s.clubs.find(cl=>cl.id===cid);
 const crest=(cid:string)=>d.clubs.find(cl=>cl.id===cid)?.crest_url??null;
 const status=c.phase==='finished'?'complete':c.phase==='league'?'league':m.window?.status==='open'?'market':'lobby';
 const team=(cl:GameClub)=>({id:cl.teamId,clubId:cl.id,name:cl.name,crestUrl:crest(cl.id),budget:cl.budget,budgetReserved:cl.reserved,squadValue:cl.squad.reduce((v,p)=>v+p.price,0)});
 const manager=(cid:string,seasonId=c.seasonId)=>{
  const cl=club(cid),assignment=d.assignments.find(a=>a.club_id===cid&&a.season_id===seasonId);
  const mid=seasonId===c.seasonId?cl?.memberId:assignment?.member_id;
  return {id:mid||cid,displayName:s.members.find(mm=>mm.id===mid)?.name||'Sin administrador',teamName:cl?.name||'',crestUrl:crest(cid)};
 };
 const remaining=(pid:string)=>c.suspensions.filter(a=>a.playerId===pid&&a.seasonId===c.seasonId&&!a.expired).reduce((n,a)=>n+Math.max(0,a.matches-a.served),0);
 const player=(p:any)=>({...p,position:p.position||'',headshotUrl:asset(p.id)?.headshot_url??null,countryName:'',suspended:remaining(p.id),yellowCards:c.fixtures.filter(f=>f.seasonId===c.seasonId).flatMap(f=>f.cards).filter(card=>card.playerId===p.id&&card.kind==='yellow').length});
 const fixtures=c.fixtures.map(f=>{
  const home=manager(f.homeClubId,f.seasonId),away=manager(f.awayClubId,f.seasonId);
  const cards=(list:{playerId:string;kind:string}[],cid:string,kind:string)=>list.filter(card=>card.kind===kind&&f.lineups.some(l=>l.clubId===cid&&l.playerId===card.playerId)).length;
  return {id:f.id,matchday:f.round,seasonId:f.seasonId,status:({scheduled:'pending',playing:'in_progress',postponed:'postponed',finished:'finished',forfeit:'finished'} as any)[f.status],homeMember:home,awayMember:away,homeConfirmed:f.confirmedClubs.includes(f.homeClubId),awayConfirmed:f.confirmedClubs.includes(f.awayClubId),homeGoals:f.homeGoals,awayGoals:f.awayGoals,homeYellow:cards(f.cards,f.homeClubId,'yellow'),awayYellow:cards(f.cards,f.awayClubId,'yellow'),homeRed:cards(f.cards,f.homeClubId,'red'),awayRed:cards(f.cards,f.awayClubId,'red'),resultSubmitterId:f.proposerClubId?manager(f.proposerClubId,f.seasonId).id:null,pendingHomeGoals:f.proposal?.homeGoals??null,pendingAwayGoals:f.proposal?.awayGoals??null,pendingCards:(f.proposal?.cards||[]).map(card=>({playerId:card.playerId,cardType:card.kind,playerName:f.lineups.find(l=>l.playerId===card.playerId)?.name||'',memberId:manager(f.lineups.find(l=>l.playerId===card.playerId)?.clubId||'',f.seasonId).id})),pendingHomeYellow:cards(f.proposal?.cards||[],f.homeClubId,'yellow'),pendingAwayYellow:cards(f.proposal?.cards||[],f.awayClubId,'yellow'),pendingHomeRed:cards(f.proposal?.cards||[],f.homeClubId,'red'),pendingAwayRed:cards(f.proposal?.cards||[],f.awayClubId,'red'),startedAt:null,finishedAt:null,postponeRequestedBy:f.postponeRequestedClubId?manager(f.postponeRequestedClubId,f.seasonId).id:null,reactivateRequestedBy:f.reactivateRequestedClubId?manager(f.reactivateRequestedClubId,f.seasonId).id:null};
 });
 const standings=(seasonId:string)=>s.clubs.filter(cl=>c.fixtures.some(f=>f.seasonId===seasonId&&[f.homeClubId,f.awayClubId].includes(cl.id))).map(cl=>{
  let played=0,wins=0,draws=0,losses=0,gf=0,ga=0;
  for(const f of c.fixtures.filter(f=>f.seasonId===seasonId&&['finished','forfeit'].includes(f.status)&&[f.homeClubId,f.awayClubId].includes(cl.id))){played++;const g=f.homeClubId===cl.id?f.homeGoals!:f.awayGoals!,a=f.homeClubId===cl.id?f.awayGoals!:f.homeGoals!;gf+=g;ga+=a;if(g>a)wins++;else if(g===a)draws++;else losses++;}
  const member=manager(cl.id,seasonId);return {memberId:member.id,displayName:member.displayName,teamName:cl.name,played,wins,draws,losses,gf,ga,gd:gf-ga,points:wins*3+draws};
 }).sort((a,b)=>b.points-a.points||b.gd-a.gd||b.gf-a.gf||a.teamName.localeCompare(b.teamName));
 const current=fixtures.filter(f=>f.seasonId===c.seasonId),round=c.round||Math.max(1,...current.map(f=>f.matchday));
 const currentFixtures=current.filter(f=>f.matchday===round);
 const window=(w:any)=>({id:w.id,status:w.status==='open'?'active':'finished',marketType:w.kind==='winter'?'winter':'regular',startedAt:w.opens_at,opensAt:w.opens_at,finishedAt:w.closed_at,closesAt:w.closes_at,durationHours:(Date.parse(w.closes_at)-Date.parse(w.opens_at))/3600000});
 const transfer=(t:any)=>({id:t.id,transferType:t.kind,amount:t.amount,createdAt:t.created_at,buyerId:manager(t.buyer_club_id).id,sellerId:t.seller_club_id?manager(t.seller_club_id).id:null,buyerName:manager(t.buyer_club_id).displayName,sellerName:t.seller_club_id?manager(t.seller_club_id).displayName:'Libre',buyerTeamName:club(t.buyer_club_id)?.name,sellerTeamName:club(t.seller_club_id)?.name||'Libre',playerName:asset(t.player_id)?.name||'',playerId:t.player_id});
 const purchases=(cid:string)=>d.transfers.filter(t=>t.window_id===m.window?.id&&t.buyer_club_id===cid&&['offer','clause'].includes(t.kind)).length;
 const limit=m.limits.find(l=>l.clubId===mine?.id);
 const offers=m.offers.filter(o=>o.status==='pending').map(o=>({id:o.id,buyerId:manager(o.buyerClubId).id,buyerName:o.buyer,sellerId:manager(o.sellerClubId).id,sellerName:o.seller,playerId:o.playerId,playerName:o.playerName,playerOvr:asset(o.playerId)?.ovr||0,playerPosition:asset(o.playerId)?.position||'',playerHeadshot:asset(o.playerId)?.headshot_url||null,playerPrice:asset(o.playerId)?.reference_price||0,playerClause:asset(o.playerId)?.reference_clause||0,amount:o.proposedAmount??o.amount,expiresAt:m.window?.closesAt||null,counterAmount:null,parentOfferId:null,createdAt:d.windows.find(w=>w.id===o.windowId)?.opens_at||'',responder:manager(!o.proposedByClubId||o.proposedByClubId===o.buyerClubId?o.sellerClubId:o.buyerClubId).id}));
 const icon=(pid:string)=>({id:pid,name:asset(pid)?.name||'',ovr:asset(pid)?.ovr||0,position:asset(pid)?.position||'',nation:'',headshotUrl:asset(pid)?.headshot_url||null});
 const auctions:any[]=m.auctions.map(a=>({id:a.id,phase:['active','expired'].includes(a.status)?'active':'finished',startsAt:d.windows.find(w=>w.id===a.windowId)?.opens_at||null,endsAt:a.endsAt,voteEndsAt:null,minBid:a.minBid,highestBid:a.highestBid,highestBidderId:a.highestClubId?manager(a.highestClubId).id:null,highestBidderName:a.highestClubId?manager(a.highestClubId).displayName:null,winnerId:a.status==='settled'&&a.highestClubId?manager(a.highestClubId).id:null,winnerName:a.status==='settled'?a.highestClub:null,finalAmount:a.status==='settled'?a.highestBid:null,icon:icon(a.playerId),candidates:[],voteCounts:{},myVoteIconId:null,totalMembers:s.clubs.filter(cl=>cl.memberId).length,totalVotes:0,isMyBid:a.highestClubId===mine?.id,timeRemainingMs:Math.max(0,Date.parse(a.endsAt)-Date.now()),voteTimeRemainingMs:null}));
 for(const b of c.ballots.filter(b=>b.status==='open'))auctions.unshift({id:b.id,phase:'voting',startsAt:null,endsAt:null,voteEndsAt:b.endsAt,minBid:5000000,highestBid:0,highestBidderId:null,highestBidderName:null,winnerId:null,winnerName:null,finalAmount:null,icon:null,candidates:b.options.map(o=>icon(o.playerId)),voteCounts:Object.fromEntries(b.options.map(o=>[o.playerId,o.votes])),myVoteIconId:d.votes.find(v=>v.ballot_id===b.id)?.player_id||null,totalMembers:b.electorate,totalVotes:b.votedClubs.length,isMyBid:false,timeRemainingMs:null,voteTimeRemainingMs:Math.max(0,Date.parse(b.endsAt)-Date.now())});
 return {s,m,c,mine,asset,club,crest,team,manager,player,fixtures,current,currentFixtures,round,window,transfer,standings,auctions,icon,status,limit,
 tournament:{id:s.id,name:s.name,code:s.code,status,createdAt:d.meta.createdAt,currentSeason:s.season,lastLeagueFinished:c.phase==='finished',maxTransfers:d.meta.maxTransfers,clauseProtection:d.meta.clauseProtection,slotMachinePrice:c.rules?.spin_fee,slotsEnabled:d.meta.slotsEnabled,myMemberId:s.memberId,marketOpen:m.window?.status==='open',members:s.members.filter(mm=>!c.departures.includes(mm.id)).map(mm=>{const cl=s.clubs.find(cl=>cl.memberId===mm.id);return{id:mm.id,displayName:mm.name,budget:cl?.budget??null,team:cl?team(cl):null};})},
 league:{status:c.phase==='assignment'?'pending':c.phase==='finished'?'finished':'active',session:current.length?{id:c.seasonId,currentMatchday:round,totalMatchdays:Math.max(...current.map(f=>f.matchday))}:null,tournamentName:s.name,isAdmin:d.meta.isAdmin,myMemberId:s.memberId,currentFixtures,allFixtures:current,restMember:s.clubs.filter(cl=>current.some(f=>[f.homeMember.id,f.awayMember.id].includes(manager(cl.id).id))).filter(cl=>!currentFixtures.some(f=>[f.homeMember.id,f.awayMember.id].includes(manager(cl.id).id))).map(cl=>manager(cl.id))[0]||null,myDiscipline:{yellows:0,reds:0,suspended:false,yellowsToSuspension:3,suspendedPlayers:mine?.squad.filter(p=>remaining(p.id)>0).map(p=>({playerName:p.name,reason:'Sanción pendiente',matchesRemaining:remaining(p.id)}))||[]},currentMatchdayFinished:currentFixtures.every(f=>f.status==='finished'),table:standings(c.seasonId),discipline:s.clubs.flatMap(cl=>cl.squad.map(p=>{const pp=player(p),member=manager(cl.id);return{playerId:p.id,playerName:p.name,memberId:member.id,displayName:member.displayName,teamName:cl.name,yellows:pp.yellowCards,reds:c.fixtures.filter(f=>f.seasonId===c.seasonId).flatMap(f=>f.cards).filter(card=>card.playerId===p.id&&card.kind==='red').length,suspended:pp.suspended>0,yellowsToSuspension:3-pp.yellowCards%3};})).filter(p=>p.yellows||p.reds||p.suspended)},
 market:{status:m.window?(m.window.status==='open'?'active':'finished'):'pending',session:d.windows[0]?window(d.windows[0]):null,timer:{closesAt:m.window?.closesAt||null,timeRemainingMs:m.window?Math.max(0,Date.parse(m.window.closesAt)-Date.now()):null,isClosingSoon:false,isUrgent:false},myStatus:{memberId:s.memberId,budget:mine?.budget||0,budgetReserved:mine?.reserved||0,purchasesUsed:limit?.used??(mine?purchases(mine.id):0),maxPurchases:limit?.limit||d.meta.maxTransfers,iconSlotUsed:!!limit?.iconsUsed,myTeamId:mine?.teamId||null,myTeamName:mine?.name||null,myTeamCrestUrl:mine?crest(mine.id):null,pendingIncoming:offers.filter(o=>o.responder===s.memberId).length,pendingOutgoing:offers.filter(o=>o.buyerId===s.memberId&&o.responder!==s.memberId).length},availablePlayers:s.clubs.filter(cl=>cl.id!==mine?.id&&cl.memberId).flatMap(cl=>cl.squad.filter(p=>!asset(p.id)?.is_icon).map(p=>({playerId:p.id,playerName:p.name,headshotUrl:asset(p.id)?.headshot_url||null,ovr:p.ovr,position:p.position||'',price:p.price,clause:p.clause||0,isIcon:asset(p.id)?.is_icon||false,teamId:cl.teamId,teamName:cl.name,teamCrestUrl:crest(cl.id),ownerId:cl.memberId,ownerName:cl.manager,clauseProtected:!!m.window?.clauseProtectionLimit&&m.clauseAttempts.filter(a=>a.windowId===m.window?.id&&a.seller===cl.name&&a.outcome==='accepted').length>=m.window.clauseProtectionLimit,rejectedByMe:m.clauseAttempts.some(a=>a.playerId===p.id&&a.buyerClubId===mine?.id&&a.windowId===m.window?.id&&a.outcome==='rejected'),inNegotiation:m.offers.some(o=>o.playerId===p.id&&o.status==='pending')}))),myIncomingOffers:offers.filter(o=>o.responder===s.memberId),myOutgoingOffers:offers.filter(o=>o.buyerId===s.memberId&&o.responder!==s.memberId),recentTransfers:d.transfers.filter(t=>t.window_id===m.window?.id).map(transfer),clauseProtectionEnabled:m.window?.clauseProtectionLimit??d.meta.clauseProtection,unreadNotifications:0,league:{totalMatchdays:c.rounds.length},allMembers:s.clubs.filter(cl=>cl.memberId).map(cl=>({id:cl.memberId,displayName:cl.manager,teamName:cl.name,teamCrestUrl:crest(cl.id),purchasesUsed:m.limits.find(l=>l.clubId===cl.id)?.used??purchases(cl.id),clausesUsed:m.clauseAttempts.filter(a=>a.buyerClubId===cl.id&&a.windowId===m.window?.id&&a.outcome==='accepted').length}))}
 };
}

export async function handleLegacyGame(request:Request,parts:string[]){
 try{
 const [code,...tail]=parts,route=tail.join('/'),method=request.method,url=new URL(request.url);
 const token=bearer(request),member=request.headers.get('X-Mercatto-Member')||token;
 const snapshot=()=>gameRpc('game_ui_snapshot',{p_code:code,p_token:member,p_admin_token:request.headers.get('X-Mercatto-Admin')});
 const body=method==='GET'||method==='HEAD'?{}:await request.json().catch(()=>({}));
 const key=method==='GET'?null:requestKey(request);
 const competition=(action:string,payload:any={})=>gameRpc('game_competition_command',{p_code:code,p_token:token,p_key:key,p_action:action,p_body:payload});
 const activity=(action:string,payload:any={})=>gameRpc('game_activity_command',{p_code:code,p_token:token,p_key:key,p_action:action,p_body:payload});
 const ui=(action:string,payload:any={})=>gameRpc('game_ui_command',{p_code:code,p_token:token,p_key:key,p_action:action,p_body:payload});
 const market=(action:string,args:any={})=>gameRpc('game_market_command',{p_code:code,p_token:token,p_key:key,p_action:action,...args});
 if(method!=='GET'){
  if(route==='market/start')return json(await ui('market_open',body));
  if(route==='market/close')return json(await market('close'));
  if(route==='market/clause'){const result=await gameRpc('game_pay_clause',{p_code:code,p_token:token,p_key:key,p_player:id(body.playerId)});return json({...result,rejected:result.outcome==='rejected'});}
  if(route==='market/offer')return json(await market('offer',{p_player:id(body.playerId),p_amount:number(body.amount)}));
  if(tail[0]==='market'&&tail[1]==='offer'&&tail[2]){const action=method==='DELETE'?'cancel':body.action;if(!['accept','reject','counter','cancel'].includes(action))throw new Error('INVALID_ACTION');return json(await market(action,{p_offer:id(tail[2]),...(action==='counter'?{p_amount:number(body.counterAmount)}:{})}));}
  if(tail[0]==='league'&&tail[1]==='fixtures'&&['postpone','reactivate'].includes(tail[3])&&['POST','DELETE'].includes(method))return json(await gameRpc('game_fixture_schedule',{p_code:code,p_token:token,p_key:key,p_fixture:id(tail[2]),p_action:tail[3],p_cancel:method==='DELETE',p_force:body.force===true}));
  if(route==='league/start')return json(await competition('league_start',{legs:2}));
  if(route==='league/close-matchday')return json(await competition('round_close'));
  if(route==='season/next')return json(await competition('season_next'));
  if(route==='squad/lineup')return json(await ui('save_lineup',body));
  if(tail[0]==='league'&&tail[1]==='fixtures'&&tail[3]==='confirm-start')return json(await ui('confirm_lineup',{fixtureId:id(tail[2])}));
  if(tail[0]==='league'&&tail[1]==='fixtures'&&tail[3]==='result'){
   const action=method==='PATCH'?'result_force':typeof body.confirm==='boolean'?(body.confirm?'result_confirm':'result_dispute'):'result_submit';
   if(action==='result_confirm')return json(await gameRpc('game_ui_confirm_result',{p_code:code,p_token:token,p_key:key,p_fixture:id(tail[2]),p_cards:(body.cards||[]).map((card:any)=>({playerId:id(card.playerId),kind:card.cardType}))}));
   return json(await competition(action,{fixtureId:id(tail[2]),...(['result_force','result_submit'].includes(action)?{homeGoals:number(body.homeGoals),awayGoals:number(body.awayGoals),cards:(body.cards||[]).map((card:any)=>({playerId:id(card.playerId),kind:card.cardType}))}:{})}));
  }
  if(route==='spin'&&method==='PATCH'){await competition('draw');const d=await snapshot(),v=legacyView(d);return json({team:v.mine?v.team(v.mine):null,rerollsUsed:Math.max(0,v.c.draws.filter(x=>x.memberId===v.s.memberId&&x.seasonId===v.c.seasonId).length-1)});}
  if(route==='spin'&&method==='POST'){const d=await snapshot(),v=legacyView(d);if(!v.mine||![v.mine.id,v.mine.teamId].includes(body.teamId))return reject('El equipo seleccionado no coincide con tu sorteo.');return json({assigned:true,team:v.team(v.mine),budget:v.mine.budget});}
  if(route==='auctions')return json(await activity('vote_open',{minutes:2,auctionMinutes:body.durationMinutes||10}),201);
  if(tail[0]==='auctions'&&tail[2]==='vote')return json(await activity('vote',{ballotId:id(tail[1]),playerId:id(body.iconId)}));
  if(tail[0]==='auctions'&&tail.length===2&&method==='PATCH'){const d=await snapshot();return d.competition.ballots.some((b:{id:string})=>b.id===tail[1])?json(await activity('vote_close',{ballotId:id(tail[1])})):json(await gameRpc('game_ui_end_auction',{p_code:code,p_token:token,p_key:key,p_auction:id(tail[1])}));}
  if(tail[0]==='auctions'&&tail[2]==='bid')return json(await gameRpc('game_auction_command',{p_code:code,p_token:token,p_key:key,p_action:'auction_bid',p_auction:id(tail[1]),p_amount:number(body.amount)}));
  if(tail[0]==='members'&&method==='DELETE')return json(await ui('remove_member',{memberId:id(tail[1])}));
  if(route==='settings')return json(await ui('settings',body));
  if(route==='notifications')return json({ok:true});
  if(route.endsWith('/reset'))return reject('El historial y el patrimonio se conservan. Finaliza la temporada para comenzar otra.');
  if(route===''||route==='league/finish'){const d=await snapshot();return d.competition.phase==='finished'?json({ok:true}):reject('Completa y cierra las jornadas pendientes antes de finalizar.');}
  if (!route.startsWith('social/')) return reject('Esta acción todavía no está conectada al modelo local.');
 }
 const d:Snapshot=await snapshot(),v=legacyView(d),{s,c,m,mine}=v;
 if(route==='')return json(v.tournament);
 if(route==='teams')return json(s.clubs.filter(cl=>!cl.memberId||cl.memberId===s.memberId).map(v.team));
 if(route==='spin')return json({assigned:!!mine,team:mine?v.team(mine):null,rerollsAllowed:c.rules?.rerolls||0,rerollsUsed:Math.max(0,c.draws.filter(x=>x.memberId===s.memberId&&x.seasonId===c.seasonId).length-1)});
 if(route==='squad')return mine?json({team:v.team(mine),players:mine.squad.map(v.player),avgOvr:mine.squad.length?Math.round(mine.squad.reduce((sum,p)=>sum+p.ovr,0)/mine.squad.length):0}):reject('Gira la ruleta para recibir tu equipo.');
 if(route==='squad/lineup')return json(d.draft||{formation:null,slots:null});
 if(route==='market')return json(v.market);
 if(route==='league')return json(v.league);
 if(route==='seasons')return json({seasons:d.seasons.filter(se=>se.id!==c.seasonId||c.phase==='finished').map(se=>({id:se.id,seasonNumber:se.number,startedAt:se.started_at,finishedAt:se.ended_at,totalMatchdays:Math.max(0,...v.fixtures.filter(f=>f.seasonId===se.id).map(f=>f.matchday)),champion:v.standings(se.id)[0]||null,standings:v.standings(se.id),fixtures:v.fixtures.filter(f=>f.seasonId===se.id).map(f=>({...f,homeDisplayName:f.homeMember.displayName,awayDisplayName:f.awayMember.displayName,homeTeamName:f.homeMember.teamName,awayTeamName:f.awayMember.teamName}))}))});
 if(tail[0]==='league'&&tail[1]==='fixtures'&&tail[3]==='squads'){
  const f=c.fixtures.find(f=>f.id===tail[2]);if(!f)return reject('Partido no encontrado.',404);
  const squad=(cid:string)=>({memberId:v.manager(cid,f.seasonId).id,displayName:v.manager(cid,f.seasonId).displayName,teamName:v.club(cid)?.name,players:f.lineups.filter(l=>l.clubId===cid&&l.selected).map(l=>({id:l.playerId,name:l.name,position:l.position||'',ovr:l.ovr,suspended:false}))});
  return json({home:squad(f.homeClubId),away:squad(f.awayClubId)});
 }
 if(route==='auctions')return json({auctions:v.auctions,myBudget:mine?.budget||0,myBudgetReserved:mine?.reserved||0,myIconSlotUsed:!!v.limit?.iconsUsed});
 if(tail[0]==='auctions'&&tail.length===2){const a=v.auctions.find(a=>a.id===tail[1]);if(!a)return reject('Subasta no encontrada.',404);return json({auction:a,bids:(m.auctions.find(a=>a.id===tail[1])?.bids||[]).map(b=>({id:String(b.id),memberId:v.manager(b.clubId).id,memberName:v.manager(b.clubId).displayName,amount:b.amount,createdAt:b.createdAt,isMe:b.clubId===mine?.id}))});}
 if(route==='icons')return json({icons:m.auctionIcons.map(p=>({...v.icon(p.id),minBid:p.minBid}))});
 if(route==='notifications')return json({notifications:[],unreadCount:0});
 if(route==='market/history'){
  const wid=url.searchParams.get('sessionId');if(!wid)return json({sessions:d.windows.map(w=>({...v.window(w),transferCount:d.transfers.filter(t=>t.window_id===w.id).length}))});
  const w=d.windows.find(w=>w.id===wid);if(!w)return reject('Mercado no encontrado.',404);
  const ts=d.transfers.filter(t=>t.window_id===wid).map(v.transfer);
  return json({session:v.window(w),transfers:ts,stats:{totalTransfers:ts.length,totalSpent:ts.reduce((n,t)=>n+t.amount,0),clauseCount:ts.filter(t=>t.transferType==='clause').length,auctionCount:ts.filter(t=>t.transferType==='icon_auction').length,offerCount:ts.filter(t=>t.transferType==='offer').length,biggestDeal:[...ts].sort((a,b)=>b.amount-a.amount)[0]||null},members:s.clubs.map(cl=>({id:v.manager(cl.id).id,displayName:v.manager(cl.id).displayName,teamName:cl.name,teamCrestUrl:v.crest(cl.id),bought:ts.filter(t=>t.buyerId===v.manager(cl.id).id),sold:ts.filter(t=>t.sellerId===v.manager(cl.id).id),totalSpent:ts.filter(t=>t.buyerId===v.manager(cl.id).id).reduce((n,t)=>n+t.amount,0)}))});
 }
 if(route==='expenses'){
  const games=c.fixtures.filter(f=>f.seasonId===c.seasonId&&[f.homeClubId,f.awayClubId].includes(mine?.id||''));
  const players=(mine?.squad||[]).map(p=>({playerId:p.id,playerName:p.name,price:p.price,ovr:p.ovr,position:p.position||'',headshotUrl:v.asset(p.id)?.headshot_url||null,salaryPerMatch:Math.floor(p.price*.1/Math.max(1,games.length)),salaryPerSeason:Math.floor(p.price*.1)}));
  const ledger=games.flatMap(f=>f.expenses.filter(e=>e.clubId===mine?.id).map(e=>({id:`${f.id}:${e.playerId}:${e.kind}`,fixtureId:f.id,matchday:f.round,expenseType:e.kind==='yellow'?'yellow_card':e.kind==='red'?'red_card':'salary',playerId:e.playerId,playerName:f.lineups.find(l=>l.playerId===e.playerId)?.name||'',amount:e.amount,isCredit:false,createdAt:d.seasons.find(se=>se.id===c.seasonId)?.started_at})));
  const total=(kind:string)=>ledger.filter(e=>e.expenseType===kind).reduce((n,e)=>n+e.amount,0);
  return json({budget:mine?.budget||0,budgetReserved:mine?.reserved||0,league:{totalMatchdays:games.length,currentMatchday:v.round,status:v.league.status},salaries:{perMatchTotal:players.reduce((n,p)=>n+p.salaryPerMatch,0),perSeasonTotal:players.reduce((n,p)=>n+p.salaryPerSeason,0),players},fines:{yellowFee:500000,redFee:2000000},totals:{salaryPaid:total('salary'),yellowFines:total('yellow_card'),redFines:total('red_card'),autoReleaseRecovered:c.releases.filter(r=>r.clubId===mine?.id).reduce((n,r)=>n+r.refund,0),netSpent:ledger.reduce((n,e)=>n+e.amount,0)},ledger});
 }
 if(route.startsWith('social/'))return await social(request,route,body,key!,d);
 return reject('Esta acción requiere una adaptación adicional al modelo de clubes.');
 }catch(error){console.error('[UI compatibility]', error instanceof Error ? error.message : (error as {message?:string})?.message);return gameError(error);}
}

async function social(request:Request,route:string,body:any,key:string,d:Snapshot){
 const db=localGameClient(),s=d.state,token=request.headers.get('X-Mercatto-Member')||bearer(request);
 const profiles=await db.from('social_profiles').select('id,member_id,username,photo_url').eq('tournament_id',s.id);
 if(profiles.error)throw profiles.error;
 const profile=profiles.data.find(p=>p.member_id===s.memberId)||null;
 if(route==='social/profile'){
  if(request.method==='GET')return json({profile,profiles:profile?[profile]:[]});
  if(typeof body.username!=='string'||body.username.trim().length<2||body.username.length>40)throw new Error('INVALID_PROFILE');
  const {data,error}=await db.from('social_profiles').upsert({tournament_id:s.id,member_id:s.memberId,username:body.username.trim(),photo_url:body.photo_url||null},{onConflict:'member_id,tournament_id'}).select('id,username,photo_url').single();if(error)throw error;return json({profile:data,profiles:[data]});
 }
 if(route==='social/posts'&&request.method!=='GET'){
  if(body.image_url) return reject('Las imágenes todavía no están conectadas al entorno local.');
  const result=await gameRpc('game_social_command',{p_code:s.code,p_token:token,p_key:key,p_action:'post',p_content:body.content,p_post:body.parent_id||null});return json({post:{id:result.postId,content:body.content,parent_id:body.parent_id||null,created_at:new Date().toISOString(),image_url:null,isMe:true,author:profile,likeCount:0,likedByMe:false,replyCount:0}},201);
 }
 if(route.endsWith('/like'))return json(await gameRpc('game_social_command',{p_code:s.code,p_token:token,p_key:key,p_action:request.method==='DELETE'?'unlike':'like',p_post:id(route.split('/')[2])}));
 if(route!=='social/posts'||request.method!=='GET') return reject('Esta acción todavía no está conectada al modelo local.');
 const {data:posts,error}=await db.from('posts').select('id,member_id,content,image_url,parent_id,created_at').eq('tournament_id',s.id).order('created_at',{ascending:false}).limit(100);if(error)throw error;
 const likes=posts.length?await db.from('post_likes').select('post_id,member_id').in('post_id',posts.map(p=>p.id)):{data:[],error:null};if(likes.error)throw likes.error;
 const parent=new URL(request.url).searchParams.get('parent_id');
 return json({posts:posts.filter(p=>(p.parent_id||null)===parent).map(p=>({...p,isMe:p.member_id===s.memberId,author:profiles.data.find(pr=>pr.member_id===p.member_id)||{username:s.members.find(mm=>mm.id===p.member_id)?.name||'Participante',photo_url:null},likeCount:likes.data.filter(l=>l.post_id===p.id).length,likedByMe:likes.data.some(l=>l.post_id===p.id&&l.member_id===s.memberId),replyCount:posts.filter(r=>r.parent_id===p.id).length}))});
}
