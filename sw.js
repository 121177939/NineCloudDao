const CACHE_NAME = 'nine-cloud-dao-v0.14.1-fix7-cache4';
const CACHE_PREFIX = 'nine-cloud-dao-';
const NAVIGATION_FALLBACK = './index.html';
const APP_SHELL = [
  './index.html',
  './404.html',
  './styles.css?v=0141-fix7-cache4',
  './config.js?v=0141-fix7-cache4',
  './update-guard.js?v=0141-fix7-cache4',
  './app.js?v=0141-fix7-cache4',
  './manifest.webmanifest?v=0141-fix7-cache4',
  './assets/icon-192.png?v=0141-fix7-cache4',
  './assets/icon-512.png?v=0141-fix7-cache4'
];

self.addEventListener('message', event => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await Promise.all(APP_SHELL.map(async resource => {
      const request = new Request(resource, { cache: 'reload' });
      const response = await fetch(request);
      if (!response.ok) throw new Error(`PRECACHE_FAILED:${resource}:${response.status}`);
      await cache.put(resource, response);
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
        .map(key => caches.delete(key))
    );
    await self.clients.claim();
  })());
});

async function networkFirst(request, fallbackRequest = request) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const freshRequest = new Request(request, { cache: 'no-store' });
    const response = await fetch(freshRequest);
    if (response && response.ok) await cache.put(request, response.clone());
    return response;
  } catch {
    return (await cache.match(fallbackRequest)) || (await cache.match(request));
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response && response.ok) await cache.put(request, response.clone());
  return response;
}

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);

  // Supabase账号、存档与版本控制请求始终联网，绝不写入PWA缓存。
  if (url.hostname.endsWith('.supabase.co')) return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, NAVIGATION_FALLBACK));
    return;
  }

  if (url.origin !== self.location.origin) return;

  const isCoreResource = /\.(?:js|css|json|webmanifest)$/i.test(url.pathname);
  const isImage = /\.(?:png|jpg|jpeg|webp|svg|ico)$/i.test(url.pathname);

  if (isCoreResource) {
    event.respondWith(networkFirst(request));
    return;
  }

  if (isImage) {
    event.respondWith(cacheFirst(request));
    return;
  }

  event.respondWith(networkFirst(request));
});
