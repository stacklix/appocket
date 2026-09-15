// Generated with a complete, versioned inventory of this sub-app's static files.
const VERSION = __VERSION__;
const FILES = __FILES__;
const ROOT = self.registration.scope;
const PREFIX = `sentra:${ROOT}:`;
const CACHE = PREFIX + VERSION;
const URLS = new Set(FILES.map(path => new URL(path, ROOT).href));

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    await cache.addAll([...URLS].map(url => new Request(url, { cache: 'reload' })));
  })());
  // Updates wait until all old app windows close, avoiding mixed app versions.
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith(PREFIX) && key !== CACHE)
      .map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin ||
      !url.href.startsWith(ROOT)) return;
  const target = request.mode === 'navigate'
    ? new URL('index.html', ROOT).href : url.href;
  // Only build assets are cached. API requests and credentials never enter Cache Storage.
  if (!URLS.has(target)) return;
  event.respondWith((async () => {
    const cached = await (await caches.open(CACHE)).match(target);
    return cached || fetch(request);
  })());
});
