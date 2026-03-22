// PWA state management — module-level singleton

interface BeforeInstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

let _deferredPrompt: BeforeInstallPromptEvent | null = null;
const _listeners = new Set<() => void>();

const DISMISS_KEY = "mercatto:pwa:installDismissed";
const DISMISS_DAYS = 7;

// ── Install prompt ──────────────────────────────────────────

export function setDeferredPrompt(e: Event | null) {
  _deferredPrompt = e as BeforeInstallPromptEvent | null;
  _notify();
}

export function canInstall(): boolean {
  return _deferredPrompt !== null && !isDismissed();
}

function isDismissed(): boolean {
  try {
    const ts = localStorage.getItem(DISMISS_KEY);
    if (!ts) return false;
    const elapsed = Date.now() - parseInt(ts, 10);
    if (elapsed > DISMISS_DAYS * 86_400_000) {
      localStorage.removeItem(DISMISS_KEY);
      return false;
    }
    return true;
  } catch {
    return false;
  }
}

export function dismissInstallPrompt() {
  try {
    localStorage.setItem(DISMISS_KEY, Date.now().toString());
  } catch {}
  _notify();
}

export async function triggerInstall(): Promise<boolean> {
  if (!_deferredPrompt) return false;
  try {
    _deferredPrompt.prompt();
    const { outcome } = await _deferredPrompt.userChoice;
    _deferredPrompt = null;
    _notify();
    return outcome === "accepted";
  } catch {
    return false;
  }
}

// ── Standalone detection ────────────────────────────────────

export function isStandalone(): boolean {
  if (typeof window === "undefined") return false;
  return (
    window.matchMedia("(display-mode: standalone)").matches ||
    (window.navigator as unknown as Record<string, unknown>).standalone === true
  );
}

// ── Notification permission ─────────────────────────────────

export function getNotifPermission(): NotificationPermission | "unsupported" {
  if (typeof window === "undefined" || !("Notification" in window))
    return "unsupported";
  return Notification.permission;
}

// ── Subscriptions ───────────────────────────────────────────

export function subscribePwa(listener: () => void): () => void {
  _listeners.add(listener);
  return () => {
    _listeners.delete(listener);
  };
}

function _notify() {
  _listeners.forEach((l) => l());
}
