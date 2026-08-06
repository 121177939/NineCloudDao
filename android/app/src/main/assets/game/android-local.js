(() => {
  'use strict';
  window.JIUXIAO_ANDROID_LOCAL = Object.freeze({
    localRuntime: true,
    runtime: 'android-apk-assets',
    gameBuild: String(window.GAME_CONFIG?.buildId || 'unknown')
  });
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.getRegistrations()
      .then(registrations => Promise.all(registrations.map(item => item.unregister())))
      .catch(() => undefined);
  }
  document.documentElement.dataset.androidLocal = 'true';
  window.addEventListener('DOMContentLoaded', () => {
    const footer = document.querySelector('.footer');
    if (footer && !footer.querySelector('[data-android-local]')) {
      const label = document.createElement('span');
      label.dataset.androidLocal = 'true';
      label.textContent = 'Android 本地资源版';
      footer.appendChild(label);
    }
  }, { once: true });
})();
