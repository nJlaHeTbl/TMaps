// Retirement worker for TMaps releases that registered Flutter's legacy
// offline service worker. Existing installations periodically check this same
// URL, activate this small replacement, clear only /TMaps/ entries, reload the
// controlled page from the network, and then unregister the worker.

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const scopePath = new URL(self.registration.scope).pathname;
    const cacheNames = await caches.keys();

    await Promise.all(
      cacheNames.map(async (cacheName) => {
        const cache = await caches.open(cacheName);
        const requests = await cache.keys();
        await Promise.all(
          requests
            .filter((request) =>
              new URL(request.url).pathname.startsWith(scopePath),
            )
            .map((request) => cache.delete(request)),
        );
      }),
    );

    await self.clients.claim();
    const windows = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    await self.registration.unregister();
    await Promise.all(
      windows.map((client) => client.navigate(client.url).catch(() => null)),
    );
  })());
});

self.addEventListener('fetch', (event) => {
  if (event.request.method === 'GET') {
    event.respondWith(fetch(event.request, {cache: 'no-store'}));
  }
});
