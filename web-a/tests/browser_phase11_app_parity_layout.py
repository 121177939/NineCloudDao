"""Offline Chromium DOM geometry for APP-aligned send dialogs and STOP progress.
Does not log in, call Supabase, or create a real task.
"""
from pathlib import Path
import os, re, shutil
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
          const overlay=document.getElementById('overlay');overlay.hidden=false;
          document.getElementById('modal-heading').textContent='发送任务';
          document.getElementById('modal-body').textContent='请选择要发送的账号';
          const opts=document.getElementById('modal-options');opts.className='account-choice-list';opts.replaceChildren();
          for(const [label,active] of [['排列',true],['七星',false],['两个一起',false]]){
            const card=document.createElement('button');card.className='account-choice'+(active?' selected':'');card.setAttribute('role','radio');card.setAttribute('aria-checked',String(active));
            card.innerHTML='<span class="account-choice-radio">'+(active?'◉':'○')+'</span><span class="account-choice-label">'+label+'</span>';opts.append(card);
          }
          const actions=document.getElementById('modal-actions');actions.className='modal-actions';actions.replaceChildren();
          ['取消','下一步'].forEach((t,i)=>{const x=document.createElement('button');x.className='button'+(i?' primary':' ghost');x.textContent=t;actions.appendChild(x);});
          const stop=document.getElementById('stop-progress');stop.hidden=false;stop.textContent='等待 B 对准确 STOP 版本确认停止\\n请求 ID：11111111-1111-4111-8111-111111111111';
        }''')
        report=page.evaluate('''() => {
          const rect=(s)=>document.querySelector(s).getBoundingClientRect().toJSON();
          return {width:innerWidth,scrollWidth:document.documentElement.scrollWidth,preview:rect('#preview'),footer:rect('.preview-footer'),modal:rect('.modal'),cards:[...document.querySelectorAll('.account-choice')].map(n=>n.getBoundingClientRect().toJSON()),actions:[...document.querySelectorAll('#modal-actions .button')].map(n=>n.getBoundingClientRect().toJSON()),stop:rect('#stop-progress')};
        }''')
        assert report['scrollWidth']<=w,report
        assert report['modal']['left']>=0 and report['modal']['right']<=w,report
        assert all(b['left']>=report['modal']['left'] and b['right']<=report['modal']['right'] for b in report['cards']+report['actions']),report
        assert all(report['cards'][i]['bottom']<=report['cards'][i+1]['top'] for i in range(2)),report
        assert all(report['actions'][i]['right']<=report['modal']['right'] for i in range(2)),report
        assert report['stop']['left']>=0 and report['stop']['right']<=w,report
        # The second native dialog is the five-row send summary followed by Back / Confirm.
        page.evaluate('''() => {
          const opts=document.getElementById('modal-options');opts.className='';opts.replaceChildren();
          const card=document.createElement('div');card.className='send-summary-card';
          for(const [label,value] of [['发送账号','排列'],['任务类型','普通 11 条 · 全转 10 条'],['预计金额','488元'],['套码截图','不适用'],['转换倍率','关闭']]){
            const row=document.createElement('div');row.className='send-summary-row';
            const a=document.createElement('span');a.className='send-summary-name';a.textContent=label;
            const b=document.createElement('span');b.className='send-summary-value';b.textContent=value;
            row.append(a,b);card.append(row);
          }
          opts.append(card);
          const actions=document.getElementById('modal-actions');actions.className='modal-actions';actions.replaceChildren();
          ['返回修改','确认发送'].forEach((t,i)=>{const x=document.createElement('button');x.className='button'+(i?' primary':' ghost');x.textContent=t;actions.appendChild(x);});
        }''')
        summary=page.evaluate('''() => ({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,modal:document.querySelector('.modal').getBoundingClientRect().toJSON(),card:document.querySelector('.send-summary-card').getBoundingClientRect().toJSON(),rows:[...document.querySelectorAll('.send-summary-row')].map(n=>n.getBoundingClientRect().toJSON()),buttons:[...document.querySelectorAll('#modal-actions .button')].map(n=>n.getBoundingClientRect().toJSON())})''')
        assert summary['scrollWidth']<=w and summary['modal']['left']>=0 and summary['modal']['right']<=w,summary
        assert len(summary['rows'])==5 and all(r['left']>=summary['modal']['left'] and r['right']<=summary['modal']['right'] for r in summary['rows']),summary
        assert all(b['left']>=summary['modal']['left'] and b['right']<=summary['modal']['right'] for b in summary['buttons']),summary
        print(f'PASS: {w}x{h} APP account cards, five-row summary, fixed actions, concise preview and STOP progress fit viewport')
        page.close()
    browser.close()
