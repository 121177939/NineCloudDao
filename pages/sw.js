const CACHE_NAME = 'nine-cloud-dao-v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated';
const CACHE_PREFIX = 'nine-cloud-dao-';
const NAVIGATION_FALLBACK = './index.html';
const APP_SHELL = [
  './index.html',
  './404.html',
  './styles.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-tianxu-v220.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-tiandao-person-v220.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-exploration-v220.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './config.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './update-guard.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './app.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './manifest.webmanifest?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './assets/icon-192.png?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './assets/icon-512.png?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-equipment01.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-equipment01.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-equipment-v210.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-equipment-v210.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-secret-realm01.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-secret-realm01.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-technique-v220.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-technique-v220.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-sect-v2.css?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-sect-v2.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-tiandao-person-v220.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './b-exploration-v220.js?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
  './assets/secret-realm-portal.webp?v=v2-2-0-cache134-jiuxiao-exploration-300-natural-ai-admin38-sql262-gated',
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
