#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,shutil,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.js','b-paigow01.css','b-paigow01.html','paigow-realtime.js','paigow-app.js','paigow-app.css','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png']
for rel in required:
    if not (root/rel).is_file(): raise SystemExit(f'MISSING:{rel}')
checks={
 'version':(root/'VERSION.txt').read_text('utf-8').strip()=='V1.7',
 'config':all(x in (root/'config.js').read_text('utf-8') for x in ["version: '1.7.0'","releaseLabel: 'V1.7 CACHE46'","buildId: 'v1-7-cache46'",'cacheEpoch: 46']),
 'index':'b-paigow01.js?v=v1-7-cache46' in (root/'index.html').read_text('utf-8'),
 'iframe':all(x in (root/'b-paigow01.html').read_text('utf-8') for x in ['paigow-realtime.js?v=v1-7-cache46','paigow-app.js?v=v1-7-cache46']),
 'service-worker':all(x in (root/'sw.js').read_text('utf-8') for x in ['nine-cloud-dao-v1.7-cache46','paigow-realtime.js?v=v1-7-cache46']),
}
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
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':'V1.7 CACHE46','clientBuild':'v1-7-cache46','files':manifest},ensure_ascii=False,indent=2)+'\n','utf-8')
if any(out.rglob('*.sql')): raise SystemExit('SQL_NOT_ALLOWED_IN_PAGES')
print(f'V1.7 CACHE46 pages build PASS files={len(manifest)}')
