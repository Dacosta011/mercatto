import 'server-only';
import { createClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';

export function localGameClient() {
  const mode = process.env.MERCATTO_GAME_MODEL;
  if (mode !== 'local' && mode !== 'clubs') throw new Error('LOCAL_GAME_DISABLED');
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const local = url === 'http://127.0.0.1:54321';
  const hosted = !!url && /^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url);
  if (!url || !key || (mode === 'local' && !local) || (mode === 'clubs' && (!hosted || process.env.NEXT_PUBLIC_MERCATTO_GAME_MODEL !== 'clubs'))) throw new Error('LOCAL_GAME_CONFIG');
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false } });
}
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function requestKey(request: Request) {
  const key = request.headers.get('Idempotency-Key');
  if (!key || !UUID.test(key)) throw new Error('INVALID_KEY');
  return key;
}
export function bearer(request: Request) {
  const auth = request.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ') || !UUID.test(auth.slice(7))) throw new Error('INVALID_TOKEN');
  return auth.slice(7);
}
export async function jsonBody(request: Request): Promise<Record<string, unknown>> {
  const body: unknown = await request.json().catch(() => { throw new Error('INVALID_BODY'); });
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('INVALID_BODY');
  return body as Record<string, unknown>;
}
export function gameError(error: unknown) {
  const message = error instanceof Error ? error.message : (error as { message?: string })?.message || '';
  const code = (error as { code?: string })?.code;
  if (message === 'LOCAL_GAME_DISABLED') return NextResponse.json({ error: 'Modelo de clubes deshabilitado.' }, { status: 404 });
  if (message === 'LOCAL_GAME_CONFIG') return NextResponse.json({ error: 'Falta configurar el entorno de clubes.' }, { status: 503 });
  if (message === 'INVALID_TOKEN' || code === '28000') return NextResponse.json({ error: 'Credencial incorrecta para este torneo.' }, { status: 403 });
  if (message.startsWith('INVALID_') || message.startsWith('Invalid ')) return NextResponse.json({ error: 'Petición inválida. Revisa los campos y la clave de reintento.' }, { status: 400 });
  if (message === 'Tournament not found') return NextResponse.json({ error: 'Torneo no encontrado.' }, { status: 404 });
  if (code === 'GM001') {
    const messages: Record<string, string> = {
      'Close market before changing clubs or season': 'Cierra el mercado antes de cambiar de club o temporada.',
      'Close existing market first': 'Cierra la ventana anterior antes de abrir otra.',
      'No open market': 'No hay una ventana de mercado abierta.',
      'Choose a club first': 'Selecciona un club primero.',
      'Market deadline passed': 'La ventana de mercado ya venció.',
      'Player not in this tournament': 'El jugador no pertenece a este torneo.',
      'Icons require an auction': 'Los iconos requieren una subasta.',
      'Player has no eligible seller': 'El jugador no tiene un vendedor válido.',
      'Seller club has no manager': 'El club vendedor no tiene administrador.',
      'Offer already pending': 'Ya tienes una oferta pendiente por este jugador.',
      'Player is no longer free': 'El jugador ya pertenece a un club.',
      'Free player has no valid price': 'El jugador libre no tiene un precio válido.',
      'Insufficient available balance': 'El club no tiene saldo disponible suficiente.',
      'No purchase slots available': 'El club no tiene cupos de compra disponibles.',
      'Offer is not pending in this market': 'La oferta ya no está pendiente en este mercado.',
      'Seller no longer owns player': 'El vendedor ya no tiene al jugador.',
      'Player has no valid clause': 'El jugador no tiene una cláusula válida.',
      'Clause already attempted in this window': 'Ya intentaste pagar la cláusula de este jugador en esta ventana.',
      'Player already transferred in this window': 'Este jugador ya fue traspasado en esta ventana.',
      'Seller clause protection reached': 'El club vendedor alcanzó su protección por cláusulas en esta ventana.',
      'Auction not found': 'No se encontró la subasta.',
      'Auction already active': 'Ya hay una subasta activa en esta ventana.',
      'No eligible auction icon': 'Este icono no está disponible para subastarse.',
      'Auction is not active in this market': 'La subasta ya no está activa en esta ventana.',
      'Auction deadline passed': 'La subasta ya venció y está pendiente de adjudicación.',
      'Auction deadline not reached': 'La subasta todavía no ha vencido.',
      'Club already leads auction': 'Tu club ya tiene la puja más alta.',
      'Auction bid below minimum': 'La puja debe alcanzar el mínimo y superar la anterior en al menos 5 millones.',
      'No icon slots available': 'Tu club ya utilizó o reservó su cupo de icono en esta ventana.',
      'Auction player is no longer free': 'El icono ya pertenece a un club.',
      'Minimum squad reached':'La liberación dejaría la plantilla por debajo del mínimo.',
      'Maximum squad reached':'La plantilla alcanzó su tamaño máximo o reservó la última plaza para una subasta.',
      'Invalid squad size':'Algún club no cumple el tamaño de plantilla configurado.',
      'Player is no longer owned':'El jugador ya no pertenece a tu club.',
      'Outstanding club debt':'El club debe pagar su deuda antes de realizar compras.',
      'Finish active matches first':'Finaliza los partidos en curso antes de modificar la plantilla.',
      'Club selection is closed':'La elección de clubes terminó para esta temporada.',
      'No rerolls remaining':'Ya utilizaste todas tus reelecciones de esta temporada.',
      'No clubs available':'No quedan clubes disponibles para el giro.',
      'Use reroll after roulette':'Usa la ruleta para cambiar el club sorteado.',
      'At least two clubs required':'Se necesitan al menos dos clubes administrados para generar la liga.',
      'Close market before starting league':'Cierra el mercado antes de generar la liga.',
      'Fixture already finished':'El partido ya finalizó.',
      'Fixture not found':'El partido no pertenece a esta temporada.',
      'Fixture is not available in this phase':'El partido no está disponible en la jornada actual o hay un mercado abierto.',
      'Lineup already frozen':'La alineación ya está confirmada.',
      'Suspended player in lineup':'Un jugador suspendido no puede formar parte de la alineación.',
      'Confirm both lineups first':'Ambos clubes deben confirmar sus alineaciones primero.',
      'Other club must confirm result':'La propuesta debe confirmarla el otro club.',
      'Confirm or dispute existing result':'Confirma o disputa primero la propuesta rival.',
      'Finish all round matches first':'Completa todos los partidos y cierra el mercado antes de cerrar la jornada.',
      'Finish league before next season':'Finaliza todas las jornadas antes de iniciar otra temporada.',
      'Window already used this season':'Esta temporada ya tuvo una ventana de ese tipo.',
      'Summer belongs before league':'El verano se abre antes de generar la liga.',
      'Winter requires closed midpoint round':'El invierno solo puede abrirse al cerrar la jornada de mitad de liga, antes del siguiente partido.',
      'Vote before opening auction':'La subasta se inicia a partir de la votación de iconos.',
      'Auction or voting already active':'Ya existe una votación o subasta activa.',
      'Voting is closed':'La votación ya terminó.',
      'Club already voted':'Tu club ya emitió su voto.',
      'Voting still pending':'Espera a que venza el plazo o voten todos los clubes.',
      'At least one assigned club required':'Asigna al menos un club antes de abrir la votación.',
      'Free player is not eligible today':'Ese libre no está disponible para tu club hoy. Los liberados esperan al día siguiente y su antiguo club a otra ventana.',
      'Daily free player quota reached':'Tu club agotó el cupo diario de libres de ese nivel.',
      'No eligible daily free players':'No hay jugadores disponibles para tus cupos diarios.',
      'Resolve pending spin first':'Acepta o rechaza el resultado pendiente antes de volver a girar.',
      'Spin expired or resolved':'El resultado del giro ya venció o fue resuelto.',
      'Close market and finish active matches first':'Cierra el mercado y finaliza los partidos activos antes de cambiar al administrador.',
      'Replacement member unavailable':'El sustituto debe estar activo y sin otro club asignado.',
      'Replacement deadline not reached':'El club todavía tiene administrador o no venció el plazo para sustituirlo.',
      'Configure before starting the game':'Define las reglas antes de abrir el primer mercado o generar la liga.',
    };
    return NextResponse.json({ error: messages[message] || 'La operación no es válida en el estado actual.' }, { status: 409 });
  }
  if(['23514','22P02','22003','22023','23502'].includes(code||''))return NextResponse.json({error:'Parámetros fuera de los límites permitidos.'},{status:400});
  if (message.includes('Idempotency key') || message === 'Club already assigned' || message === 'Display name already in use') {
    return NextResponse.json({ error: 'La operación entra en conflicto con el estado actual.' }, { status: 409 });
  }
  console.error('[local game]', code || 'error', message);
  return NextResponse.json({ error: 'No se pudo completar la operación.' }, { status: 500 });
}
export async function gameRpc(name: string, args: Record<string, unknown>) {
  const { data, error } = await localGameClient().rpc(name, args);
  if (error) throw error;
  return data;
}
