from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve(); checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
def txt(p): return (root/p).read_text('utf-8')
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for f in required: ck('file:'+f,(root/f).is_file())
ck('version',txt('VERSION.txt').strip()=='V0.14.2')
ck('html-version',all('0.14.2' in txt(f) for f in ['index.html','404.html']))
ck('config-version',"version: '0.14.2'" in txt('config.js'))
ck('sw-cache','nine-cloud-dao-v0.14.2-cache6' in txt('sw.js'))
ck('html-cache-build',all(t in txt('index.html') for t in ['styles.css?v=0142-cache6','update-guard.js?v=0142-cache6','app.js?v=0142-cache6']))
ck('guard-rpc','get_jiuxiao_app_release_control_v1' in txt('update-guard.js'))
ck('world-feed-sort','sortWorldEventEntriesNewestFirst' in txt('app.js') and 'feed_sequence' in txt('app.js'))
for banned in ['.git','.github','database','docs','tools']: ck('not-deployed:'+banned,not (root/banned).exists())
for ext in ['*.sql','*.py','*.zip']: ck('no:'+ext,not list(root.rglob(ext)))
m=json.loads(txt('PAGES_ARTIFACT_MANIFEST.json')); ck('manifest.version',m.get('version')=='V0.14.2' and m.get('clientBuild')=='v0142-cache6')
for e in m.get('files',[]):
 p=root/e['path']; ck('hash:'+e['path'],p.is_file() and p.stat().st_size==e['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==e['sha256'])
failed=[x for x in checks if not x[1]]
for n,o,d in checks: print(('PASS' if o else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
