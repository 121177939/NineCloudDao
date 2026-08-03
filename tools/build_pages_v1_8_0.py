#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys

root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build_id='v1-8-2-cache72-equipmentfx1'
label='V1.8.2 CACHE72'
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css','b-secret-realm01.js','b-secret-realm01.css','paigow-realtime.js','paigow-app.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css','b-paigow02-ui.js','assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp']
for rel in required:
    if not (root/rel).is_file(): raise SystemExit(f'MISSING:{rel}')
for rel in ['gm-admin.html','gm-admin.css','gm-admin.js','gm-operations.html','GM入口说明.txt']:
    if (root/rel).exists(): raise SystemExit(f'LOCAL_GM_ASSET_NOT_ALLOWED_IN_PUBLIC_PAGES:{rel}')
def text(rel): return (root/rel).read_text('utf-8')
app=text('app.js'); equipment=text('b-equipment01.js'); secret_realm=text('b-secret-realm01.js'); sw=text('sw.js'); workflow=text('.github/workflows/deploy-pages.yml')
baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
runtime=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.html','b-paigow01.js','b-equipment01.css','b-equipment01.js','b-secret-realm01.css','b-secret-realm01.js','paigow-app.js','paigow-realtime.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css','b-paigow02-ui.js']
texts=[text(x) for x in runtime]; blob='\n'.join(texts)
checks={
 'version':text('VERSION.txt').splitlines()[0].strip()=='V1.8.2 CACHE72' and build_id in text('VERSION.txt'),
 'config':all(t in text('config.js') for t in ["version: '1.8.2'","releaseLabel: 'V1.8.2 CACHE72'",f"buildId: '{build_id}'",'cacheEpoch: 72']),
 'deployment-enabled':baseline.get('deploymentStatus')=='formal_release' and release.get('deploymentAllowed') is True and baseline.get('sqlRevision')=='143-162',
 'local-gm-mode':baseline.get('gmDeliveryMode')=='local_only' and release.get('gmDeliveryMode')=='local_only',
 'baseline-lock':baseline.get('developmentBaseline')=='V1.8.2_AB56_ADMIN9_CACHE72' and baseline.get('gmVersion')=='ADMIN9 R11 FIX1',
 'index-assets':all(t in text('index.html') for t in ['<!-- version: V1.8.2 CACHE72 -->',f'b-secret-realm01.js?v={build_id}',f'b-equipment01.js?v={build_id}',f'b-paigow01.js?v={build_id}']),
 'service-worker':all(t in sw for t in ['nine-cloud-dao-v1.8.2-cache72-equipmentfx1',f'b-equipment01.js?v={build_id}',f'paigow-app.js?v={build_id}']) and all(t not in sw for t in ['gm-admin','gm-operations','ADMIN9']),
 'enhancement-state-rpc':'get_equipment_enhancement_state_v180' in equipment,
 'enhancement-action-rpc':'enhance_equipment_v180' in equipment and 'decompose_equipment_v180' in equipment,
 'enhancement-copy':all(t in equipment for t in ['我命由我不由天','我再回去考虑考虑','装备、已有强化等级、全部孔位','器源']),
 'enhancement-rules':all(t in equipment for t in ['yellow: 1, mystic: 2, earth: 4, heaven: 8, immortal: 16','targetLevel','ring_cumulative_percent']),
 'equipment-grid-uifix':all(t in text('b-equipment01.css') for t in ['CACHE64 UIFIX4','-webkit-line-clamp:2','font-size:.30rem']) and '<small>${esc(item.realm_name)} · ${esc(item.main_stat_display)}</small>' not in equipment and 'function gridSocketDisplay(item)' in equipment and '<em>${esc(gridSocketDisplay(item))}</em>' in equipment and 'merged.socket_display = `孔位 ${merged.total_socket_capacity}' in equipment,
 'secret-realm-reward2':all(t in secret_realm for t in ['对应完整机缘结果的五分之一','reward_global_multiplier','monster_strength_multiplier','炼气10—15']),
 'ring-talent1':all(t in app for t in ['戒指效果提高','本次戒指增伤由','effective_equipment_element_bonus','talent_ring_amplification_rate']) and all(t in json.dumps(baseline,ensure_ascii=False) for t in ['戒指4%在剑心或变异灵根生效时为4.4%','剑心与变异灵根不叠加']),
 'equipment-fx1':all(t in equipment for t in ['function equipmentEffectTier(item)','equipment-effect-tier6-bequipment01','equipment-effect-tier8-bequipment01','equipment-effect-tier10-bequipment01']) and all(t in text('b-equipment01.css') for t in ['CACHE72 EQUIPMENT-FX1','equipmentFxInnerSpinBEquipment01','equipmentFxOuterSpinBEquipment01','#c99a32 0%','#4f86d9 20%','#925fd1 40%','#e05252 60%','#f2d06b 80%']),
 'secret-realm-nav':all(t in app for t in ["['secret_realm', '秘', '秘境']",'id="secretRealmSection"','jiuxiao:secret-realm-rendered']),
 'workflow-builder':'python3 tools/build_pages_v1_8_0.py' in workflow,
 'workflow-js':'gm-admin.js' not in workflow and 'b-equipment01.js' in workflow,
 'no-old-build':build_id in blob and not any(x in blob for x in ['v1-7-7-fix1-cache57','v1-7-8-cache58-equipfix2','v1-7-9-cache59-secretclaim2-history5','v1-8-1-cache65-secret-realm-reward2']),
 'no-conflicts':not any('<<<<<<<' in x or '>>>>>>>' in x for x in texts),
 'no-secrets':'sb_secret_' not in blob.lower()
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
if failed: raise SystemExit('VERSION_CHECK_FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
    src=root/rel; dst=out/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
manifest=[]
for path in sorted(x for x in out.rglob('*') if x.is_file()):
    if path.is_symlink(): raise SystemExit(f'SYMLINK_NOT_ALLOWED:{path}')
    manifest.append({'path':path.relative_to(out).as_posix(),'size':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build_id,'deploymentAllowed':True,'gmDeliveryMode':'local_only','files':manifest},ensure_ascii=False,indent=2)+'\n','utf-8')
if any(out.rglob('*.sql')): raise SystemExit('SQL_NOT_ALLOWED_IN_PAGES')
if (out/'B_HANDOFF').exists(): raise SystemExit('B_HANDOFF_NOT_ALLOWED_IN_PAGES')
if any((out/x).exists() for x in ['gm-admin.html','gm-admin.css','gm-admin.js','gm-operations.html']): raise SystemExit('LOCAL_GM_ASSET_LEAKED_TO_PAGES')
print(f'{label} public production pages build PASS files={len(manifest)}')
