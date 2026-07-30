(() => {
  'use strict';
  const OVERLAY_ID = 'bPaigow01Overlay';
  let lastFocus = null;

  function ensureOverlay() {
    let overlay = document.getElementById(OVERLAY_ID);
    if (overlay) return overlay;
    overlay = document.createElement('div');
    overlay.id = OVERLAY_ID;
    overlay.className = 'b-paigow01-overlay';
    overlay.hidden = true;
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', '九霄灵牌');
    overlay.innerHTML = `
      <div class="b-paigow01-shell">
        <iframe class="b-paigow01-frame" title="九霄灵牌" src="about:blank"></iframe>
        <button class="b-paigow01-close" type="button" aria-label="关闭九霄灵牌">×</button>
      </div>`;
    document.body.appendChild(overlay);
    overlay.querySelector('.b-paigow01-close')?.addEventListener('click', close);
    return overlay;
  }

  function open(context = {}) {
    const overlay = ensureOverlay();
    const frame = overlay.querySelector('.b-paigow01-frame');
    lastFocus = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    if (frame && (frame.src === 'about:blank' || !frame.src.includes('b-paigow01.html'))) {
      const params = new URLSearchParams({ embed: '1', source: String(context.source || 'casino'), v: 'v1-2-fix2-cache39' });
      frame.src = `b-paigow01.html?${params.toString()}`;
    }
    overlay.hidden = false;
    document.body.classList.add('b-paigow01-open');
    overlay.querySelector('.b-paigow01-close')?.focus();
  }

  function close() {
    const overlay = document.getElementById(OVERLAY_ID);
    if (!overlay) return;
    overlay.hidden = true;
    document.body.classList.remove('b-paigow01-open');
    if (lastFocus?.isConnected) lastFocus.focus();
  }

  window.addEventListener('message', event => {
    if (event.origin !== location.origin && location.protocol !== 'file:') return;
    if (event.data?.type === 'b-paigow01-close') close();
  });

  window.JiuxiaoPaiGowB01 = Object.freeze({ open, close });
})();
