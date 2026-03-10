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
      icon: data.icon || "/icon-192.png",
      badge: "/icon-192.png",
      vibrate: [100, 50, 100],
      tag: "mercatto-notification",
      renotify: true,
    })
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clientList) => {
        for (const client of clientList) {
          if (client.url.includes("/market") && "focus" in client) {
            return client.focus();
          }
        }
        return clients.openWindow("/market");
      })
  );
});
