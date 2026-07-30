#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
room_id = '11111111-1111-4111-8111-111111111111'
lobby_calls = {'count': 0}

lobby_room = {
    'id': room_id,
    'slot_no': 1,
    'name': '天字一号房',
    'duel_type': 'pvp',
    'pvp_mode': 'rob',
    'game_mode': 'small',
    'stake_type': 'spirit_stone',
    'base_stake': 20,
    'status': 'playing',
    'expires_at': '2099-01-01T00:00:00Z',
    'players': 2,
    'spectators': 0,
    'capacity': 9,
    'joined': True,
}

room_state = {
    'room': {
        'id': room_id,
        'room_name': '天字一号房',
        'duel_type': 'pvp',
        'pvp_mode': 'rob',
        'game_mode': 'small',
        'stake_type': 'spirit_stone',
        'base_stake': 20,
        'status': 'playing',
    },
    'members': [
        {'character_id': 'c1', 'name': '顾长风', 'role': 'player', 'seat_no': 1, 'is_self': True, 'is_owner': True, 'ready': True},
        {'character_id': 'c2', 'name': '沈青禾', 'role': 'player', 'seat_no': 2, 'is_self': False, 'is_owner': False, 'ready': True},
    ],
    'self_member': {'character_id': 'c1', 'name': '顾长风', 'role': 'player', 'seat_no': 1, 'is_self': True, 'is_owner': True, 'ready': True},
    'self_balance': 88888,
    'bankroll_balance': 100000000,
    'round': {
        'round_no': 1,
        'phase': 'multiplier',
        'phase_deadline': '2099-01-01T00:00:00Z',
        'players': [
            {'character_id': 'c1', 'name': '顾长风', 'seat_no': 1, 'is_self': True, 'active': True, 'is_dealer': False, 'action_confirmed': False, 'stake_amount': 0, 'fee_amount': 0, 'net_amount': 0, 'cards': []},
            {'character_id': 'c2', 'name': '沈青禾', 'seat_no': 2, 'is_self': False, 'active': True, 'is_dealer': True, 'action_confirmed': True, 'multiplier': 10, 'stake_amount': 200, 'fee_amount': 5, 'net_amount': 0, 'cards': []},
        ],
        'logs': [],
        'laohe': None,
    },
}


def fulfill(route, payload):
    route.fulfill(
        status=200,
        content_type='application/json',
        headers={'Access-Control-Allow-Origin': '*'},
        body=json.dumps(payload, ensure_ascii=False),
    )


with sync_playwright() as pw:
    browser = pw.chromium.launch(
        headless=True,
        executable_path='/usr/bin/chromium',
        args=['--no-sandbox', '--disable-dev-shm-usage'],
    )
    page = browser.new_page(viewport={'width': 390, 'height': 844})

    def handler(route):
        url = route.request.url
        if '/rpc/get_paigow_lobby_bpaigow01' in url:
            lobby_calls['count'] += 1
            balance = 88888 if lobby_calls['count'] == 1 else 88889
            fulfill(route, {
                'status': 'active',
                'balances': {'spirit_stone': balance, 'cultivation': 123456},
                'bankrolls': {'spirit_stone': 100000000, 'cultivation': 1000000000},
                'rooms': [lobby_room],
            })
        elif '/rpc/advance_paigow_round_bpaigow01' in url or '/rpc/get_paigow_room_state_bpaigow01' in url:
            fulfill(route, room_state)
        else:
            fulfill(route, room_state)

    page.route('https://fyykkqkovccgmamsdeoq.supabase.co/**', handler)
    app_js = (ROOT / 'paigow-app.js').read_text('utf-8').replace('</script>', '<\\/script>')
    html = f'''<!doctype html><html><body>
      <main id="paigowApp" class="pg-app"></main><div id="pgToast"></div>
      <script>
        const __store = {{'nine_cloud_dao_session_fyykkqkovccgmamsdeoq_v1': JSON.stringify({{access_token:'test-token'}})}};
        Object.defineProperty(window, 'localStorage', {{value: {{getItem:k=>__store[k]??null,setItem:(k,v)=>{{__store[k]=String(v)}},removeItem:k=>delete __store[k]}}}});
        window.GAME_CONFIG = Object.freeze({{supabaseUrl:'https://fyykkqkovccgmamsdeoq.supabase.co',supabasePublishableKey:'test-key'}});
      </script>
      <script>{app_js}</script>
    </body></html>'''
    page.set_content(html, wait_until='networkidle')
    page.wait_for_selector('#baseBetInput')

    base = page.locator('#baseBetInput')
    assert base.get_attribute('step') == '1', '灵石底注必须支持任意整数'
    base.fill('123')
    page.evaluate("window.__baseNode = document.getElementById('baseBetInput')")
    page.wait_for_timeout(5600)
    assert page.locator('#baseBetInput').input_value() == '123', '大厅自动刷新覆盖了自定义底注'
    assert page.evaluate("window.__baseNode === document.getElementById('baseBetInput')") is False, '测试未触发大厅余额变化后的必要重绘'
    assert page.locator('#baseBetInput').input_value() == '123', '必要重绘后表单草稿未恢复'

    page.locator('[data-open-room]').click()
    page.wait_for_selector('#gameView .board-frame')
    page.evaluate("window.__boardNode = document.querySelector('#gameView .board-frame')")
    page.wait_for_timeout(2400)
    assert page.evaluate("window.__boardNode === document.querySelector('#gameView .board-frame')"), '牌桌轮询仍在整体替换DOM，存在闪烁风险'
    assert page.locator('#gameView').count() == 1
    browser.close()

print('PASS lobby custom stake survives required rerender')
print('PASS unchanged room polling preserves board DOM')
print('PASS integer custom stake step=1')
