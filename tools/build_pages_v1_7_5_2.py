#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,shutil,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css','paigow-realtime.js','paigow-app.js','paigow-app.css','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png']
for rel in required:
    if not (root/rel).is_file(): raise SystemExit(f'MISSING:{rel}')
checks={
 'version':(root/'VERSION.txt').read_text('utf-8').strip()=='V1.7.5.2',
 'config':all(x in (root/'config.js').read_text('utf-8') for x in ["version: '1.7.5.1'","releaseLabel: 'V1.7.5.2 CACHE53'","buildId: 'v1-7-5-2-cache53'",'cacheEpoch: 53']),
 'index':all(x in (root/'index.html').read_text('utf-8') for x in ['b-paigow01.js?v=v1-7-5-2-cache53','b-equipment01.js?v=v1-7-5-2-cache53','b-equipment01.css?v=v1-7-5-2-cache53']),
 'iframe':all(x in (root/'b-paigow01.html').read_text('utf-8') for x in ['paigow-realtime.js?v=v1-7-5-2-cache53','paigow-app.js?v=v1-7-5-2-cache53']),
 'service-worker':all(x in (root/'sw.js').read_text('utf-8') for x in ['nine-cloud-dao-v1.7.5.1-cache53','paigow-realtime.js?v=v1-7-5-2-cache53','b-equipment01.js?v=v1-7-5-2-cache53']),
 'equipment-no-global-polling':all(x not in (root/'b-equipment01.js').read_text('utf-8') for x in ['MutationObserver','setInterval(','window.fetch=']),
 'equipment-event-hooks':all(x in (root/'app.js').read_text('utf-8') for x in ['jiuxiao:opportunity-settled','jiuxiao:cave-rendered','jiuxiao:primordial-rendered']),
 'equipment-storage-6x6':all(x in (root/'b-equipment01.css').read_text('utf-8') for x in ['grid-template-columns:repeat(6,minmax(0,1fr))','aspect-ratio:1']),
 'equipment-single-cave-grid':all(x in (root/'b-equipment01.js').read_text('utf-8') for x in ['renderCaveEquipmentIntoNative','renderBackpackInline',"storagePanel('backpack')"]) and all(x not in (root/'b-equipment01.js').read_text('utf-8') for x in ['cave.parentNode.insertBefore','equipment-storage-shell-bequipment01','data-eq-view="cave"']),
 'equipment-backpack-persistent':all(x in (root/'b-equipment01.js').read_text('utf-8') for x in ['equipmentBackpackInlineBEquipment01','renderBackpackInline','focusBackpack']) and all(x not in (root/'b-equipment01.js').read_text('utf-8') for x in ['<button class="modal-close-button" data-eq-close>×</button><header><span class="equipment-icon-bequipment01">囊</span>','data-open-equipment-backpack','renderBackpackLauncher']),
 'cave-no-spirit-stone-summary':"const resourceRows = resources.filter(row => row.code !== 'spirit_stone')" in (root/'app.js').read_text('utf-8'),
}
checks.update({
 'casino-dice-public-ui':all(x in (root/'app.js').read_text('utf-8') for x in ['place_spirit_dice_bets_v175','本局10秒','dice-target-grid','120ms合并本批点击']),
 'casino-fish-batch-ui':all(x in (root/'app.js').read_text('utf-8') for x in ['place_fish_shrimp_bets_v175','本批只提交一次事务']),
 'casino-no-fast-db-polling':all(x not in (root/'app.js').read_text('utf-8') for x in ['setInterval(refreshSpiritDiceStateV175,1000','setInterval(refreshFishShrimpStateV0148,1000','setInterval(() => refreshSpiritDiceStateV175','setInterval(() => refreshFishShrimpStateV0148']),
 'casino-generic-sync-skips-public-table':"publicGame === 'spirit_dice' || publicGame === 'fish_shrimp'" in (root/'app.js').read_text('utf-8'),
 'casino-history-cap20':(root/'app.js').read_text('utf-8').count('最近20局')>=2,
 'casino-lightweight-batch-merge':all(x in (root/'app.js').read_text('utf-8') for x in ['applySpiritDiceBatchPayloadV175','applyFishShrimpBatchPayloadV175','payload.batch_only']),
 'casino-boundary-jitter':all(x in (root/'app.js').read_text('utf-8') for x in ['spiritDiceBoundaryRefreshTimer','fishShrimpBoundaryRefreshTimer','Math.random() * 161']),
 'casino-dice-win-glow-cache53':all(x in (root/'app.js').read_text('utf-8') for x in ['spiritDiceChoiceHitV175(results, choiceCode)',"data-dice-has-bet","revealComplete=Array.isArray(round.results)","button.classList.toggle('win',shouldGlow)"]),
})
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
if failed: raise SystemExit('VERSION_CHECK_FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
    src=root/rel;dst=out/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
manifest=[]
for p in sorted(x for x in out.rglob('*') if x.is_file()):
    if p.is_symlink(): raise SystemExit(f'SYMLINK_NOT_ALLOWED:{p}')
    manifest.append({'path':p.relative_to(out).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':'V1.7.5.2 CACHE53','clientBuild':'v1-7-5-2-cache53','files':manifest},ensure_ascii=False,indent=2)+'\n','utf-8')
if any(out.rglob('*.sql')): raise SystemExit('SQL_NOT_ALLOWED_IN_PAGES')
if (out/'B_HANDOFF').exists(): raise SystemExit('B_HANDOFF_NOT_ALLOWED_IN_PAGES')
print(f'V1.7.5.2 CACHE53 pages build PASS files={len(manifest)}')
