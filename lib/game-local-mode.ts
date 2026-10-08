// Original screens, using the club-model transport locally or in production.
export const localGameUI = process.env.NEXT_PUBLIC_MERCATTO_GAME_MODEL === 'clubs'
  || process.env.NEXT_PUBLIC_SUPABASE_URL === 'http://127.0.0.1:54321';
