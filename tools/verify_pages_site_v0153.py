#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.pages-site').resolve()
checks = []

def ck(name, ok):
    checks.append((name, bool(ok)))

def txt(rel):
    return (root / rel).read_text(encoding='utf-8')

required = [
    '.nojekyll', 'index.html', '404.html', 'styles.css', 'app.js', 'config.js',
    'update-guard.js', 'sw.js', 'manifest.webmanifest', 'VERSION.txt',
    'CURRENT_BASELINE.json', 'release_config.json', 'assets/icon-192.png',
    'assets/icon-512.png', 'PAGES_ARTIFACT_MANIFEST.json'
]
for rel in required:
    ck(f'file:{rel}', (root / rel).is_file())

ck('version', txt('VERSION.txt').strip() == 'V0.15.3')
ck('config-version', "version: '0.15.3'" in txt('config.js'))
ck('build', 'v0153-cache20' in txt('config.js'))
ck('epoch', 'cacheEpoch: 20' in txt('config.js'))
ck('index-cache', '0153-cache20' in txt('index.html'))
ck('service-worker-cache', 'nine-cloud-dao-v0.15.3-cache20' in txt('sw.js'))
ck('40-sec-client', 'elapsed/40*100' in txt('app.js') and '公共40秒轮次' in txt('app.js'))
ck('30-2-5-3-client', all(x in txt('app.js') for x in [
    '前30秒下注', '随后2秒封盘', '5秒依次开骰',
    'start + 30000', 'start + 32000', 'start + 37000'
]))
ck('technique-library-client', 'get_technique_library_v1' in txt('app.js'))
ck('technique-v2-upgrade-client', 'upgrade_technique_v2' in txt('app.js'))
ck('exclusive-upgrade-client', 'upgrade_exclusive_technique_v1' in txt('app.js'))

manifest = json.loads(txt('PAGES_ARTIFACT_MANIFEST.json'))
ck('manifest-version', manifest.get('version') == 'V0.15.3')
ck('manifest-build', manifest.get('clientBuild') == 'v0153-cache20')
for entry in manifest.get('files', []):
    path = root / entry['path']
    ck(
        f"hash:{entry['path']}",
        path.is_file()
        and path.stat().st_size == entry['size']
        and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256'],
    )

failed = [name for name, ok in checks if not ok]
print(json.dumps({'ok': not failed, 'checks': len(checks), 'failed': failed}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failed else 0)
