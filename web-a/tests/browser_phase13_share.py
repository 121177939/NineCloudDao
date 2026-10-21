from pathlib import Path
import re,os,shutil
from playwright.sync_api import sync_playwright
p=Path(__file__).resolve().parent.parent/'site/app.js'
html=(p.parent/'index.html').read_text();html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]+>','',html);html=re.sub(r'<script\b[^>]*>.*?</script>','',html,flags=re.S)
script=p.read_text();fragment=script[script.index('function makeImageFiles('):script.index('\nasync function showTaskDetail(',script.index('function makeImageFiles('))]
with sync_playwright() as pw:
 b=pw.chromium.launch(executable_path=shutil.which('chromium') or '/usr/bin/chromium',args=['--no-sandbox'])
 for w,h in [(320,640),(390,844),(430,932)]:
  page=b.new_page(viewport={'width':w,'height':h});page.set_content(html)
  page.evaluate('''() => {
    window.$=id=>document.getElementById(id);window.state={activeObjectUrls:[]};window.imageExtension=()=> 'png';window.safeFilePart=x=>x;
    window.modal=(title,description,actions)=>{
      document.querySelector('#overlay').hidden=false;
      document.querySelector('#modal-heading').textContent=title;
      document.querySelector('#modal-body').textContent=description;
      const opts=document.querySelector('#modal-options');opts.replaceChildren();
      const host=document.querySelector('#modal-actions');host.replaceChildren();
      for(const action of actions){const b=document.createElement('button');b.className='button';b.textContent=action.label;b.addEventListener('click',()=>action.onClick?.());host.append(b);}
    };
    window.__shareCalls=[];
    Object.defineProperty(navigator,'canShare',{configurable:true,value:({files})=>files?.length>0});
    Object.defineProperty(navigator,'share',{configurable:true,value:(data)=>{window.__shareCalls.push({files:data.files?.length,url:data.url,title:data.title});return Promise.resolve();}});
    window.__tests={};
  }''')
  page.evaluate("src => { (0, eval)(src); }",fragment)
  page.evaluate('''() => {const blob=new Blob(['FAKE TEST IMAGE'],{type:'image/png'});window.imageShareDialog([new File([blob],'fixture.png',{type:blob.type})],'test-task-id');}''')
  data=page.evaluate('''() => {const r=s=>document.querySelector(s)?.getBoundingClientRect().toJSON();return {scrollWidth:document.documentElement.scrollWidth,modal:r('.modal'),img:r('#modal-options img'),links:[...document.querySelectorAll('#modal-options a[download]')].length,text:document.getElementById('modal-body').textContent,buttons:[...document.querySelectorAll('#modal-actions button')].map(x=>x.textContent)}}''')
  assert data['scrollWidth']<=w and data['modal']['left']>=0 and data['modal']['right']<=w,data
  assert data['img']['left']>=0 and data['img']['right']<=w and data['links']==1,data
  assert '不要使用浏览器菜单' in data['text'] and '系统分享图片' in data['buttons'],data
  page.get_by_role('button',name='系统分享图片').click()
  result=page.evaluate('window.__shareCalls')
  assert result==[{'files':1,'url':None,'title':None}],result
  print(f'PASS: {w}x{h} image preview/download and user-click file-only WebShare; no URL-card payload')
  page.close()
 b.close()
