#!/usr/bin/env python3
"""九霄问道 Android release preflight.

Never hard-code a CACHE number here. The validator derives the expected release
from CURRENT_BASELINE.json / PROJECT_MANIFEST.json / gradle.properties so a
normal client version bump cannot leave CI pinned to an older release.
"""
from __future__ import annotations
import hashlib, json, re, sys
from pathlib import Path

ANDROID = Path(__file__).resolve().parents[1]
MONO = ANDROID.parent
GAME = ANDROID / 'app/src/main/assets/game'
BASELINE_FILE = MONO / 'CURRENT_BASELINE.json' if (MONO/'CURRENT_BASELINE.json').is_file() else GAME/'CURRENT_BASELINE.json'
PROJECT_FILE = ANDROID/'PROJECT_MANIFEST.json'
ERRORS=[]

def fail(msg): ERRORS.append(msg)
def read_json(path):
    try: return json.loads(path.read_text('utf-8'))
    except Exception as e: fail(f'无法读取 {path}: {e}'); return {}
def props(path):
    out={}
    for line in path.read_text('utf-8').splitlines():
        t=line.strip()
        if not t or t.startswith('#') or '=' not in t: continue
        k,v=t.split('=',1); out[k.strip()]=v.strip()
    return out

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()

required=[
    ANDROID/'gradlew', ANDROID/'gradle/wrapper/gradle-wrapper.jar',
    ANDROID/'gradle/wrapper/gradle-wrapper.properties', ANDROID/'settings.gradle.kts',
    ANDROID/'build.gradle.kts', ANDROID/'gradle.properties', ANDROID/'app/build.gradle.kts',
    ANDROID/'app/src/main/AndroidManifest.xml', GAME/'index.html', GAME/'CURRENT_BASELINE.json',
    GAME/'VERSION.txt', GAME/'b-tiandao-person-v220.js', GAME/'b-exploration-v220.js'
]
for p in required:
    if not p.is_file(): fail(f'缺少必需文件: {p.relative_to(ANDROID)}')
if ERRORS:
    print('\n'.join('FAIL '+x for x in ERRORS)); sys.exit(1)

baseline=read_json(BASELINE_FILE); project=read_json(PROJECT_FILE); gp=props(ANDROID/'gradle.properties')
version_code=int(gp.get('APP_VERSION_CODE','0') or 0); version_name=gp.get('APP_VERSION_NAME','')
expected_code=int(baseline.get('androidVersionCode') or project.get('versionCode') or 0)
expected_name=str(baseline.get('androidVersionName') or project.get('versionName') or '')
build_id=str(baseline.get('buildId') or baseline.get('clientBuild') or project.get('gameBuildId') or '')
release_label=str(baseline.get('releaseLabel') or project.get('version') or '')

if gp.get('APP_ID')!='com.jiuxiaowendao.game': fail('APP_ID 不是正式包名 com.jiuxiaowendao.game')
if version_code!=expected_code: fail(f'APP_VERSION_CODE={version_code} 与当前基线 {expected_code} 不一致')
if version_name!=expected_name: fail(f'APP_VERSION_NAME={version_name} 与当前基线 {expected_name} 不一致')
if project:
    if int(project.get('versionCode',0))!=version_code: fail('PROJECT_MANIFEST versionCode 与 gradle.properties 不一致')
    if str(project.get('versionName',''))!=version_name: fail('PROJECT_MANIFEST versionName 与 gradle.properties 不一致')
    if str(project.get('gameBuildId',''))!=build_id: fail('PROJECT_MANIFEST gameBuildId 与 CURRENT_BASELINE 不一致')
embedded=read_json(GAME/'CURRENT_BASELINE.json')
if embedded.get('buildId')!=build_id: fail('APK内置 CURRENT_BASELINE buildId 与当前基线不一致')
if embedded.get('androidVersionCode')!=version_code: fail('APK内置 CURRENT_BASELINE versionCode 与 gradle.properties 不一致')
version_text=(GAME/'VERSION.txt').read_text('utf-8')
if release_label and release_label not in version_text: fail('APK内置 VERSION.txt 缺当前 releaseLabel')
if build_id and build_id not in version_text: fail('APK内置 VERSION.txt 缺当前 buildId')
app_gradle=(ANDROID/'app/build.gradle.kts').read_text('utf-8')
if build_id and build_id not in app_gradle: fail('app/build.gradle.kts GAME_BUILD_ID 不是当前基线')
if 'compileSdk = 34' not in app_gradle or 'targetSdk = 34' not in app_gradle: fail('Android SDK 基线不是 34')
wrapper=(ANDROID/'gradle/wrapper/gradle-wrapper.properties').read_text('utf-8')
if 'gradle-8.2.1-bin.zip' not in wrapper: fail('Gradle wrapper 不是已锁定的 8.2.1')
expected_wrapper='613f321ad9687358566e3b3322bc789e4347f871823e4ca29e8b6e3b6ade4703'
if digest(ANDROID/'gradle/wrapper/gradle-wrapper.jar')!=expected_wrapper: fail('gradle-wrapper.jar SHA256 不符合锁定值')
# Signing files must not be committed; workflow injects them only after this preflight.
for rel in ['release.keystore','signing.properties','app/release.keystore','app/signing.properties']:
    if (ANDROID/rel).exists(): fail(f'仓库不应包含签名敏感文件: {rel}')
# Secret boundary.
secret_re=re.compile(r'CLOUDFLARE_AUTH_TOKEN\s*=|CLOUDFLARE_ACCOUNT_ID\s*=')
for p in GAME.rglob('*'):
    if p.is_file() and p.suffix.lower() in {'.js','.html','.json','.txt','.css'}:
        try:
            if secret_re.search(p.read_text('utf-8',errors='ignore')): fail(f'客户端发现 Cloudflare Secret 名值边界风险: {p.relative_to(GAME)}')
        except OSError: pass
# Feature contracts are semantic, never tied to one CACHE number.
people=(GAME/'b-tiandao-person-v220.js').read_text('utf-8')
for marker in ['tp-free-talk-input','data-tp-free-send','本地人格兜底']:
    if marker not in people: fail(f'天道人物交谈能力标记缺失: {marker}')
if "prompt('你想亲自对TA说什么？'" in people: fail('自由交谈仍使用浏览器原生 prompt')
explore=(GAME/'b-exploration-v220.js').read_text('utf-8')
for marker in ['B-EXPLORATION-V01','get_exploration_hub_v262','exploration_start_v262','exploration_choose_v262']:
    if marker not in explore: fail(f'九霄游历能力标记缺失: {marker}')

if ERRORS:
    for e in ERRORS: print('FAIL',e)
    sys.exit(1)
print(f'PASS Android dynamic preflight: {release_label} / {version_code} / {version_name}')
print(f'PASS buildId: {build_id}')
print('PASS validator derives version from current baseline; no CACHE hard-code release pin')
