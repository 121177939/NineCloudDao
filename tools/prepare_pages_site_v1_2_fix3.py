#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,shutil,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
if out.exists():shutil.rmtree(out)
out.mkdir(parents=True)
files=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.js','b-paigow01.css','b-paigow01.html','paigow-app.js','paigow-app.css','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png']
for rel in files:
 src=root/rel;dst=out/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
manifest=[]
for p in sorted(x for x in out.rglob('*') if x.is_file()):
 manifest.append({'path':p.relative_to(out).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':'V1.2 FIX3 CACHE40','clientBuild':'v1-2-fix3-cache40','files':manifest},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'pages files={len(manifest)}')
