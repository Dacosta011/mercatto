import { notFound } from 'next/navigation';
import GameLab from './GameLab';

export default function GamePage() {
  if (process.env.MERCATTO_GAME_MODEL !== 'local' || process.env.NEXT_PUBLIC_SUPABASE_URL !== 'http://127.0.0.1:54321') notFound();
  return <GameLab />;
}
