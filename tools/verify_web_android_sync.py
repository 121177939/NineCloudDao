#!/usr/bin/env python3
from pathlib import Path
import hashlib, re, sys

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / 'android/app/src/main/assets/game'
SHARED = [
    'CURRENT_BASELINE.json','VERSION.txt','app.js','b-equipment01.css','b-equipment01.js',
    'b-tianxu-v220.css','b-equipment-v210.css','b-equipment-v210.js',
    'b-secret-realm01.css','b-secret-realm01.js','b-tiandao-person-v220.css','b-tiandao-person-v220.js','b-exploration-v220.css','b-exploration-v220.js','b-spirit-beast-v250.css','b-spirit-beast-v250.js','b-world-boss01.css','b-world-boss01.js','b-sect-v2.css','b-sect-v2.js','b-technique-v220.css','b-technique-v220.js',
    'config.js','release_config.json','styles.css'
]
ASSETS = ['assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp']

def digest(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

def expected_android_index() -> str:
    s=(ROOT/'index.html').read_text(encoding='utf-8')
    s=re.sub(r'^\s*<link rel="manifest"[^\n]*\n','',s,flags=re.M)
    s=re.sub(r'^\s*<script src="update-guard\.js[^\n]*\n','',s,flags=re.M)
    s=re.sub(r'(<script src="config\.js[^\n]*</script>\n)',r'\1  <script src="android-local.js?v=android-local-r1"></script>\n',s,count=1)
    return s

errors=[]
for rel in SHARED + ASSETS:
    a=ROOT/rel; b=GAME/rel
    if not a.is_file() or not b.is_file(): errors.append(f'缺文件: {rel}'); continue
    if digest(a)!=digest(b): errors.append(f'网页/Android内容不一致: {rel}')
if (GAME/'index.html').read_text(encoding='utf-8') != expected_android_index():
    errors.append('Android index.html 不是网页index的规定本地化变体')
web_version=(ROOT/'VERSION.txt').read_text(encoding='utf-8').splitlines()[0].strip()
android_version=(GAME/'VERSION.txt').read_text(encoding='utf-8').splitlines()[0].strip()
if web_version != android_version: errors.append(f'版本不一致: web={web_version}, android={android_version}')

if errors:
    for e in errors: print('FAIL',e)
    sys.exit(1)
print(f'PASS 网页/Android共享资源同步：{len(SHARED)+len(ASSETS)}个文件 + Android index变体；版本={web_version}')
