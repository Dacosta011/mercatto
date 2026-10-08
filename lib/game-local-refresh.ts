import { localGameUI } from './game-local-mode';

// Original screens retain their rendering; refresh scoped state while using local RPCs.
export function localRefresh(refresh: () => unknown) {
  if (!localGameUI) return;
  const update = () => { void refresh(); };
  const timer = window.setInterval(update, 10000);
  window.addEventListener('mercatto:game-change', update);
  return () => { clearInterval(timer); window.removeEventListener('mercatto:game-change', update); };
}
