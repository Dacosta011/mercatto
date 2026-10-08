import { handleLegacyGame } from '@/lib/game-legacy-adapter';
type Context={params:Promise<{path:string[]}>};
async function handle(request:Request,{params}:Context){return handleLegacyGame(request,(await params).path);}
export {handle as GET,handle as POST,handle as PUT,handle as PATCH,handle as DELETE};
