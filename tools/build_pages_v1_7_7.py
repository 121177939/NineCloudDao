#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,shutil,sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css','paigow-realtime.js','paigow-app.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui.js','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png']
for rel in required:
    if not (root/rel).is_file(): raise SystemExit(f'MISSING:{rel}')

def text(rel): return (root/rel).read_text('utf-8')
app=text('app.js'); pg=text('paigow-app.js'); b02=text('b-paigow02-ui.js'); sw=text('sw.js'); wf=text('.github/workflows/deploy-pages.yml')
runtime_texts=[text(x) for x in ['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.html','b-paigow01.js','b-equipment01.css','b-equipment01.js','paigow-app.js','paigow-realtime.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui.js']]
checks={
 'version':text('VERSION.txt').strip()=='V1.7.7',
 'config':all(x in text('config.js') for x in ["version: '1.7.7'","releaseLabel: 'V1.7.7 CACHE56'","buildId: 'v1-7-7-cache56'",'cacheEpoch: 56']),
 'index':all(x in text('index.html') for x in ['<!-- version: V1.7.7 CACHE56 -->','b-paigow01.js?v=v1-7-7-cache56','b-equipment01.js?v=v1-7-7-cache56','b-equipment01.css?v=v1-7-7-cache56']),
 'iframe-b02':all(x in text('b-paigow01.html') for x in ['<html class="b-paigow02-ui"','paigow-realtime.js?v=v1-7-7-cache56','paigow-app.js?v=v1-7-7-cache56','B-PAIGOW02-UI02-PARITY-INLINE','id="bPaigow02Ui02Style"','id="bPaigow02Ui02Viewport"']),
 'paigow-b02-runtime-opener':"ui: 'b-paigow02-ui02'" in text('b-paigow01.js'),
 'paigow-b02-runtime-style':all(x in text('b-paigow01.html') for x in ['html.b-paigow02-ui .felt','html.b-paigow02-ui .seat.left','html.b-paigow02-ui .self-zone']),
 'paigow-visible-version': 'V1.7.7 CACHE56' in pg,
 'paigow-multipliers-10-30-50-100':all(x in pg for x in ['data-multiplier="10"','data-multiplier="30"','data-multiplier="50"','data-multiplier="100"','10、30、50、100倍']) and 'repeat(4,minmax(0,1fr))' in text('paigow-app.css'),
 'paigow-b02-no-network-hooks':all(x not in b02 for x in ['fetch(','XMLHttpRequest','WebSocket','setInterval(','MutationObserver']),
 'service-worker':all(x in sw for x in ['nine-cloud-dao-v1.7.7-cache56','paigow-realtime.js?v=v1-7-7-cache56','b-equipment01.js?v=v1-7-7-cache56','b-paigow02-ui.css?v=v1-7-7-cache56','b-paigow02-ui.js?v=v1-7-7-cache56']),
 'workflow-builder-present':"python3 tools/build_pages_v1_7_7.py" in wf and (root/'tools/build_pages_v1_7_7.py').is_file(),
 'ui02-final-page-guard': all(x in text('b-paigow01.html') for x in ['B-PAIGOW02-UI02-PARITY-INLINE','id="bPaigow02Ui02Style"','id="bPaigow02Ui02Viewport"']),
 'workflow-b02-js-check':'b-paigow02-ui.js' in wf,
 'no-merge-conflict-markers':not any(('<<<<<<<' in s or '>>>>>>>' in s) for s in runtime_texts),
 'equipment-no-global-polling':all(x not in text('b-equipment01.js') for x in ['MutationObserver','setInterval(','window.fetch=']),
 'equipment-event-hooks':all(x in app for x in ['jiuxiao:opportunity-settled','jiuxiao:cave-rendered','jiuxiao:primordial-rendered']),
 'equipment-storage-6x6':all(x in text('b-equipment01.css') for x in ['grid-template-columns:repeat(6,minmax(0,1fr))','aspect-ratio:1']),
 'equipment-backpack-persistent':all(x in text('b-equipment01.js') for x in ['equipmentBackpackInlineBEquipment01','renderBackpackInline','focusBackpack']),
 'cave-no-spirit-stone-summary':"const resourceRows = resources.filter(row => row.code !== 'spirit_stone')" in app,
 'casino-dice-public-ui':all(x in app for x in ['place_spirit_dice_bets_v175','本局10秒','dice-target-grid']),
 'casino-fish-batch-ui':all(x in app for x in ['place_fish_shrimp_bets_v175','本批只提交一次事务']),
 'casino-no-fast-db-polling':all(x not in app for x in ['setInterval(refreshSpiritDiceStateV175,1000','setInterval(refreshFishShrimpStateV0148,1000','setInterval(() => refreshSpiritDiceStateV175','setInterval(() => refreshFishShrimpStateV0148']),
 'casino-background-sync-paused':all(x in app for x in ['function casinoPublicTableActiveV176()','if (!casinoPublicTableActiveV176()) syncCultivation(true)','if (!document.hidden && !casinoPublicTableActiveV176()) refreshWorldEvents(true)']),
 'dice-dom-local-patch':all(x in app for x in ['function patchSpiritDiceBetDomV176()','patchSpiritDiceBetDomV176();']) and 'renderSpiritDicePanelV175()' not in app[app.find('async function processSpiritDiceQueueV175'):app.find('function spiritDicePhaseTextV175')],
 'dice-boundary-history-one':all(x in app for x in ['spiritDiceBoundaryHistoryLimit: 1','refreshSpiritDiceStateV175(true,state.spiritDiceBoundaryHistoryLimit||1,true)','Math.random()*501']),
 'dice-adaptive-clock':all(x in app for x in ['function scheduleSpiritDiceClockV176(delay=500)','scheduleSpiritDiceClockV176(nextDelay)']) and 'setInterval(updateSpiritDiceClockV175,250)' not in app,
 'dice-win-glow':all(x in app for x in ['spiritDiceHasAcceptedBetV175','spiritDiceRememberAcceptedBetsV175',"button.classList.toggle('dice-win-glow',shouldGlow)"]) and all(x in text('styles.css') for x in ['.dice-target-card.dice-win-glow','.dice-target-card.dice-win-glow:disabled']),
 'paigow-v176-advance':'advance_paigow_round_v176' in pg,
 'paigow-realtime-render-coalesce':all(x in pg for x in ['function scheduleRenderV176()','scheduleRenderV176();','requestAnimationFrame']),
 'paigow-snapshot-throttle':all(x in pg for x in ['lastSnapshotAt: 0','snapshotDelay = Math.max(220, 420 - Math.max(0, sinceLast))']),
 'paigow-clock-500ms':'setInterval(updateCountdown, 500)' in pg,
 'paigow-resync-lowered':all(x in pg for x in ['state.roomId ? 90000 : 180000','220 + Math.floor(Math.random() * 561)']),
 'paigow-no-250ms-clock':'setInterval(updateCountdown, 250)' not in pg,
 'b02-assets-contained':'contain:' in text('b-paigow02-ui.css'),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
if failed: raise SystemExit('VERSION_CHECK_FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
    src=root/rel; dst=out/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
manifest=[]
for p in sorted(x for x in out.rglob('*') if x.is_file()):
    if p.is_symlink(): raise SystemExit(f'SYMLINK_NOT_ALLOWED:{p}')
    manifest.append({'path':p.relative_to(out).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':'V1.7.7 CACHE56','clientBuild':'v1-7-7-cache56','files':manifest},ensure_ascii=False,indent=2)+'\n','utf-8')
if any(out.rglob('*.sql')): raise SystemExit('SQL_NOT_ALLOWED_IN_PAGES')
if (out/'B_HANDOFF').exists(): raise SystemExit('B_HANDOFF_NOT_ALLOWED_IN_PAGES')
print(f'V1.7.7 CACHE56 pages build PASS files={len(manifest)}')
