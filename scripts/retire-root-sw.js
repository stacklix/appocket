// Retire only the former Appocket homepage PWA; keep independent sub-apps intact.
self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith('appocket:')).map(key => caches.delete(key)));
    await self.registration.unregister();
  })());
});
