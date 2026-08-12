#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys, re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve(); out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-2-0-cache137-destiny-cultivation-root-admin40-sql265-gated'; label='V2.2.0 CACHE137'
required=[
'.nojekyll','index.html','404.html','styles.css','b-tianxu-v220.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
'b-equipment01.js','b-equipment01.css','b-equipment-v210.js','b-equipment-v210.css','b-secret-realm01.js','b-secret-realm01.css','b-world-boss01.js','b-world-boss01.css','b-sect-v2.js','b-sect-v2.css','b-technique-v220.js','b-technique-v220.css','b-tiandao-person-v220.js','b-tiandao-person-v220.css','b-exploration-v220.js','b-exploration-v220.css',
'assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp']
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
def text(x): return (root/x).read_text('utf-8')
idx=text('index.html'); people=text('b-tiandao-person-v220.js'); explore=text('b-exploration-v220.js'); sw=text('sw.js'); baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
sql262=root/'database-upgrades/SQL262_JIUXIAO_EXPLORATION/01_SQL262_V2.2.0_CACHE134_九霄游历300故事_天道人物自然对话_执行即门禁.sql'
sql262_text=sql262.read_text('utf-8') if sql262.is_file() else ''
sql263=root/'database-upgrades/SQL263_TIANDAO_AI_MULTI_MODEL_ROUTER/01_SQL263_V2.2.0_CACHE135_B模块天道AI多模型调度器_ADMIN9_R39_执行即门禁.sql'
sql263_text=sql263.read_text('utf-8') if sql263.is_file() else ''
sql264=root/'database-upgrades/SQL264_HEAVEN_CONTROL_TIANDAO_COMPANION_CULTIVATION/01_SQL264_R3_V2.2.0_CACHE136_天道固定_权威修炼链_NPC道侣最终1点5倍_修复source_type约束_ADMIN9_R40_执行即门禁.sql'
sql264_text=sql264.read_text('utf-8') if sql264.is_file() else ''
sql265=root/'database-upgrades/SQL265_DESTINY_CULTIVATION_SPIRIT_ROOT/01_SQL265_V2.2.0_CACHE137_天命榜修为榜显示玩家当前灵根_执行即门禁.sql'
sql265_text=sql265.read_text('utf-8') if sql265.is_file() else ''
catalog=json.loads(text('exploration-story-catalog-v262.json'))
checks={
'version':text('VERSION.txt').splitlines()[0]==label and build in text('VERSION.txt'),
'pages-lock':'PAGES_DEPLOY prebuilt-pages-directory-official-artifact-r1' in text('VERSION.txt'),
'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 137']),
'release-json':release.get('releaseLabel')==label and release.get('cacheEpoch')==137 and release.get('buildId')==build and release.get('nextSqlNumber')==266 and release.get('gmVersion')=='ADMIN9 R40' and release.get('runtimeDatabaseGate')=='SQL265_GATE_PASSED' and 'SQL265 READY' in release.get('databaseRelease','') and 'R6' in release.get('edgeFunction',''),
'baseline-json':baseline.get('releaseLabel')==label and baseline.get('nextSqlNumber')==266 and 'SQL265' in baseline.get('sqlRevision','') and baseline.get('gmVersion')=='ADMIN9 R40' and baseline.get('androidVersionCode')==2001516,
'index-cache-bust':build in idx and '<!-- version: V2.2.0 CACHE137 -->' in idx and 'b-exploration-v220.js' in idx,
'exploration-nav':all(x in text('app.js') for x in ["['explore', '游', '游历']",'data-mobile-screen="explore"','jiuxiao:exploration-rendered','B_EXPLORATION_V262']),
'exploration-module':all(x in explore for x in ['B-EXPLORATION-V01','get_exploration_hub_v262','exploration_start_v262','exploration_choose_v262','游历志','旅囊']),
'story-catalog':catalog.get('story_total')==300 and catalog.get('realm_specific')==240 and catalog.get('cross_realm')==60 and len(catalog.get('regions',[]))==8 and len(catalog.get('stories',[]))==300,
'natural-ai-ui':all(x in people for x in ['tp-free-talk-input','data-tp-free-send','GLM AI','Cloudflare AI','本地人格兜底']) and "prompt('你想亲自对TA说什么？'" not in people,
'sql262':all(x in sql262_text for x in ['SQL262_GATE_PASSED','exploration_story_defs_v262','get_exploration_hub_v262','exploration_start_v262','exploration_choose_v262','server_personality_v1','SQL262_GATE_STORY_COUNT']),
'sql263':all(x in sql263_text for x in ['SQL263_GATE_PASSED','admin9_get_tiandao_ai_router_v263','zhipu_glm','cloudflare_workers_ai','server_personality_v1']),
'sql264-r3':all(x in sql264_text for x in ['SQL264_GATE_PASSED','SQL264 R3','tiandao_companion','character_cultivation_effects_source_type_check']),
'sql265':all(x in sql265_text for x in ['SQL265_GATE_PASSED','get_destiny_ranking_v265','get_destiny_ranking_v1','character_spirit_roots','spirit_root_name']),
'client-ranking-root':all(x in text('app.js') for x in ["rpc/get_destiny_ranking_v265",'spirit_root_name','灵根「']),
'client-companion15':all(x in text('app.js') for x in ['tiandao_companion_v264','NPC道侣同修','companionMultiplierV264','jiuxiao:tiandao-companion-changed']),
'memory-abi':"pg_get_function_result(to_regprocedure('public.tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb)'))<>'void'" in sql262_text,
'cloudflare-client-secret-absent':not re.search(r'CLOUDFLARE_AUTH_TOKEN\s*=|CLOUDFLARE_ACCOUNT_ID\s*=', idx+people+explore+text('config.js')),
'sw-cache137':build in sw and 'b-exploration-v220.js' in sw,
'pc-nav-drag':all(x in text('app.js') for x in ['is-mouse-dragging','pointerdown','setPointerCapture','lastWheelPageAt','snapToNearestPage']),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
if failed: raise SystemExit('FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
 src=root/rel; dst=out/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
files=[]
for p in sorted(x for x in out.rglob('*') if x.is_file()): files.append({'path':p.relative_to(out).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build,'requiredDatabaseGate':'SQL265_GATE_PASSED','files':files},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'{label} Pages artifact PASS files={len(files)}')
