#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,shutil,sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-0-5-cache97-equipment-worldnews3-pagesunlock1-appdialogupdate1'; label='V2.0.5 CACHE97'
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css','b-secret-realm01.js','b-secret-realm01.css','b-sect-v2.js','b-sect-v2.css','paigow-realtime.js','paigow-app.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css','b-paigow02-ui.js','assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp']
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
def text(x): return (root/x).read_text('utf-8')
styles=text('styles.css'); baseline=json.loads(text('CURRENT_BASELINE.json'))
checks={
 'version':text('VERSION.txt').splitlines()[0]==label and build in text('VERSION.txt'),
 'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 97']),
 'text-red':'.world-event-row.is-equipment-enhancement .world-event-copy p' in styles and 'color: #ef5f5f' in styles,
 'no-special-background':not re.search(r'\.world-event-row\.is-equipment-enhancement\s*\{[^}]*(background|border-left)',styles,re.S),
 'database':baseline.get('nextSqlNumber')==232 and baseline.get('sqlRevision')=='211-221 + 229-231',
 'pages-method':baseline.get('deploymentMethod')=='github_actions_pages_artifact_original_flow'
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
