#!/usr/bin/env python3
from __future__ import annotations
import json, re, subprocess, sys
from pathlib import Path

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
passes=[]; fails=[]; warns=[]
def check(name, cond, detail=''):
    (passes if cond else fails).append(name + (f'：{detail}' if detail else ''))
def text(rel): return (root/rel).read_text(encoding='utf-8')

required=['index.html','404.html','app.js','styles.css','config.js','sw.js','manifest.webmanifest','VERSION.txt','README.md','CHANGELOG.md','CURRENT_BASELINE.json','release_config.json',
'database/V0.12.0/202607260830_v0120_fix1_precheck.sql','database/V0.12.0/202607260830_v0120_fix1_market_casino.sql','database/V0.12.0/202607260830_v0120_fix1_check.sql','database/V0.12.0/202607260830_v0120_fix1_emergency_disable.sql','database/V0.12.0/202607260830_v0120_fix1_resume.sql','database/V0.12.0/202607260830_v0120_fix1_rollback.sql']
check('必需文件完整', all((root/x).is_file() for x in required), ', '.join(x for x in required if not (root/x).is_file()))

app=text('app.js'); sql=text('database/V0.12.0/202607260830_v0120_fix1_market_casino.sql'); chk=text('database/V0.12.0/202607260830_v0120_fix1_check.sql'); pre=text('database/V0.12.0/202607260830_v0120_fix1_precheck.sql'); rb=text('database/V0.12.0/202607260830_v0120_fix1_rollback.sql')
check('统一版本标识', text('VERSION.txt').strip()=='V0.12.0 FIX1' and "version: '0.12.0-fix1'" in text('config.js') and '0.12.0-fix1' in text('index.html') and 'nine-cloud-dao-v0.12.0-fix1' in text('sw.js'))
check('index与404一致', (root/'index.html').read_bytes()==(root/'404.html').read_bytes())
check('旧V0.12.0初稿SQL未打包', '202607260800_v0120_market_casino.sql' not in [p.name for p in (root/'database/V0.12.0').glob('*')])
check('只读预检查无写操作', not re.search(r'(?im)^\s*(insert|update|delete|alter|create|drop|truncate|grant|revoke)\b',pre))
check('主SQL事务完整', sql.lstrip().startswith('--') and re.search(r'\bbegin\s*;',sql,re.I) is not None and re.search(r'\bcommit\s*;\s*$',sql,re.I) is not None)
check('主SQL dollar quote配对', sql.count('$$')%2==0, str(sql.count('$$')))
check('回滚SQL事务与未结算返还', 'begin;' in rb.lower() and 'commit;' in rb.lower() and "status in('open','sealed')" in rb and 'award_spirit_stones_v3' in rb and 'cultivation=cultivation+d.stake_amount' in rb)

for t in ['casino_settings','casino_pools','casino_duels','casino_house_games','casino_daily_activity','casino_tickets','casino_draws']:
    check(f'数据表 {t}', f'create table if not exists public.{t}' in sql)
check('赌场表RLS与直连权限关闭', sql.count('enable row level security')>=7 and sql.count('revoke all on table public.casino_')>=7)
check('正式RPC完整', all(f'create or replace function public.{f}' in sql for f in ['get_market_v1','play_house_game_v1','create_duel_v1','join_duel_v1','cancel_duel_v1']))
check('只向authenticated开放五个RPC', sql.count('grant execute on function public.')==5 and ' to anon' not in sql.lower())
internal=['casino_assert_enabled_v1()','casino_current_character_id_v1()','casino_stone_item_id_v1()','casino_nascent_major_order_v1()','casino_available_v1(uuid,text)','casino_validate_choice_v1(text,text)','casino_choice_name_v1(text,text)','casino_result_v1(text,text,text)','casino_debit_v1(uuid,text,bigint,text,text)','casino_credit_v1(uuid,text,bigint)','casino_realign_after_loss_v1(uuid)','casino_assert_activity_allowed_v1(uuid,text,text)','casino_record_activity_v1(uuid,text,text)','casino_add_ticket_v1(uuid,text)','casino_expire_open_duels_v1()','casino_settle_duels_v1()','casino_draw_pools_v1()','casino_process_v1()']
check('全部内部函数撤销客户端执行权', all(f'revoke all on function public.{f} from public,anon,authenticated;' in sql for f in internal), ', '.join(f for f in internal if f'revoke all on function public.{f} from public,anon,authenticated;' not in sql))
check('删除初稿危险函数', all(x in sql for x in ['drop function if exists public.casino_credit(uuid,text,bigint);','drop function if exists public.casino_debit(uuid,text,bigint);','drop function if exists public.settle_casino_duels_v1();']))

