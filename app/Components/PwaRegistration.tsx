"use client";

import { useEffect } from "react";
import { setDeferredPrompt } from "@/lib/pwa";

export default function PwaRegistration() {
  useEffect(() => {
    if (!("serviceWorker" in navigator)) return;

    navigator.serviceWorker.register("/sw.js").catch(() => {});

    const onPrompt = (e: Event) => {
      e.preventDefault();
      setDeferredPrompt(e);
    };

    const onInstalled = () => setDeferredPrompt(null);

    window.addEventListener("beforeinstallprompt", onPrompt);
    window.addEventListener("appinstalled", onInstalled);

    return () => {
      window.removeEventListener("beforeinstallprompt", onPrompt);
      window.removeEventListener("appinstalled", onInstalled);
    };
  }, []);

  return null;
}
