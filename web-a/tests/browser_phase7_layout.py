"""Chromium DOM layout checks without navigation, login, or cloud calls."""
from pathlib import Path
import os,shutil,re
from playwright.sync_api import sync_playwright
HTML=(Path(__file__).resolve().parent.parent/'site/index.html').read_text(encoding='utf8')
HTML=re.sub(r'<meta http-equiv="Content-Security-Policy"[^>]+>','',HTML)
HTML=re.sub(r'<script\b[^>]*>.*?</script>','',HTML,flags=re.S)
with sync_playwright() as p:
 browser=p.chromium.launch(executable_path=os.environ.get('CHROME_BIN',shutil.which('chromium') or '/usr/bin/chromium'),args=['--no-sandbox'])
 for width,height in [(320,640),(390,844),(430,932)]:
  page=browser.new_page(viewport={'width':width,'height':height})
  page.set_content(HTML)
  page.evaluate('''() => {
    document.getElementById('login-screen').hidden=true;
    document.getElementById('overlay').hidden=false;
    document.getElementById('page-entry').hidden=true;
    document.getElementById('page-history').hidden=false;
    const card=document.createElement('button');card.className='card history-card';
    card.innerHTML='<div class="row-info"><strong>七星彩</strong><span class="history-status tone-success"><span class="history-status-dot"></span>已完成</span></div><div class="sub">核验完成</div>';
    document.getElementById('history-list').replaceChildren(card);
    document.getElementById('modal-heading').textContent='任务 12345678';
    document.getElementById('modal-body').textContent='时间：2026-10-20 20:54\\n任务状态：成功\\n执行账号：七星彩';
    document.getElementById('modal-options').innerHTML='<h3>散码小票</h3><img class="ticket-image" width="1600" height="2300" src="data:image/svg+xml,%3Csvg xmlns=\\"http://www.w3.org/2000/svg\\" width=\\"1600\\" height=\\"2300\\"/%3E">';
    const actions=document.getElementById('modal-actions');actions.className='modal-actions history-detail-actions';
    for(const [i,label] of ['转发小票到微信','两张图片一起发微信','A 端人工核实 · 结案并通知 B 自动恢复接单','关闭'].entries()){
      let button=document.createElement('button');button.className='button '+(i===0?'primary':'ghost');button.textContent=label;if(i===2)button.disabled=true;actions.appendChild(button);
    }
  }''')
  report=page.evaluate('''() => {
    const box=s=>document.querySelector(s).getBoundingClientRect().toJSON();
    const a=[...document.querySelectorAll('.history-detail-actions button')].map(x=>x.getBoundingClientRect().toJSON());
    return {vw:innerWidth,cardStatusColor:getComputedStyle(document.querySelector('.history-status')).color,overlay:box('.overlay'),modal:box('.modal'),image:box('.ticket-image'),actions:a,scrollWidth:document.documentElement.scrollWidth};
  }''')
  assert report['cardStatusColor']=='rgb(27, 151, 105)',report
  assert 0<=report['modal']['x'] and report['modal']['right']<=width,report
  assert report['scrollWidth']<=width,report
  assert report['image']['right']<=report['modal']['right'],report
  assert all(b['right']<=report['modal']['right'] and b['x']>=report['modal']['x'] for b in report['actions']),report
  assert all(report['actions'][i]['bottom']<=report['actions'][i+1]['top'] for i in range(3)),report
  print(f'PASS: {width}x{height} history status green, modal/image/button containment and vertical stacking')
  page.close()
 browser.close()
