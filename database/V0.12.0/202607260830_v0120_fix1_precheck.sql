-- 《九霄问道》V0.12.0 FIX1 市坊·万运博弈楼只读预检查
-- 本文件只读取结构，不修改任何数据。
with checks(item, result, detail) as (
  values
    ('player_characters', case when to_regclass('public.player_characters') is not null then 'PASS' else 'FAIL' end,
      '赌场角色与修为结算基础表'),
    ('realm_stages', case when to_regclass('public.realm_stages') is not null then 'PASS' else 'FAIL' end,
      '小境界与修为门槛表'),
    ('realms', case when to_regclass('public.realms') is not null then 'PASS' else 'FAIL' end,
      '大境界顺序表'),
    ('character_inventory', case when to_regclass('public.character_inventory') is not null then 'PASS' else 'FAIL' end,
      '灵石库存表'),
    ('item_definitions', case when to_regclass('public.item_definitions') is not null then 'PASS' else 'FAIL' end,
      '灵石物品定义表'),
    ('character_cultivation_state', case when to_regclass('public.character_cultivation_state') is not null then 'PASS' else 'FAIL' end,
      '境界跌落后重算基础吐纳所需'),
    ('award_spirit_stones_v3', case when to_regprocedure('public.award_spirit_stones_v3(uuid,bigint)') is not null then 'PASS' else 'FAIL' end,
      '赌场返还与奖励灵石所需'),
    ('realm_base_cultivation_rate_v1', case when to_regprocedure('public.realm_base_cultivation_rate_v1(smallint)') is not null then 'PASS' else 'FAIL' end,
      '赌场修为输钱跌小境界后重算吐纳所需'),
    ('nascent_soul_realm', case when exists(
      select 1 from public.realms r where r.code='nascent_soul' or r.name like '元婴%'
    ) then 'PASS' else 'FAIL' end,
      '修为局最低开放境界与大境界保护线'),
    ('spirit_stone_item', case when exists(
      select 1 from public.item_definitions i where i.code='spirit_stone'
    ) then 'PASS' else 'FAIL' end,
      '灵石下注物品定义'),
    ('player_character_id_type', case when exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name='player_characters' and column_name='id' and udt_name='uuid'
    ) then 'PASS' else 'FAIL' end,
      'player_characters.id 必须为 uuid'),
    ('realm_stage_id_type', case when exists(
      select 1 from information_schema.columns
      where table_schema='public' and table_name='realm_stages' and column_name='id' and udt_name='int2'
    ) then 'PASS' else 'FAIL' end,
      'realm_stages.id 必须为 smallint')
)
select * from checks order by item;
