#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys, re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve(); out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-2-0-cache130-tiandao-interaction-ux-admin37-sql259-online'; label='V2.2.0 CACHE130'
required=[
'.nojekyll','index.html','404.html','styles.css','b-tianxu-v220.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
'b-equipment01.js','b-equipment01.css','b-equipment-v210.js','b-equipment-v210.css','b-secret-realm01.js','b-secret-realm01.css','b-world-boss01.js','b-world-boss01.css','b-sect-v2.js','b-sect-v2.css','b-technique-v220.js','b-technique-v220.css','b-tiandao-person-v220.js','b-tiandao-person-v220.css',
'assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp']
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
def text(x): return (root/x).read_text('utf-8')
idx=text('index.html'); module=text('b-tiandao-person-v220.js'); css=text('b-tiandao-person-v220.css'); sw=text('sw.js'); baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
checks={
'version':text('VERSION.txt').splitlines()[0]==label and build in text('VERSION.txt'),
'pages-lock':'PAGES_DEPLOY prebuilt-pages-directory-official-artifact-r1' in text('VERSION.txt'),
'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 130']),
'release-json':release.get('releaseLabel')==label and release.get('cacheEpoch')==130 and release.get('buildId')==build and release.get('nextSqlNumber')==260 and release.get('gmVersion')=='ADMIN9 R37' and release.get('runtimeDatabaseGate')=='SQL259_GATE_PASSED',
'baseline-json':baseline.get('releaseLabel')==label and baseline.get('nextSqlNumber')==260 and 'SQL259 ONLINE' in baseline.get('sqlRevision','') and baseline.get('gmVersion')=='ADMIN9 R37',
'index-cache-bust':build in idx and '<!-- version: V2.2.0 CACHE130 -->' in idx,
'legacy-social-rpc-removed':'get_npc_social_v1' not in module and 'get_npc_social_v1' not in text('app.js'),
'dynamic-modal-delegation':all(x in module for x in ["closest?.('[data-tp-close-modal]')","closest?.('[data-tp-interact]')","data-tp-modal-backdrop","closePersonModal"]),
'modal-ux':all(x in css for x in ['tp-person-modal-loading','tp-action-status','tp-ai-spinner','max-height:92dvh']),
'observer-throttled':all(x in module for x in ['requestAnimationFrame(run)','record.addedNodes','node.id === \'npcSocialSection\'']) and 'new MutationObserver(()=>mount())' not in module,
'interaction-feedback':all(x in module for x in ['runAiAction','NPC正在思量','state.actionBusy','setActionBusy']),
'detail-cache':'detailCache' in module and '45000' in module,
'cloudflare-client-secret-absent':not re.search(r'CLOUDFLARE_AUTH_TOKEN|CLOUDFLARE_ACCOUNT_ID|5b79ea0b023989a461bbb8f8a6f0b374', idx+module+text('config.js')),
'sw-cache130':build in sw,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
if failed: raise SystemExit('FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
 src=root/rel; dst=out/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
files=[]
for p in sorted(x for x in out.rglob('*') if x.is_file()): files.append({'path':p.relative_to(out).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build,'files':files},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'{label} Pages artifact PASS files={len(files)}')
