import { NextResponse, type NextRequest } from 'next/server';

// Hosted cutover requires explicit server and build-time UI switches.
export function proxy(request: NextRequest) {
  const local=process.env.MERCATTO_GAME_MODEL==='local'&&process.env.NEXT_PUBLIC_SUPABASE_URL==='http://127.0.0.1:54321';
  const hosted=process.env.MERCATTO_GAME_MODEL==='clubs'&&process.env.NEXT_PUBLIC_MERCATTO_GAME_MODEL==='clubs';
  if(!local&&!hosted)return NextResponse.next();
  const path=request.nextUrl.pathname;
  if(path==='/api/cron/market')return NextResponse.next();
  if(path.startsWith('/api/tournaments/')){const url=request.nextUrl.clone();url.pathname=path.replace('/api/tournaments/','/api/game-compat/');return NextResponse.rewrite(url);}
  if(path.startsWith('/api/'))return NextResponse.json({error:'La partida local utiliza el modelo de clubes. Usa /api/game; las operaciones heredadas están deshabilitadas.'},{status:410});
  return NextResponse.next();
}
export const config={matcher:['/','/create','/join','/rejoin','/lobby/:path*','/roulette/:path*','/market','/squad','/calendar','/table','/subastas','/tragaperras','/market-history','/feed','/api/tournaments/:path*','/api/cron/market','/api/auctions/:path*']};
