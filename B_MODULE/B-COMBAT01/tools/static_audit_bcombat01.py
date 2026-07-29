#!/usr/bin/env python3
from __future__ import annotations
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / 'B_MODULE/B-COMBAT01'
main = (MOD/'SQL_CANDIDATE/10_B_COMBAT01_MAIN.sql').read_text(encoding='utf-8')
pre = (MOD/'SQL_CANDIDATE/00_PRECHECK.sql').read_text(encoding='utf-8')
post = (MOD/'SQL_CANDIDATE/20_CHECK.sql').read_text(encoding='utf-8')
rollback = (MOD/'SQL_CANDIDATE/99_ROLLBACK.sql').read_text(encoding='utf-8')
app = (ROOT/'app.js').read_text(encoding='utf-8')
css = (ROOT/'styles.css').read_text(encoding='utf-8')

checks = {}
def has(name, condition): checks[name] = bool(condition)

has('transaction', main.lstrip().startswith('--') and '\nbegin;' in main and main.rstrip().endswith('commit;'))
has('44-stage-values', len(re.findall(r"\(\d+,\d+,'[^']+',[0-9.]+,\d+,\d+,\d+,\d+\)", main)) == 44)
has('power-formula', 'calc.final_attack*10+calc.final_defense*8+calc.final_vitality*1.5+calc.final_agility*5' in main)
has('five-elements', all(x in main for x in ["'metal'","'wood'","'water'","'fire'","'earth'"]))
has('balanced-allocation-lock', "pg_advisory_xact_lock(hashtext('B-COMBAT01_ELEMENT_ASSIGN'))" in main)
has('new-character-trigger', 'trg_bcombat01_assign_element' in main)
has('element-rules', all(x in main for x in ['1.15','0.85','1.05','0.95']))
has('daily-rules', all(x in main for x in ['default 5','default 10','default 1','default 30','default 0.01']))
has('sword-heart-eight-percent', 'sword_heart_final_damage_bonus' in main and 'default 0.08' in main)
has('sword-heart-no-four-stat-bonus', "-'combat_attribute_bonus'-'combat_effect_enabled'" in main)
has('defense-caps', 'least(0.70' in main and 'least(0.80' in main)
has('cultivation-floor-one-percent', 'floor(v_loser_before::numeric*v_settings.cultivation_loss_rate)' in main)
has('cultivation-cap-preserved', 'character_cultivation_cap_v1' in main and 'cultivation_escrowed' in main)
has('idempotency-lock', "pg_advisory_xact_lock(hashtext('B-COMBAT01:'||p_request_id::text))" in main)
has('world-feed-reused', 'world_event_publish_v0140' in main and 'create or replace function public.world_event_publish_v0140' not in main)
has('no-release-control-write', not re.search(r'(?is)update\s+public\.jiuxiao_app_release_control|insert\s+into\s+public\.jiuxiao_app_release_control', main))
has('no-version-cache-write', not re.search(r'(?is)update\s+[^;]*(cache_epoch|release_version|app_version)', main))
has('rls-on-new-tables', main.count('enable row level security') >= 6)
has('precheck-required-deps', all(x in pre for x in ['character_cultivation_cap_v1','world_event_publish_v0140','sword_heart']))
has('postcheck-rules', all(x in post for x in ['realm_stats_44','element_balance','challenge_settings','world_feed_reused']))
has('rollback-restores-sword-heart', 'ncd_b_module_backup.bcombat01_fates' in rollback and 'update public.fates' in rollback)
has('client-rpcs', all(x in app for x in ['get_battle_power_ranking_bcombat01','get_battle_challenge_preview_bcombat01','challenge_battle_power_bcombat01']))
has('client-fallbacks', '赤手空拳' in app and '赤裸' in app)
has('client-battle-modal', all(x in app for x in ['battle-versus-grid-bcombat01','battle-playback-controls-bcombat01','battleSettlementHtmlBCombat01']))
has('client-world-refresh', "refreshWorldEvents(true)" in app)
has('client-battle-privacy', 'battle-combatant-card-compact-fix2' in app and 'showBattleResolvingModalBCombat01' in app and '${attacker}赤手空拳，运转' not in app)
has('client-css', all(x in css for x in ['.battle-ranking-rule-bcombat01','.battle-challenge-modal-bcombat01','.battle-action-bcombat01','.battle-settlement-bcombat01']))

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items(): print(('PASS' if ok else 'FAIL'), name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
if failed: raise SystemExit(1)
