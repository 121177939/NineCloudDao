(() => {
  'use strict';

  const MODULE = 'B-PAIGOW02-UI01';
  const root = document.documentElement;
  root.classList.add('b-paigow02-ui');

  let raf = 0;
  const viewport = window.visualViewport;

  function applyViewportHeight() {
    raf = 0;
    const height = Math.max(560, Math.round(viewport?.height || window.innerHeight || 780));
    root.style.setProperty('--pg02-screen-h', `${height}px`);
  }

  function scheduleViewportHeight() {
    if (raf) return;
    raf = requestAnimationFrame(applyViewportHeight);
  }

  scheduleViewportHeight();
  window.addEventListener('resize', scheduleViewportHeight, { passive: true });
  viewport?.addEventListener('resize', scheduleViewportHeight, { passive: true });

  function destroy() {
    if (raf) cancelAnimationFrame(raf);
    raf = 0;
    window.removeEventListener('resize', scheduleViewportHeight);
    viewport?.removeEventListener('resize', scheduleViewportHeight);
    root.classList.remove('b-paigow02-ui');
    root.style.removeProperty('--pg02-screen-h');
  }

  window.addEventListener('message', event => {
    if (event.origin !== location.origin && location.protocol !== 'file:') return;
    if (event.data?.type === 'b-paigow01-pause') destroy();
  });

  window.JiuxiaoPaigowB02UI = Object.freeze({
    module: MODULE,
    destroy,
    refreshViewport: scheduleViewportHeight
  });
})();
