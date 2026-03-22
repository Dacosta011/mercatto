const CACHE_NAME = "mercatto-v1";
const OFFLINE_URL = "/offline.html";

const PRECACHE = [OFFLINE_URL, "/icon.svg"];

// ── Install: pre-cache offline shell ────────────────────────
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE))
      .then(() => self.skipWaiting())
  );
});

// ── Activate: clean old caches ──────────────────────────────
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))
        )
      )
      .then(() => self.clients.claim())
  );
});

// ── Fetch: caching strategies ───────────────────────────────
self.addEventListener("fetch", (event) => {
  const { request } = event;

  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // API requests — always network, never cache
  if (url.pathname.startsWith("/api/")) return;

  // Navigation (HTML pages) — network-first, offline fallback
  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request).catch(() => caches.match(OFFLINE_URL))
    );
    return;
  }

  // Static assets — stale-while-revalidate
  if (
    url.pathname.startsWith("/_next/static/") ||
    url.pathname.match(/\.(svg|png|jpg|jpeg|webp|gif|ico|woff2?|css|js)$/)
  ) {
    event.respondWith(
      caches.match(request).then((cached) => {
        const networkFetch = fetch(request)
          .then((response) => {
            if (response.ok) {
              const clone = response.clone();
              caches.open(CACHE_NAME).then((c) => c.put(request, clone));
            }
            return response;
          })
          .catch(() => cached);
        return cached || networkFetch;
      })
    );
    return;
  }
});

// ── Push notifications ──────────────────────────────────────
self.addEventListener("push", (event) => {
  let data = { title: "Mercatto", body: "" };
  try {
    data = event.data.json();
  } catch {
    data.body = event.data?.text() ?? "";
  }

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: data.icon || "/icon.svg",
      badge: "/icon.svg",
      vibrate: [100, 50, 100],
      tag: data.tag || "mercatto-notification",
      renotify: true,
      data: { url: data.url || "/" },
    })
  );
});

// ── Notification click ──────────────────────────────────────
self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = event.notification.data?.url || "/";

  event.waitUntil(
    clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((windowClients) => {
        for (const client of windowClients) {
          if (client.url.includes(self.location.origin) && "focus" in client) {
            return client.navigate(targetUrl).then((c) => c?.focus());
          }
        }
        return clients.openWindow(targetUrl);
      })
  );
});
