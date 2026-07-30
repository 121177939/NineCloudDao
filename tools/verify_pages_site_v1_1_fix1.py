#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path('.pages-site').resolve()
checks: list[tuple[str, bool]] = []

def ck(name: str, ok: object) -> None:
    checks.append((name, bool(ok)))

def text(rel: str) -> str:
    return (root / rel).read_text('utf-8')

required = [
    '.nojekyll', 'index.html', '404.html', 'styles.css', 'app.js', 'config.js',
    'update-guard.js', 'sw.js', 'manifest.webmanifest', 'VERSION.txt',
    'CURRENT_BASELINE.json', 'release_config.json', 'assets/icon-192.png',
    'assets/icon-512.png', 'PAGES_ARTIFACT_MANIFEST.json'
]
for rel in required:
    ck('file:' + rel, (root / rel).is_file())
ck('version', text('VERSION.txt').strip() == 'V1.1 FIX1')
ck('config', all(token in text('config.js') for token in ["version: '1.1 FIX1'", "buildId: 'v1-1-fix1-cache36'", 'cacheEpoch: 36']))
ck('index-cache', 'v1-1-fix1-cache36' in text('index.html'))
ck('sw-cache', 'nine-cloud-dao-v1.1-fix1-cache36' in text('sw.js'))
app = text('app.js')
ck('casino-fix1-copy', all(token in app for token in ['100赔3320', '100:97.5', '正利润的50%', '领取70%', '30%']))
ck('casino-rpcs', 'rpc/play_house_game_v1_fix4' in app and 'rpc/place_fish_shrimp_bet_v1_fix4' in app)
ck('battle-preserved', '高低战力均可互相挑战' in app)
manifest = json.loads(text('PAGES_ARTIFACT_MANIFEST.json'))
ck('manifest-version', manifest.get('version') == 'V1.1 FIX1 CACHE36')
ck('manifest-build', manifest.get('clientBuild') == 'v1-1-fix1-cache36')
for entry in manifest.get('files', []):
    p = root / entry['path']
    ck('hash:' + entry['path'], p.is_file() and p.stat().st_size == entry['size'] and hashlib.sha256(p.read_bytes()).hexdigest() == entry['sha256'])
failed = [name for name, ok in checks if not ok]
print(json.dumps({'ok': not failed, 'checks': len(checks), 'failed': failed}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failed else 0)
