export function getMinBid(ovr: number): number {
  if (ovr >= 95) return 300_000_000;
  if (ovr >= 92) return 230_000_000;
  if (ovr >= 89) return 170_000_000;
  return 120_000_000;
}

export function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}
