"""Browser smoke with mock Supabase: never sends actual mutations, does not prove live integration."""
from pathlib import Path
import json, threading, time
from playwright.sync_api import sync_playwright
HERE=Path(__file__).resolve().parents[1]/'site'
origin='https://web-a.test/'
uid='11111111-1111-4111-8111-111111111111';now='2026-10-20T12:00:00Z'
reads=[]
def respond(route):
    url=route.request.url; method=route.request.method
    if method in ('PATCH','DELETE') or (method=='POST' and '/auth/' not in url and '/rpc/remote_claim_role' not in url and '/rpc/remote_role_current' not in url):
        raise AssertionError('Browser smoke unexpectedly attempted a mutation: '+url)
    reads.append((method,url))
    if '/auth/v1/token' in url: data={'access_token':'mock-jwt','refresh_token':'mock-refresh','expires_in':3600,'user':{'id':uid}}
    elif '/rpc/remote_claim_role' in url or '/rpc/remote_role_current' in url: data=True
    elif 'remote_device_presence' in url:data=[{'state':'idle','task_id':'','completed_items':0,'total_items':0,'seen_at':now}]
    elif 'remote_tasks' in url:data=[]
    elif 'remote_stop_requests' in url:data=[]
    else: data=[]
    route.fulfill(status=200,content_type='application/json',headers={'Date':'Tue, 20 Oct 2026 12:00:00 GMT','Access-Control-Expose-Headers':'Date','Access-Control-Allow-Origin':'*'},body=json.dumps(data))
try:
 with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox'])
    context=browser.new_context(viewport={'width':390,'height':844},device_scale_factor=1)
    context.route('https://wqhirteaemujeytsdpit.supabase.co/**',respond)
    def local(route):
        name=route.request.url.removeprefix(origin).split('?',1)[0].strip('/') or 'index.html'
        path=HERE/name
        if path.is_file() and path.resolve().is_relative_to(HERE):
            mime='text/html' if name.endswith('.html') else 'application/javascript' if name.endswith('.js') else 'text/plain'
            route.fulfill(status=200,body=path.read_bytes(),content_type=mime)
        else:route.fulfill(status=404,body='Not found')
    context.route(origin+'**',local)
    page=context.new_page(); errors=[];page.on('pageerror',lambda err:errors.append(str(err)))
    page.goto(origin,wait_until='load',timeout=25000)
    page.locator('#login-screen').wait_for(state='visible')
    page.locator('#login-email').fill('user@example.org');page.locator('#login-password').fill('sample-password')
    page.locator('#login-submit').click();page.get_by_text('确认 Web A 登录').wait_for()
    page.get_by_role('button',name='确认登录').click()
    page.locator('#login-screen').wait_for(state='hidden',timeout=12000)
    page.locator('#command').fill('1234-1234各1')
    page.locator('#preview-input').click()
    page.locator('#preview').wait_for(state='visible')
    assert '16笔' in page.locator('#preview-rows').inner_text()
    assert page.locator('#preview-send').is_disabled()
    page.locator('#preview-back').click()
    page.locator('#presence-refresh').click()
    page.get_by_role('button',name='任务',exact=True).click()
    page.locator('#tasks-stop').click();assert '禁止真实建单' in page.locator('#modal-body').inner_text()
    page.locator('#modal-actions button').first.click()
    page.get_by_role('button',name='历史',exact=True).click()
    page.locator('#history-list').wait_for()
    assert not errors,errors
    assert not any('/remote_tasks?select=*' in url and method=='POST' for method,url in reads)
    print('PASS: login lease, original parser, disabled send, task/stop and history navigation')
    browser.close()
finally:pass
