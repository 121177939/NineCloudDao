#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
manifest = json.loads((root / 'PACKAGE_MANIFEST.json').read_text('utf-8'))
failed = []
for entry in manifest.get('files', []):
    p = root / entry['path']
    if not p.is_file():
        failed.append(entry['path'] + ':missing')
        continue
    data = p.read_bytes()
    if len(data) != entry['size'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
        failed.append(entry['path'] + ':mismatch')
print(json.dumps({
    'ok': not failed,
    'version': manifest.get('version'),
    'clientBuild': manifest.get('clientBuild'),
    'expectedFiles': manifest.get('generatedFileCount'),
    'verifiedFiles': len(manifest.get('files', [])) - len(failed),
    'failed': failed
}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failed else 0)
