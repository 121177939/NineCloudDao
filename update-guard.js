(() => {
  'use strict';

  const config = window.GAME_CONFIG || {};
  const BUILD_ID = String(config.buildId || 'v0153-cache20');
  const CACHE_PREFIX = 'nine-cloud-dao-';
  const BUILD_STORAGE_KEY = 'nine_cloud_dao_client_build_v1';
  const EPOCH_STORAGE_KEY = 'nine_cloud_dao_cache_epoch_v1';
  const RELOAD_GUARD_KEY = 'nine_cloud_dao_sw_reload_guard_v1';
  const CHECK_INTERVAL_MS = 60 * 1000;
  const SUPABASE_URL = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const API_KEY = String(config.supabasePublishableKey || '');
  let refreshInProgress = false;
  let releaseCheckInProgress = false;

  async function clearNineCloudCaches() {
    if (!('caches' in window)) return;
    const names = await caches.keys();
    await Promise.all(
      names
        .filter(name => name.startsWith(CACHE_PREFIX))
        .map(name => caches.delete(name))
    );
  }

  function cacheBustedUrl(epoch) {
    const url = new URL(window.location.href);
    url.searchParams.set('ncd_build', BUILD_ID);
    if (Number.isFinite(epoch) && epoch > 0) {
      url.searchParams.set('cache_epoch', String(epoch));
    }
    return url.toString();
  }

  async function forceClientRefresh(epoch) {
    if (refreshInProgress) return;
    refreshInProgress = true;
    try {
      localStorage.setItem(BUILD_STORAGE_KEY, BUILD_ID);
      localStorage.setItem(EPOCH_STORAGE_KEY, String(epoch));
      await clearNineCloudCaches();
      if ('serviceWorker' in navigator) {
        const registrations = await navigator.serviceWorker.getRegistrations();
        await Promise.all(registrations.map(registration => registration.update().catch(() => undefined)));
      }
    } finally {
      window.location.replace(cacheBustedUrl(epoch));
    }
  }

  async function checkServerRelease() {
    if (releaseCheckInProgress || !SUPABASE_URL || !API_KEY) return;
    releaseCheckInProgress = true;
    try {
      const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/get_jiuxiao_app_release_control_v1`, {
        method: 'POST',
        cache: 'no-store',
        headers: {
          apikey: API_KEY,
          Accept: 'application/json',
          'Content-Type': 'application/json'
        },
        body: '{}'
      });
      if (!response.ok) return;
      const payload = await response.json();
      const data = Array.isArray(payload) ? payload[0] : payload;
      const serverEpoch = Number(data?.cache_epoch || 0);
      if (!Number.isSafeInteger(serverEpoch) || serverEpoch <= 0) return;

      const rawLocalEpoch = localStorage.getItem(EPOCH_STORAGE_KEY);
      if (rawLocalEpoch === null) {
        localStorage.setItem(EPOCH_STORAGE_KEY, String(serverEpoch));
        return;
      }
      const localEpoch = Number(rawLocalEpoch || 0);
      if (serverEpoch > localEpoch) {
        await forceClientRefresh(serverEpoch);
      }
    } catch (error) {
      console.debug('[九霄问道] 版本检查暂不可用：', error?.message || error);
    } finally {
      releaseCheckInProgress = false;
    }
  }

  async function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) return;

    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (sessionStorage.getItem(RELOAD_GUARD_KEY) === BUILD_ID) return;
      sessionStorage.setItem(RELOAD_GUARD_KEY, BUILD_ID);
      window.location.reload();
    });

    try {
      const registration = await navigator.serviceWorker.register(
        `./sw.js?v=${encodeURIComponent(BUILD_ID)}`,
        { scope: './', updateViaCache: 'none' }
      );

      if (registration.waiting) {
        registration.waiting.postMessage({ type: 'SKIP_WAITING' });
      }

      registration.addEventListener('updatefound', () => {
        const worker = registration.installing;
        if (!worker) return;
        worker.addEventListener('statechange', () => {
          if (worker.state === 'installed' && navigator.serviceWorker.controller) {
            worker.postMessage({ type: 'SKIP_WAITING' });
          }
        });
      });

      await registration.update();
      window.setInterval(() => registration.update().catch(() => undefined), 5 * 60 * 1000);
    } catch (error) {
      console.warn('[九霄问道] Service Worker 注册失败：', error);
    }
  }

  async function initializeUpdateGuard() {
    const previousBuild = localStorage.getItem(BUILD_STORAGE_KEY);
    if (previousBuild !== BUILD_ID) {
      localStorage.setItem(BUILD_STORAGE_KEY, BUILD_ID);
      await clearNineCloudCaches();
    }

    await registerServiceWorker();
    await checkServerRelease();

    window.setInterval(checkServerRelease, CHECK_INTERVAL_MS);
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) checkServerRelease();
    });
    window.addEventListener('focus', checkServerRelease, { passive: true });
  }

  window.addEventListener('load', initializeUpdateGuard, { once: true });
})();
