"""Offline intercepted Chromium smoke: no production Supabase access."""
import json,os,shutil
from pathlib import Path
from playwright.sync_api import sync_playwright
SITE=Path(__file__).resolve().parent.parent/'site'
UID='00000000-0000-4000-8000-000000000000'
TASK='11111111-1111-4111-8111-111111111111'
TINY_PNG=bytes.fromhex('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000b49444154789c636000020000050001a5f645400000000049454e44ae426082')
def exercise():
 with sync_playwright() as playwright:
  browser=playwright.chromium.launch(headless=True,executable_path=os.environ.get('CHROME_BIN',shutil.which('chromium') or '/usr/bin/chromium'),args=['--no-sandbox'])
  page=browser.new_page(viewport={'width':390,'height':844},accept_downloads=True)
  errors=[]
  page.on('pageerror',lambda err:errors.append(str(err)))
  def serve(route):
   request=route.request
   if request.url.startswith('https://wap.test/'):
    path=request.url.split('?',1)[0].removeprefix('https://wap.test/').strip('/') or 'index.html'
    file=(SITE/path).resolve()
    if not file.is_relative_to(SITE.resolve()) or not file.is_file():route.fulfill(status=404,body='missing asset');return
    ctype='text/html' if file.suffix=='.html' else 'application/javascript' if file.suffix=='.js' else 'application/octet-stream'
    route.fulfill(body=file.read_bytes(),content_type=ctype);return
   if 'supabase.co' not in request.url:route.abort();return
   path=request.url.split('supabase.co',1)[1]
   if '/storage/v1/object/authenticated/' in path:route.fulfill(body=TINY_PNG,content_type='image/png');return
   if '/auth/v1/token' in path:data={'access_token':'fake','refresh_token':'fake-refresh','expires_in':3600,'user':{'id':UID}}
   elif '/rpc/remote_claim_role' in path or '/rpc/remote_role_current' in path:data=True
   elif '/remote_tasks?' in path:
    data=[{'id':TASK,'target_account':'seven','status':'finished','message':'核验完成','created_at':'2026-10-20T20:54:00Z','result_path':UID+'/receipt.png','scatter_path':'','suite_path':''}]
   elif '/remote_stop_requests?' in path or '/remote_task_suite_items?' in path or '/remote_device_presence?' in path:data=[]
   else:data=[]
   route.fulfill(body=json.dumps(data),content_type='application/json',headers={'Date':'Wed, 21 Oct 2026 02:54:00 GMT'})
  page.route('**/*',serve)
  page.goto('https://wap.test/index.html',wait_until='networkidle')
  assert '阶段七' in page.title()
  page.locator('#login-email').fill('tester@example.com')
  page.locator('#login-password').fill('test-password')
  page.locator('#login-submit').click()
  page.get_by_role('button',name='确认登录').click()
  page.locator('[data-page="history"]').click()
  assert '阶段七' in page.locator('#wap-build-id').inner_text()
  card=page.locator('.history-card').first
  card.wait_for()
  assert card.locator('.history-status-dot').count()==1
  color=card.locator('.history-status').evaluate('(e)=>getComputedStyle(e).color')
  assert color=='rgb(27, 151, 105)',color
  card.click()
  page.locator('.ticket-image').wait_for()
  page.locator('.history-detail-actions .button').first.wait_for()
  boxes=page.evaluate("""() => ({vw:innerWidth,m:document.querySelector('.modal').getBoundingClientRect().toJSON(),actions:[...document.querySelectorAll('.history-detail-actions .button')].map(x=>x.getBoundingClientRect().toJSON()),img:document.querySelector('.ticket-image').getBoundingClientRect().toJSON()})""")
  assert boxes['m']['x']>=0 and boxes['m']['right']<=boxes['vw'],boxes
  assert all(x['x']>=boxes['m']['x'] and x['right']<=boxes['m']['right'] for x in boxes['actions']),boxes
  assert all(boxes['actions'][i]['bottom']<=boxes['actions'][i+1]['top'] for i in range(len(boxes['actions'])-1)),boxes
  assert boxes['img']['right']<=boxes['m']['right'],boxes
  assert page.locator('.history-detail-actions button:disabled').count()>=1
  page.locator('.history-detail-actions .button').last.click()
  page.locator('[data-page="entry"]').click()
  page.locator('#command').fill('0336各88组，全倒各1组')
  page.locator('#preview-input').click()
  page.locator('[data-filter="需确认"]').click()
  recognized=page.locator('#preview-rows').inner_text()
  assert '50元' in recognized and '38元' in recognized,recognized
  assert not errors,errors
  browser.close()
  print('PASS: Chromium offline mock green history, inline screenshot, stacked responsive buttons, filtered 50/38 preview')
if __name__=='__main__':exercise()
