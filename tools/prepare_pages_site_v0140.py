from pathlib import Path
import hashlib, json, shutil, sys

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path.cwd()
out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else root / '.pages-site'
if out == root or root in out.parents and out.name in ('', '.'):
    raise SystemExit('REFUSE_UNSAFE_OUTPUT')
if out.exists():
    shutil.rmtree(out)
out.mkdir(parents=True)

files = [
    '.nojekyll','index.html','404.html','styles.css','app.js','config.js','sw.js',
    'manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
    'assets/icon-192.png','assets/icon-512.png'
]
manifest=[]
for rel in files:
    source=root/rel
    if not source.is_file():
        raise SystemExit(f'MISSING_PAGE_FILE:{rel}')
    target=out/rel
    target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,target)
    data=target.read_bytes()
    manifest.append({'path':rel,'size':len(data),'sha256':hashlib.sha256(data).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':'V0.14.0','files':manifest}, ensure_ascii=False, indent=2) + chr(10), 'utf-8')
print(f'PAGES_SITE_BUILT files={len(manifest)+1} output={out}')
