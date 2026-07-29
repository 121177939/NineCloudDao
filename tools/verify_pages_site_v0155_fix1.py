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
    return (root / rel).read_text('utf-8')

required = [
    '.nojekyll', 'index.html', '404.html', 'styles.css', 'app.js', 'config.js',
    'update-guard.js', 'sw.js', 'manifest.webmanifest', 'VERSION.txt',
    'CURRENT_BASELINE.json', 'release_config.json', 'assets/icon-192.png',
    'assets/icon-512.png', 'PAGES_ARTIFACT_MANIFEST.json'
]
for rel in required:
    ck(f'file:{rel}', (root / rel).is_file())

ck('version', txt('VERSION.txt').strip() == 'V0.15.5')
ck('config-version', "version: '0.15.5'" in txt('config.js'))
ck('build', 'v0155-fix1-cache27' in txt('config.js'))
ck('epoch', 'cacheEpoch: 27' in txt('config.js'))
ck('index-cache', '0155-fix1-cache27' in txt('index.html'))
ck('service-worker-cache', 'nine-cloud-dao-v0.15.5-fix1-cache27' in txt('sw.js'))

app = txt('app.js')
css = txt('styles.css')
ck('yuanshen', all(x in app for x in [
    'primordialSpiritPanelHtmlV0155', 'data-mobile-screen="primordial"', '战斗属性数值系统接入中'
]))
ck('yuanshen-animation', all(x in css for x in [
    '.yuanshen-mandala-v0155', '@keyframes yuanshen-levitate-v0155', '@keyframes yuanshen-meridian-v0155'
]))
ck('b-cave', all(x in app for x in ['cave-scene-b01', 'CAVE_STORAGE_SLOT_COUNT_B01 = 30']))
ck('cave-visual-fix1', all(x in app + css for x in [
    'cave-rock-arch-b01', 'cave-spirit-veins-b01', 'cave-stone-platform-b01', '洞天幽居 · 灵脉自运'
]))
ck('cave-no-mandala-rotation', 'caveRingB01' not in css)

manifest = json.loads(txt('PAGES_ARTIFACT_MANIFEST.json'))
ck('manifest-version', manifest.get('version') == 'V0.15.5 FIX1')
ck('manifest-build', manifest.get('clientBuild') == 'v0155-fix1-cache27')
for entry in manifest.get('files', []):
    path = root / entry['path']
    ck(
        f"hash:{entry['path']}",
        path.is_file()
        and path.stat().st_size == entry['size']
        and hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256']
    )

failed = [name for name, ok in checks if not ok]
print(json.dumps({'ok': not failed, 'checks': len(checks), 'failed': failed}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failed else 0)
