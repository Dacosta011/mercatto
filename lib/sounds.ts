// Notification sounds using Web Audio API — no external files needed.
// Generates short, subtle tones for different event types.

const STORAGE_KEY = "mercatto_sounds_enabled";

let audioCtx: AudioContext | null = null;

function getCtx(): AudioContext | null {
  if (typeof window === "undefined") return null;
  if (!audioCtx) {
    try {
      audioCtx = new (window.AudioContext || (window as any).webkitAudioContext)();
    } catch {
      return null;
    }
  }
  return audioCtx;
}

export function isSoundEnabled(): boolean {
  if (typeof window === "undefined") return false;
  return localStorage.getItem(STORAGE_KEY) !== "false";
}

export function setSoundEnabled(enabled: boolean) {
  if (typeof window === "undefined") return;
  localStorage.setItem(STORAGE_KEY, enabled ? "true" : "false");
}

function playTone(
  freq: number,
  duration: number,
  type: OscillatorType = "sine",
  volume = 0.12,
  ramp?: { to: number }
) {
  if (!isSoundEnabled()) return;
  const ctx = getCtx();
  if (!ctx) return;

  if (ctx.state === "suspended") {
    ctx.resume();
  }

  const osc = ctx.createOscillator();
  const gain = ctx.createGain();

  osc.type = type;
  osc.frequency.setValueAtTime(freq, ctx.currentTime);
  if (ramp) {
    osc.frequency.linearRampToValueAtTime(
      ramp.to,
      ctx.currentTime + duration
    );
  }

  gain.gain.setValueAtTime(0, ctx.currentTime);
  gain.gain.linearRampToValueAtTime(volume, ctx.currentTime + 0.02);
  gain.gain.linearRampToValueAtTime(0, ctx.currentTime + duration);

  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start(ctx.currentTime);
  osc.stop(ctx.currentTime + duration);
}

// Soft, pleasant ping — new offer / generic notification
export function soundPing() {
  playTone(880, 0.15, "sine", 0.1);
  setTimeout(() => playTone(1100, 0.12, "sine", 0.08), 80);
}

// Sharper two-tone — outbid / urgent
export function soundUrgent() {
  playTone(660, 0.1, "triangle", 0.14);
  setTimeout(() => playTone(880, 0.1, "triangle", 0.14), 100);
  setTimeout(() => playTone(1100, 0.12, "triangle", 0.12), 200);
}

// Success chime — won auction / accepted offer
export function soundSuccess() {
  playTone(523, 0.12, "sine", 0.1);
  setTimeout(() => playTone(659, 0.12, "sine", 0.1), 100);
  setTimeout(() => playTone(784, 0.2, "sine", 0.12), 200);
}

// Warning low tone — clause / market closing
export function soundWarning() {
  playTone(440, 0.2, "triangle", 0.1);
  setTimeout(() => playTone(392, 0.25, "triangle", 0.08), 150);
}

// Subtle tap — minor UI interaction
export function soundTap() {
  playTone(1200, 0.06, "sine", 0.06);
}

export type SoundType = "ping" | "urgent" | "success" | "warning" | "tap";

const soundMap: Record<SoundType, () => void> = {
  ping: soundPing,
  urgent: soundUrgent,
  success: soundSuccess,
  warning: soundWarning,
  tap: soundTap,
};

export function playSound(type: SoundType) {
  soundMap[type]?.();
}
