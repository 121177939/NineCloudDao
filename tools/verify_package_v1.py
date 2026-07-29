#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys,zipfile
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
manifest=json.loads((root/'PACKAGE_MANIFEST.json').read_text('utf-8'))
failed=[]
for e in manifest.get('files',[]):
 p=root/e['path']
 if not p.is_file() or p.stat().st_size!=e['size'] or hashlib.sha256(p.read_bytes()).hexdigest()!=e['sha256']:
  failed.append(e['path'])
print(json.dumps({'ok':not failed,'manifestFiles':len(manifest.get('files',[])),'failed':failed},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