check('5%全部注入对应彩池', 'v_fee:=(p_stake_amount*5)/100;' in sql and 'v_fee:=(d.stake_amount*2*5)/100;' in sql and sql.count('update public.casino_pools')>=4)
check('平局原数返还且不抽水', "set status='draw',fee_amount=0,prize_amount=0" in sql and '赌注原数奉还' in sql)
check('玩家暗选五分钟一局定胜负', 'reveal_delay_seconds integer not null default 300' in sql and "status='sealed',reveal_at=v_reveal_at" in sql and '一局定胜负' in sql)
check('公开赌桌30分钟返还', 'open_expiry_seconds integer not null default 1800' in sql and 'casino_expire_open_duels_v1' in sql and "cancellation_reason='OPEN_TABLE_EXPIRED'" in sql)
check('创建者可主动取消返还', 'cancel_duel_v1' in sql and "cancellation_reason='CREATOR_CANCELLED'" in sql)
check('并发重复开桌应局已加角色锁', sql.count("pg_advisory_xact_lock(hashtextextended('casino:'||v_character_id::text,120))")>=2)
check('修为最低5万与元婴准入', 'v_minimum := 50000;' in sql and 'CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL' in sql)
check('修为单注上限20%', 'floor(v_available * 0.20)::bigint' in sql)
check('输钱仅回退同一大境界', 'where r.major_order=v_major_order and rs.cultivation_required<=v_cultivation' in sql and 'realm_base_cultivation_rate_v1(v_new_stage_id)' in sql)
check('每日与贪念限制', all(x in sql for x in ['a.total_count>=30','a.house_count>=30','a.duel_count>=15','a.cultivation_count>=10',"interval '30 seconds'"]))
check('造化签与两小时开奖', 'draw_interval_seconds integer not null default 7200' in sql and 'casino_add_ticket_v1' in sql and 'casino_draw_pools_v1' in sql and 'generate_series(1,t.ticket_count)' in sql)
check('检查SQL项目数27', len(re.findall(r"\('([^']+)',case",chk))==27)

front=['rpc/get_market_v1','rpc/play_house_game_v1','rpc/create_duel_v1','rpc/join_duel_v1','rpc/cancel_duel_v1',"['market', '市', '市坊']",'pageSize = 6','marketPanelHtml','封招应局','五分钟','灵石造化池','修为造化池']
check('前端市坊流程完整', all(x in app for x in front), ', '.join(x for x in front if x not in app))
check('无prompt出招', 'prompt(' not in app)
check('市坊首次读取与10秒刷新', 'rpcGetMarketV1().catch' in app and 'setInterval(() => refreshMarketSystem(true), 10000)' in app)
check('前端个人30次闭楼', 'personalClosed = totalCount >= 30' in app and '今日三十次落注已满' in app)
check('开奖前只显示本人招式', "'my_choice',public.casino_choice_name_v1" in sql and "'opponent_choice',case when d.status in ('settled','draw')" in sql)

# Exact fair-dice probabilities.
small=big=triple=0
for a in range(1,7):
  for b in range(1,7):
    for c in range(1,7):
      if a==b==c: triple+=1
      elif 4<=a+b+c<=10: small+=1
      elif 11<=a+b+c<=17: big+=1
check('灵骰概率精确', (small,big,triple)==(105,105,6), f'{small}/{big}/{triple}')
check('灵骰赔率与前端一致', "v_net_odds:=34" in sql and '约48.61%，1:1' in app and '约2.78%，1:34' in app)
check('龟卜25/50/25与赔率一致', 'v_roll<25' in sql and 'v_roll<75' in sql and "p_choice='neutral' then 1 else 3" in sql and '押吉（25%，1:3）' in app and '押平（50%，1:1）' in app)

node_ok=True
for f in ['app.js','config.js','sw.js']:
    r=subprocess.run(['node','--check',str(root/f)],capture_output=True,text=True)
    if r.returncode: node_ok=False; fails.append(f'{f}语法：{r.stderr.strip()}')
check('JavaScript语法',node_ok)

for x in passes: print('[PASS]',x)
for x in warns: print('[WARN]',x)
for x in fails: print('[FAIL]',x)
print(f'结果：{len(passes)}通过，{len(warns)}警告，{len(fails)}失败')
sys.exit(1 if fails else 0)
