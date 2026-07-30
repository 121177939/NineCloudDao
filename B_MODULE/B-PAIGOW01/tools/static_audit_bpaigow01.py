from pathlib import Path
import re, sys
root=Path(__file__).resolve().parents[1]
app=(root/'CLIENT_CANDIDATE/app.js').read_text(encoding='utf-8')
idx=(root/'CLIENT_CANDIDATE/index.html').read_text(encoding='utf-8')
html=(root/'CLIENT_CANDIDATE/b-paigow01.html').read_text(encoding='utf-8')
sql=(root/'SQL_CANDIDATE/71_B_PAIGOW01_MAIN.sql').read_text(encoding='utf-8')
checks={
 'visible_old_turtle_removed':'气运龟卜' not in app,
 'new_entry':'九霄灵牌' in app and 'data-paigow-open' in app,
 'launcher_loaded':'b-paigow01.js' in idx and 'b-paigow01.css' in idx,
 'four_rooms':all(x in html for x in ['天字一号房','地字二号房','玄字三号房','黄字四号房']),
 'traditional_tiles':'至尊宝' in html and '天高九' in html and '地高九' in html,
 'long_three_face':'key:"chong"' in html and 'top:{w:[1,5,9]},bottom:{w:[1,5,9]}' in html,
 'existing_bankroll_reused':'casino_bankroll_v1' in sql and 'create table if not exists public.casino_bankroll_v1' not in sql,
 'room_limit_sql':'between 1 and 4' in sql,
 'idle_20m_sql':"interval '20 minutes'" in sql,
 'fee_250bps':'p_stake*250' in sql,
 'laohe_equal':'laohe_100_to_100_existing_bankroll' in sql,
 'physical_tiles_32':sql.count("('teen")>=2 and "('gee6'" in sql,
}
for k,v in checks.items(): print(f'{k}: {"PASS" if v else "FAIL"}')
if not all(checks.values()): sys.exit(1)
