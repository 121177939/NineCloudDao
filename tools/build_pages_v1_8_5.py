#!/usr/bin/env python3
from pathlib import Path
import hashlib
import json
import shutil
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
out = Path(sys.argv[2] if len(sys.argv) > 2 else '.pages-site').resolve()
build_id = 'v1-8-5-cache86-casinogate1'
label = 'V1.8.5 CACHE86'
required = [
    '.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js',
    'manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
    'b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css',
    'b-secret-realm01.js','b-secret-realm01.css','b-sect-v2.js','b-sect-v2.css',
    'paigow-realtime.js','paigow-app.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css',
    'b-paigow02-ui.js','assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp'
]
missing = [rel for rel in required if not (root / rel).is_file()]
if missing:
    raise SystemExit('MISSING_REQUIRED_FILES:' + ','.join(missing))

for rel in ['gm-admin.html','gm-admin.css','gm-admin.js','gm-operations.html','GM入口说明.txt']:
    if (root / rel).exists():
        raise SystemExit(f'LOCAL_GM_ASSET_NOT_ALLOWED_IN_PUBLIC_PAGES:{rel}')

def text(rel: str) -> str:
    return (root / rel).read_text('utf-8')

app = text('app.js')
paigow = text('paigow-app.js')
sw = text('sw.js')
baseline = json.loads(text('CURRENT_BASELINE.json'))
release = json.loads(text('release_config.json'))
fixed_notice = '服务器检查到当前游戏进行非法活动，已暂停此项功能。'
checks = {
    'version': text('VERSION.txt').splitlines()[0].strip() == label and build_id in text('VERSION.txt'),
    'config': all(t in text('config.js') for t in [f"releaseLabel: '{label}'", f"buildId: '{build_id}'", 'cacheEpoch: 86']),
    'baseline': baseline.get('sourceBaseline') == 'V1.8.4 CACHE85' and baseline.get('clientHotfix') == 'CASINO_GATE01' and baseline.get('gmVersion') == 'ADMIN9 R16',
    'database': baseline.get('nextSqlNumber') == 199 and str(baseline.get('sqlRevision')) == '198',
    'casino-status-rpc': 'get_casino_feature_switch_v198' in app and 'refreshCasinoFeatureSwitchV198' in app,
    'casino-entry-gate': "target === 'casino'" in app and 'requireCasinoEnabledV198' in app,
    'casino-paigow-gate': 'assertCasinoEnabledV198' in paigow and fixed_notice in paigow,
    'casino-fixed-notice': fixed_notice in app,
    'heartbeat': 'PERF_E80.heartbeatMs' in app and 'heartbeatMs: 30 * 1000' in app,
    'polling': all(t in app for t in ['cultivationSyncMs: 60 * 1000','opportunityPollMs: 60 * 1000','worldEventsSyncMs: 60 * 1000','divineNoticeSyncMs: 60 * 1000']),
    'on-demand': all(t in app for t in ['refreshActiveTabDataE80','洞府、功法、红尘、宗门不再全局轮询','resumeCooldownMs: 15 * 1000']),
    'games-preserved': all((root / x).is_file() for x in ['b-paigow01.js','b-paigow01.html','paigow-app.js']) and 'rpcGetFishShrimpStateV0148' in app,
    'cache': 'nine-cloud-dao-v1.8.5-cache86-casinogate1' in sw and build_id in sw,
    'no-secrets': 'sb_secret_' not in '\n'.join(text(x) for x in ['app.js','config.js','index.html']).lower(),
    'sect-preserved': all((root / x).is_file() for x in ['b-sect-v2.js','b-sect-v2.css']) and 'function tabNav()' in text('b-sect-v2.js') and 'function metric(label, value' in text('b-sect-v2.js'),
    'deployment': release.get('deploymentAllowed') is True and release.get('gmPublicDeployment') is False,
}
failed = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    print(('PASS ' if v else 'FAIL ') + k)
if failed:
    raise SystemExit('VERSION_CHECK_FAILED:' + ','.join(failed))

if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
    src = root / rel
    dst = out / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

manifest = []
for path in sorted(x for x in out.rglob('*') if x.is_file()):
    manifest.append({
        'path': path.relative_to(out).as_posix(),
        'size': path.stat().st_size,
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
    })
(out / 'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({
    'version': label,
    'clientBuild': build_id,
    'deploymentAllowed': True,
    'gmDeliveryMode': 'local_only',
    'files': manifest,
}, ensure_ascii=False, indent=2) + '\n', 'utf-8')
print(f'{label} public production pages build PASS files={len(manifest)}')
