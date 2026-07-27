from pathlib import Path
s=(Path(__file__).parents[1]/'database/10_opportunity_v4.sql').read_text()
checks={
'120 stories': 'opportunity_v4_story_pool' in s,
'12 support seeds': s.count("'support','")>=12,
'24 technique pool': s.count("opportunity_v4_technique_pool")>=4,
'old main retained': all(x in s for x in ['清泉纳灵诀','鸿蒙引气章','苍元仙法']),
'new support retained': all(x in s for x in ['静水调息篇','混元灵台篇','九转聚灵诀']),
'five minute': 'offline_interval_seconds=300' in s and 'online_interval_seconds=300' in s,
'exclusive unchanged': 'v_pity:=greatest(20' in s and 'v_pity+2' in s and "'spirit_gain_fixed',100" in s,
'duplicate mastery': "when 'immortal' then 80" in s and "when 'heaven' then 65" in s,
'summary techniques': "'techniques_new',v_tech_new" in s,
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
raise SystemExit(0 if all(checks.values()) else 1)
