"""Offline Chromium DOM geometry; does not execute JS, Supabase, or real tasks."""
from pathlib import Path
import os,re,shutil
from playwright.sync_api import sync_playwright
html=(Path(__file__).resolve().parent.parent/'site/index.html').read_text()
html=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]+>','',html)
html=re.sub(r'<script\b[^>]*>.*?</script>','',html,flags=re.S)
with sync_playwright() as p:
    browser=p.chromium.launch(executable_path=os.getenv('CHROME_BIN',shutil.which('chromium') or '/usr/bin/chromium'),args=['--no-sandbox'])
    for w,h in [(320,640),(390,844),(430,932)]:
        page=browser.new_page(viewport={'width':w,'height':h})
        page.set_content(html)
        page.evaluate('''() => {
          document.getElementById('login-screen').hidden=true;
          document.getElementById('preview').hidden=false;
          document.getElementById('navbar').hidden=true;
          document.getElementById('original-title').textContent='原始内容（共 91 字）';
          document.getElementById('original-text').textContent='0336各88组，全倒各1组，\\n8052、5082、0396、2096、4096、8036各18组，全倒0.5组';
          document.getElementById('result-count').textContent='识别结果（散码 11 组 · 全转 10 组 · 套码 0 条）';
          const host=document.getElementById('preview-rows'); host.replaceChildren();
          const a=document.createElement('div');a.className='preview-card';
          a.innerHTML='<strong>散码区</strong><div class="preview-detail preview-raw">原文：0336，0336，8052，5082，0396，2096，4096，8036，8X3X，X036，803X</div><div class="preview-detail preview-recognized">识别：0336各50元；0336各38元；8052、5082、0396、2096、4096、8036各18元；8X3X各20元；X036、803X各10元</div>';
          const b=document.createElement('div');b.className='preview-card';
          b.innerHTML='<strong>全转区（10条独立执行项）</strong><div class="preview-detail preview-recognized">第3组 · 0336 · 全转 · 各1元（预计12码）</div><div class="preview-detail preview-recognized">第10组 · 8052 · 全转 · 各0.5元（预计24码）</div>';
          host.append(a,b);
          document.getElementById('overlay').hidden=false;
          document.getElementById('modal-heading').textContent='发送任务 · 选择账号';
          document.getElementById('modal-body').textContent='任务发送前必须核对账号与原文。';
          const actions=document.getElementById('modal-actions');actions.className='modal-actions send-choice-actions';
          ['返回','排列五','七星彩','排列五＋七星彩'].forEach(t=>{const x=document.createElement('button');x.className='button';x.textContent=t;actions.appendChild(x);});
        }''')
        report=page.evaluate('''() => {
          const rect=(s)=>document.querySelector(s).getBoundingClientRect().toJSON();
          return {width:innerWidth,scrollWidth:document.documentElement.scrollWidth,preview:rect('#preview'),footer:rect('.preview-footer'),modal:rect('.modal'),buttons:[...document.querySelectorAll('.send-choice-actions .button')].map(n=>n.getBoundingClientRect().toJSON())};
        }''')
        assert report['scrollWidth']<=w,report
        assert report['modal']['left']>=0 and report['modal']['right']<=w,report
        assert all(b['left']>=report['modal']['left'] and b['right']<=report['modal']['right'] for b in report['buttons']),report
        assert all(report['buttons'][i]['bottom']<=report['buttons'][i+1]['top'] for i in range(3)),report
        print(f'PASS: {w}x{h} concise preview and vertical send-account dialog without overflow')
        page.close()
    browser.close()
