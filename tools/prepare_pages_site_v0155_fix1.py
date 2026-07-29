#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import shutil
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root / '.pages-site'
if out == root:
    raise SystemExit('REFUSE_UNSAFE_OUTPUT')
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)

files = [
    '.nojekyll', 'index.html', '404.html', 'styles.css', 'app.js', 'config.js',
    'update-guard.js', 'sw.js', 'manifest.webmanifest', 'VERSION.txt',
    'CURRENT_BASELINE.json', 'release_config.json',
    'assets/icon-192.png', 'assets/icon-512.png'
]
manifest = []
for rel in files:
    src = root / rel
    if not src.is_file():
        raise SystemExit(f'MISSING:{rel}')
    dst = out / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    data = dst.read_bytes()
    manifest.append({'path': rel, 'size': len(data), 'sha256': hashlib.sha256(data).hexdigest()})

payload = {'version': 'V0.15.5 FIX1', 'clientBuild': 'v0155-fix1-cache27', 'files': manifest}
(out / 'PAGES_ARTIFACT_MANIFEST.json').write_text(
    json.dumps(payload, ensure_ascii=False, indent=2) + '\n', 'utf-8'
)
print('PAGES_SITE_BUILT', len(manifest) + 1)
