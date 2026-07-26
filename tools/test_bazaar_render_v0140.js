#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const root = path.resolve(process.argv[2] || path.join(__dirname, '..'));
let source = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const marker = '\n  bootstrap();\n})();';
if (!source.includes(marker)) throw new Error('bootstrap marker not found');
source = source.replace(marker, `
  globalThis.__ncdTestExports = {
    bazaarPanelHtml,
    worldEventsPanelHtml,
    worldEventTimeText,
    marketPanelHtml,
    mobileBottomNavHtml
  };
})();`);

const storage = new Map();
const element = () => ({ textContent: '', innerHTML: '', style: { setProperty() {} }, addEventListener() {}, classList: { toggle() {}, add() {}, remove() {} } });
const context = {
  console,
  URL,
  Intl,
  Date,
  Math,
  JSON,
  Number,
  String,
  Boolean,
  Array,
  Object,
  RegExp,
  Promise,
  setTimeout,
  clearTimeout,
  setInterval,
  clearInterval,
  requestAnimationFrame: cb => { cb(); return 1; },
  cancelAnimationFrame() {},
  localStorage: { getItem: k => storage.get(k) || null, setItem: (k,v) => storage.set(k,String(v)), removeItem: k => storage.delete(k) },
  document: {
    hidden: false,
    documentElement: { clientWidth: 390, style: { setProperty() {} } },
    getElementById: () => element(),
    addEventListener() {},
    querySelectorAll: () => []
  },
  window: {
    GAME_CONFIG: { supabaseUrl: 'https://example.supabase.co', supabasePublishableKey: 'test', version: '0.14.0' },
    innerWidth: 390,
    addEventListener() {},
    matchMedia: () => ({ matches: true, addEventListener() {} }),
    history: { pushState() {}, back() {}, state: null },
    location: { hash: '', pathname: '/', search: '' },
    scrollTo() {}
  },
  history: { replaceState() {} },
  location: { hash: '', pathname: '/', search: '' },
  navigator: {},
  crypto: { randomUUID: () => '11111111-1111-4111-8111-111111111111' },
  CSS: { escape: v => String(v) }
};
context.globalThis = context;
vm.createContext(context);
vm.runInContext(source, context, { filename: 'app.js' });
const f = context.__ncdTestExports;
if (!f) throw new Error('test exports unavailable');

const events = {
  status: 'active',
  entries: [
    { id:'1', event_type:'casino_house_win', event_level:1, title:'赌运亨通', content:'修士【青玄】押中天机，一局净得100枚灵石。', created_at:new Date().toISOString(), seconds_ago:5 },
    { id:'2', event_type:'breakthrough_death', event_level:4, title:'身死道消', content:'修士【玄烬】渡劫失败。', created_at:new Date(Date.now()-70000).toISOString(), seconds_ago:70, is_pinned:true },
    { id:'3', event_type:'admin_account_erasure', event_level:4, title:'天道裁决', content:'<script>alert(1)</script>', created_at:new Date().toISOString(), seconds_ago:1 }
  ]
};
const home = f.bazaarPanelHtml('home', {}, {}, events);
for (const token of ['市坊功能入口','天命榜','赌坊','珍宝阁','九霄界闻','赌运亨通','身死道消','天道裁决']) {
  if (!home.includes(token)) throw new Error(`home missing ${token}`);
}
if (home.includes('<script>alert(1)</script>') || !home.includes('&lt;script&gt;')) throw new Error('world event escaping failed');
if (home.includes('>市场<')) throw new Error('legacy market label found');

const ranking = f.bazaarPanelHtml('ranking', {}, { status:'active', entries:[], total_count:0 }, events);
if (!ranking.includes('返回市坊') || !ranking.includes('天命榜')) throw new Error('ranking subpage failed');
const treasure = f.bazaarPanelHtml('treasure', {}, {}, events);
if (!treasure.includes('珍宝阁尚在筹备') || !treasure.includes('返回市坊')) throw new Error('treasure placeholder failed');

const marketData = {
  status:'active', pools:{}, tickets:{}, activity:{total_count:0},
  character:{spirit_stones:1000,cultivation_available:100000,cultivation_max_stake:20000,cultivation_eligible:true,cultivation_full:false},
  open_duels:[], my_duels:[], latest_draws:[]
};
const casino = f.bazaarPanelHtml('casino', marketData, {}, events);
for (const token of ['赌坊 · 万运博弈楼','灵骰问道','气运龟卜','返回市坊']) if (!casino.includes(token)) throw new Error(`casino missing ${token}`);

const nav = f.mobileBottomNavHtml('market');
if (!nav.includes('data-mobile-tab="market"') || !nav.includes('市坊')) throw new Error('bazaar nav missing');
if (nav.includes('data-mobile-tab="ranking"')) throw new Error('duplicate ranking nav remains');

const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
for (const token of ['.bazaar-entry-grid','.world-event-row','.bazaar-subpage-head','.treasure-placeholder']) if (!css.includes(token)) throw new Error(`css missing ${token}`);
if (process.env.PREVIEW_OUT) {
  const cssUrl = `file://${path.join(root, 'styles.css')}`;
  const preview = `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><link rel="stylesheet" href="${cssUrl}"><style>body{padding:12px}.preview-shell{max-width:760px;margin:0 auto}.preview-shell>.panel{display:block}</style></head><body><main class="preview-shell"><section class="panel"><div class="panel-title"><h3>市坊</h3><span class="badge">天命 · 赌坊 · 珍宝 · 界闻</span></div>${home}</section></main></body></html>`;
  fs.writeFileSync(process.env.PREVIEW_OUT, preview, 'utf8');
}
console.log(JSON.stringify({ ok:true, homeLength:home.length, casinoLength:casino.length, checks:28 }));
