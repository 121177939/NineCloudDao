-- 九霄问道 Web Alpha V0.14.1 FIX7A CACHE5
-- 灵骰公平概率 + 赢利5%入池 + 败局10%入池
--
-- 本脚本可从已经部署FIX7的数据库直接执行，不依赖、也不要求执行FIX8。
--
-- 最终规则：
-- 1. 玩家只押“大”或“小”；开奖结果先独立抽大小，大/小各50%，绝不读取玩家选择或两边下注量。
-- 2. 结果类型独立抽取：普通豹子全服1/80，天命豹子全服1/5000，其余为普通非豹子。
-- 3. 小豹子为111/222/333；大豹子为444/555/666。
-- 4. 普通非豹子押中：毛利润1倍。
-- 5. 普通豹子押中：毛利润3倍。
-- 6. 天命豹子押中：毛利润34倍。
-- 7. 赢局：仅从“毛利润”提取5%进入对应全服造化池；本金不参与抽取。
-- 8. 败局：下注额10%进入对应全服造化池，余下90%由天道回收。
-- 9. 固定押任一边时，总胜率50%，理论长期净期望约-0.999%，不存在固定押一边的正期望。
-- 10. 造化池开奖、候选资格、40%命中/60%滚存等既有机制不改。
--
-- 示例（下注100）：
-- 普通结果胜：本金100 + 利润100 - 入池5 = 到账195。
-- 普通豹子胜：本金100 + 利润300 - 入池15 = 到账385。
-- 天命豹子胜：本金100 + 利润3400 - 入池170 = 到账3330。
-- 败局：10进入造化池，90由天道回收。

begin;

-- ---------------------------------------------------------------------------
-- 0. 前置检查：必须已部署FIX7
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.casino_settings') is null
     or to_regclass('public.casino_pools') is null
     or to_regclass('public.casino_house_games') is null then
    raise exception 'V0.14.1_FIX7_REQUIRED_TABLES_MISSING';
  end if;

  if to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is null
     or to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null
     or to_regprocedure('public.casino_validate_choice_v1(text,text)') is null
     or to_regprocedure('public.casino_add_ticket_v1(uuid,text)') is null then
    raise exception 'V0.14.1_FIX7_REQUIRED_FUNCTIONS_MISSING';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. FIX7A规则参数（本版本固定值）
-- ---------------------------------------------------------------------------
alter table public.casino_settings
  add column if not exists house_win_profit_pool_bps integer not null default 500,
  add column if not exists house_loss_pool_bps integer not null default 1000,
  add column if not exists spirit_dice_ordinary_triple_denominator integer not null default 80,
  add column if not exists spirit_dice_destiny_triple_result_denominator integer not null default 5000,
  add column if not exists spirit_dice_ordinary_triple_net_odds integer not null default 3;

update public.casino_settings
set house_pool_rate=0.05000,
    house_win_profit_pool_bps=500,
    house_loss_pool_bps=1000,
    spirit_dice_ordinary_triple_denominator=80,
    spirit_dice_destiny_triple_result_denominator=5000,
    spirit_dice_ordinary_triple_net_odds=3,
    spirit_dice_destiny_triple_net_odds=34,
    updated_at=now()
where singleton_id=1;

do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_settings'
      and c.conname='casino_settings_house_pool_bps_fix7a_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_house_pool_bps_fix7a_check
      check (
        house_win_profit_pool_bps between 0 and 10000
        and house_loss_pool_bps between 0 and 10000
      );
  end if;

  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_settings'
      and c.conname='casino_settings_spirit_dice_rates_fix7a_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_spirit_dice_rates_fix7a_check
      check (
        spirit_dice_ordinary_triple_denominator=80
        and spirit_dice_destiny_triple_result_denominator=5000
        and spirit_dice_ordinary_triple_net_odds=3
        and spirit_dice_destiny_triple_net_odds=34
      );
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. 整数资源的比例余数累计
--    灵石/修为均为整数。为避免每局向下取整造成小额下注漏洞，
--    不足1单位的比例余数按资源类型和胜负桶累计，长期精确执行5%与10%。
-- ---------------------------------------------------------------------------
create table if not exists public.casino_pool_fraction_carry (
  stake_type text primary key check (stake_type in ('spirit_stone','cultivation')),
  win_carry_units integer not null default 0 check (win_carry_units between 0 and 9999),
  loss_carry_units integer not null default 0 check (loss_carry_units between 0 and 9999),
  updated_at timestamptz not null default now()
);

insert into public.casino_pool_fraction_carry(stake_type)
values ('spirit_stone'),('cultivation')
on conflict (stake_type) do nothing;

alter table public.casino_pool_fraction_carry enable row level security;
revoke all on table public.casino_pool_fraction_carry from public,anon,authenticated;

create or replace function public.casino_pool_share_preview_v0141_fix7a(
  p_base_amount bigint,
  p_rate_bps integer,
  p_carry_units integer default 0
)
returns jsonb
language plpgsql
immutable
security definer
set search_path=public,pg_temp
as $$
declare
  v_scaled numeric;
  v_share bigint;
  v_next_carry integer;
begin
  if p_base_amount is null or p_base_amount<0 then
    raise exception 'CASINO_INVALID_POOL_BASE';
  end if;
  if p_rate_bps is null or p_rate_bps not between 0 and 10000 then
    raise exception 'CASINO_INVALID_POOL_RATE_BPS';
  end if;
  if p_carry_units is null or p_carry_units not between 0 and 9999 then
    raise exception 'CASINO_INVALID_POOL_CARRY';
  end if;

  v_scaled:=p_base_amount::numeric*p_rate_bps::numeric+p_carry_units::numeric;
  v_share:=floor(v_scaled/10000)::bigint;
  v_next_carry:=mod(v_scaled,10000)::integer;

  return jsonb_build_object(
    'base_amount',p_base_amount,
    'rate_bps',p_rate_bps,
    'pool_contribution',v_share,
    'next_carry_units',v_next_carry
  );
end;
$$;

revoke all on function public.casino_pool_share_preview_v0141_fix7a(bigint,integer,integer)
from public,anon,authenticated;

create or replace function public.casino_take_pool_share_v0141_fix7a(
  p_stake_type text,
  p_base_amount bigint,
  p_rate_bps integer,
  p_bucket text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_row public.casino_pool_fraction_carry%rowtype;
  v_carry integer;
  v_preview jsonb;
  v_share bigint;
  v_next_carry integer;
begin
  if p_stake_type not in ('spirit_stone','cultivation') then
    raise exception 'CASINO_INVALID_STAKE_TYPE';
  end if;
  if p_bucket not in ('win','loss') then
    raise exception 'CASINO_INVALID_POOL_BUCKET';
  end if;

  insert into public.casino_pool_fraction_carry(stake_type)
  values (p_stake_type)
  on conflict (stake_type) do nothing;

  select * into v_row
  from public.casino_pool_fraction_carry
  where stake_type=p_stake_type
  for update;

  v_carry:=case when p_bucket='win' then v_row.win_carry_units else v_row.loss_carry_units end;
  v_preview:=public.casino_pool_share_preview_v0141_fix7a(p_base_amount,p_rate_bps,v_carry);
  v_share:=coalesce((v_preview->>'pool_contribution')::bigint,0);
  v_next_carry:=coalesce((v_preview->>'next_carry_units')::integer,0);

  if p_bucket='win' then
    update public.casino_pool_fraction_carry
    set win_carry_units=v_next_carry,
        updated_at=now()
    where stake_type=p_stake_type;
  else
    update public.casino_pool_fraction_carry
    set loss_carry_units=v_next_carry,
        updated_at=now()
    where stake_type=p_stake_type;
  end if;

  return v_preview||jsonb_build_object(
    'stake_type',p_stake_type,
    'bucket',p_bucket,
    'previous_carry_units',v_carry
  );
end;
$$;

revoke all on function public.casino_take_pool_share_v0141_fix7a(text,bigint,integer,text)
from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 3. 可审计的灵骰结果规则
-- ---------------------------------------------------------------------------
create or replace function public.casino_spirit_dice_rule_v0141_fix7a(
  p_d1 integer,
  p_d2 integer,
  p_d3 integer,
  p_choice text,
  p_result_kind text,
  p_ordinary_triple_net_odds integer,
  p_destiny_triple_net_odds integer
)
returns jsonb
language plpgsql
immutable
security definer
set search_path=public,pg_temp
as $$
declare
  v_total integer;
  v_side text;
  v_is_triple boolean;
  v_won boolean;
  v_net_odds integer;
begin
  if p_d1 not between 1 and 6
     or p_d2 not between 1 and 6
     or p_d3 not between 1 and 6 then
    raise exception 'CASINO_INVALID_DICE_VALUE';
  end if;
  if p_choice not in ('big','small') then
    raise exception 'CASINO_INVALID_DICE_CHOICE';
  end if;
  if p_result_kind not in ('normal','ordinary_triple','destiny_triple') then
    raise exception 'CASINO_INVALID_DICE_RESULT_KIND';
  end if;
  if p_ordinary_triple_net_odds<1 or p_destiny_triple_net_odds<1 then
    raise exception 'CASINO_INVALID_DICE_ODDS';
  end if;

  v_total:=p_d1+p_d2+p_d3;
  v_side:=case when v_total between 3 and 10 then 'small' else 'big' end;
  v_is_triple:=p_d1=p_d2 and p_d2=p_d3;

  if p_result_kind='normal' and v_is_triple then
    raise exception 'CASINO_NORMAL_RESULT_CANNOT_BE_TRIPLE';
  end if;
  if p_result_kind in ('ordinary_triple','destiny_triple') and not v_is_triple then
    raise exception 'CASINO_TRIPLE_RESULT_REQUIRES_TRIPLE_DICE';
  end if;

  v_won:=p_choice=v_side;
  v_net_odds:=case
    when not v_won then 0
    when p_result_kind='destiny_triple' then p_destiny_triple_net_odds
    when p_result_kind='ordinary_triple' then p_ordinary_triple_net_odds
    else 1
  end;

  return jsonb_build_object(
    'total',v_total,
    'result_side',v_side,
    'result_kind',p_result_kind,
    'is_triple',v_is_triple,
    'is_destiny_triple',p_result_kind='destiny_triple',
    'won',v_won,
    'net_odds',v_net_odds
  );
end;
$$;

revoke all on function public.casino_spirit_dice_rule_v0141_fix7a(integer,integer,integer,text,text,integer,integer)
from public,anon,authenticated;

-- 灵骰继续只接受大、小；其他玩法不变。
create or replace function public.casino_validate_choice_v1(p_game_code text,p_choice text)
returns boolean
language sql
immutable
security definer
set search_path=public,pg_temp
as $$
  select case
    when p_game_code='spirit_fist' then p_choice in ('rock','scissors','paper')
    when p_game_code='five_elements' then p_choice in ('metal','wood','earth','water','fire')
    when p_game_code='spirit_dice' then p_choice in ('big','small')
    when p_game_code='turtle_oracle' then p_choice in ('auspicious','neutral','ominous')
    else false
  end;
$$;

revoke all on function public.casino_validate_choice_v1(text,text) from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 4. 重建大堂结算RPC
-- ---------------------------------------------------------------------------
create or replace function public.play_house_game_v1(
  p_game_code text,
  p_stake_type text,
  p_stake_amount bigint,
  p_choice text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;
  v_roll integer;
  v_won boolean:=false;
  v_net_odds integer:=1;
  v_reward bigint:=0;
  v_nominal_reward bigint:=0;
  v_nominal_profit bigint:=0;
  v_net_profit bigint:=0;
  v_result_text text;
  v_d1 integer;
  v_d2 integer;
  v_d3 integer;
  v_total integer;
  v_debit jsonb;
  v_drop jsonb;
  v_ticket boolean;
  v_result_payload jsonb;
  v_stake_type text:=p_stake_type;
  v_credit jsonb;
  v_requested_reward bigint:=0;
  v_pool_calc jsonb;
  v_pool_contribution bigint:=0;
  v_heaven_recovery bigint:=0;
  v_dice_rule jsonb;
  v_is_triple boolean:=false;
  v_is_destiny_triple boolean:=false;
  v_result_side text;
  v_side_name text;
  v_result_kind text;
  v_side_roll integer;
  v_kind_roll integer;
  v_face_roll integer;
  v_generation_attempt integer:=0;
  v_win_pool_bps integer:=500;
  v_loss_pool_bps integer:=1000;
  v_ordinary_denominator integer:=80;
  v_destiny_denominator integer:=5000;
  v_ordinary_net_odds integer:=3;
  v_destiny_net_odds integer:=34;
begin
  perform public.casino_assert_enabled_v1();
  perform public.casino_process_v1();

  if p_game_code not in ('spirit_dice','turtle_oracle') then
    raise exception 'CASINO_INVALID_HOUSE_GAME';
  end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then
    raise exception 'CASINO_INVALID_CHOICE';
  end if;

  v_character_id:=public.casino_current_character_id_v1();
  perform public.casino_record_activity_v1(v_character_id,'house',v_stake_type);
  v_debit:=public.casino_debit_v1(v_character_id,v_stake_type,p_stake_amount,'house',p_game_code);

  select
    coalesce(s.house_win_profit_pool_bps,500),
    coalesce(s.house_loss_pool_bps,1000),
    coalesce(s.spirit_dice_ordinary_triple_denominator,80),
    coalesce(s.spirit_dice_destiny_triple_result_denominator,5000),
    coalesce(s.spirit_dice_ordinary_triple_net_odds,3),
    coalesce(s.spirit_dice_destiny_triple_net_odds,34)
  into
    v_win_pool_bps,
    v_loss_pool_bps,
    v_ordinary_denominator,
    v_destiny_denominator,
    v_ordinary_net_odds,
    v_destiny_net_odds
  from public.casino_settings s
  where s.singleton_id=1;

  if not found then
    v_win_pool_bps:=500;
    v_loss_pool_bps:=1000;
    v_ordinary_denominator:=80;
    v_destiny_denominator:=5000;
    v_ordinary_net_odds:=3;
    v_destiny_net_odds:=34;
  end if;

  if v_win_pool_bps not between 0 and 10000
     or v_loss_pool_bps not between 0 and 10000
     or v_ordinary_denominator<2
     or v_destiny_denominator<2
     or v_ordinary_net_odds<1
     or v_destiny_net_odds<1 then
    raise exception 'CASINO_INVALID_FIX7A_SETTINGS';
  end if;

  if p_game_code='spirit_dice' then
    -- 第一步：独立抽大小。玩家选择和两边下注量不参与随机过程。
    v_side_roll:=1+floor(random()*2)::integer;
    v_result_side:=case when v_side_roll=1 then 'small' else 'big' end;
    v_side_name:=case when v_result_side='small' then '小' else '大' end;

    -- 第二步：统一抽结果类型。使用20000等分，保证1/80与1/5000均为整数区间。
    v_kind_roll:=1+floor(random()*20000)::integer;
    v_result_kind:=case
      when v_kind_roll<=4 then 'destiny_triple'       -- 4/20000 = 1/5000
      when v_kind_roll<=254 then 'ordinary_triple'    -- 250/20000 = 1/80
      else 'normal'
    end;

    if v_result_kind in ('ordinary_triple','destiny_triple') then
      v_face_roll:=1+floor(random()*3)::integer;
      if v_result_side='small' then
        v_d1:=v_face_roll;
      else
        v_d1:=v_face_roll+3;
      end if;
      v_d2:=v_d1;
      v_d3:=v_d1;
    else
      -- 在已确定的一边内，等概率拒绝采样非豹子组合。
      loop
        v_generation_attempt:=v_generation_attempt+1;
        if v_generation_attempt>256 then
          raise exception 'CASINO_DICE_GENERATION_FAILED';
        end if;

        v_d1:=1+floor(random()*6)::integer;
        v_d2:=1+floor(random()*6)::integer;
        v_d3:=1+floor(random()*6)::integer;
        v_total:=v_d1+v_d2+v_d3;

        exit when not(v_d1=v_d2 and v_d2=v_d3)
          and ((v_result_side='small' and v_total between 3 and 10)
            or (v_result_side='big' and v_total between 11 and 18));
      end loop;
    end if;

    v_dice_rule:=public.casino_spirit_dice_rule_v0141_fix7a(
      v_d1,v_d2,v_d3,p_choice,v_result_kind,v_ordinary_net_odds,v_destiny_net_odds
    );

    v_total:=coalesce((v_dice_rule->>'total')::integer,v_d1+v_d2+v_d3);
    v_result_side:=v_dice_rule->>'result_side';
    v_side_name:=case when v_result_side='small' then '小' else '大' end;
    v_is_triple:=coalesce((v_dice_rule->>'is_triple')::boolean,false);
    v_is_destiny_triple:=coalesce((v_dice_rule->>'is_destiny_triple')::boolean,false);
    v_won:=coalesce((v_dice_rule->>'won')::boolean,false);
    v_net_odds:=coalesce((v_dice_rule->>'net_odds')::integer,0);

    v_result_text:=format(
      '荷老揭开玉盅，三枚灵骰显出【%s、%s、%s】，共%s点，归于【%s】。%s',
      v_d1,v_d2,v_d3,v_total,v_side_name,
      case
        when v_result_kind='destiny_triple' and v_won then '三相归一，紫气贯盅，天命豹子显化；你押中大小，本局按毛利润34倍结算。'
        when v_result_kind='destiny_triple' then format('天命豹子显化，但归于【%s】，与你所押不合。',v_side_name)
        when v_result_kind='ordinary_triple' and v_won then '三相归一，普通豹子显化；你押中大小，本局按毛利润3倍结算。'
        when v_result_kind='ordinary_triple' then format('普通豹子显化，但归于【%s】，与你所押不合。',v_side_name)
        when v_won then '你押中了此局，按毛利润1倍结算。'
        else '此局与你所押不合。'
      end
    );

    v_result_payload:=jsonb_build_object(
      'dice',jsonb_build_array(v_d1,v_d2,v_d3),
      'total',v_total,
      'choice',p_choice,
      'result_side',v_result_side,
      'result_kind',v_result_kind,
      'is_triple',v_is_triple,
      'is_destiny_triple',v_is_destiny_triple,
      'side_roll',v_side_roll,
      'kind_roll',v_kind_roll,
      'ordinary_triple_probability','1/80',
      'destiny_triple_probability','1/5000',
      'ordinary_triple_net_odds',v_ordinary_net_odds,
      'destiny_triple_net_odds',v_destiny_net_odds,
      'triple_auto_side',true,
      'result_independent_of_choice',true
    );
  else
    v_roll:=floor(random()*100)::integer;
    v_won:=(p_choice='auspicious' and v_roll<25)
      or (p_choice='neutral' and v_roll>=25 and v_roll<75)
      or (p_choice='ominous' and v_roll>=75);
    v_net_odds:=case when p_choice='neutral' then 1 else 3 end;
    v_result_text:=case
      when v_roll<25 then '灵火骤明，龟甲裂纹如灵芝舒展，显出【吉】象。'
      when v_roll<75 then '龟甲裂纹横竖相抵，灵火归静，显出【平】象。'
      else '龟甲中央崩开深纹，黑烟盘旋，显出【凶】象。'
    end;
    v_result_text:=v_result_text||case
      when v_won then ' 荷老颔首：“道友押中了。”'
      else ' 荷老淡声道：“落筹无悔。”'
    end;
    v_result_payload:=jsonb_build_object(
      'roll',v_roll,
      'choice',p_choice,
      'result',case when v_roll<25 then 'auspicious' when v_roll<75 then 'neutral' else 'ominous' end
    );
  end if;

  if v_won then
    -- 赢局只从毛利润提取5%入池，本金不参与抽取。
    v_nominal_profit:=p_stake_amount*v_net_odds;
    v_pool_calc:=public.casino_take_pool_share_v0141_fix7a(
      v_stake_type,v_nominal_profit,v_win_pool_bps,'win'
    );
    v_pool_contribution:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
    v_net_profit:=greatest(0,v_nominal_profit-v_pool_contribution);
    v_nominal_reward:=p_stake_amount+v_nominal_profit;
    v_requested_reward:=p_stake_amount+v_net_profit;

    if v_pool_contribution>0 then
      update public.casino_pools p
      set amount=p.amount+v_pool_contribution,
          updated_at=now()
      where p.stake_type=v_stake_type;
    end if;

    v_credit:=public.casino_credit_result_v0141(v_character_id,v_stake_type,v_requested_reward);
    v_reward:=coalesce((v_credit->>'granted_amount')::bigint,0);
    v_heaven_recovery:=0;

    v_result_text:=v_result_text||format(
      ' 本局押注%s%s；本金%s%s原数返还，毛利润%s%s，其中%s%s（5%%）注入全服造化池，实际利润%s%s，合计到账%s%s。',
      p_stake_amount,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      p_stake_amount,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_nominal_profit,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_pool_contribution,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_net_profit,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_reward,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end
    );

    if v_stake_type='cultivation' and coalesce((v_credit->>'discarded_amount')::bigint,0)>0 then
      v_result_text:=v_result_text||format(
        ' 受境界上限所限，另有%s点修为未能纳入体内。',
        v_credit->>'discarded_amount'
      );
    end if;
  else
    -- 败局：下注10%入池，余下90%天道回收。
    v_nominal_reward:=0;
    v_nominal_profit:=0;
    v_net_profit:=-p_stake_amount;
    v_pool_calc:=public.casino_take_pool_share_v0141_fix7a(
      v_stake_type,p_stake_amount,v_loss_pool_bps,'loss'
    );
    v_pool_contribution:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
    v_heaven_recovery:=greatest(0,p_stake_amount-v_pool_contribution);

    if v_pool_contribution>0 then
      update public.casino_pools p
      set amount=p.amount+v_pool_contribution,
          updated_at=now()
      where p.stake_type=v_stake_type;
    end if;

    if v_stake_type='cultivation' then
      v_drop:=public.casino_realign_after_loss_v1(v_character_id);
      if coalesce((v_drop->>'stage_changed')::boolean,false) then
        v_result_text:=v_result_text||format(
          ' 你的境界由【%s】跌至【%s】，但未跌出当前大境界。',
          v_drop->>'stage_before_name',v_drop->>'stage_after_name'
        );
      end if;
    end if;

    v_result_text:=v_result_text||format(
      ' 本局实际折损%s%s，其中%s%s（10%%）进入全服造化池，余下%s%s（90%%）由天道回收。',
      p_stake_amount,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_pool_contribution,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_heaven_recovery,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end
    );
  end if;

  v_ticket:=public.casino_add_ticket_v1(v_character_id,v_stake_type);
  v_result_text:=v_result_text||case
    when v_ticket then ' 你已取得本期等权候选资格。'
    else ' 你已在本期候选名录中，本局不会叠加个人中奖权重。'
  end;

  v_result_payload:=coalesce(v_result_payload,'{}'::jsonb)||jsonb_build_object(
    'net_odds',v_net_odds,
    'nominal_profit',v_nominal_profit,
    'nominal_reward',v_nominal_reward,
    'actual_reward',v_reward,
    'pool_contribution',v_pool_contribution,
    'pool_base_amount',case when v_won then v_nominal_profit else p_stake_amount end,
    'pool_rate_bps',case when v_won then v_win_pool_bps else v_loss_pool_bps end,
    'pool_bucket',case when v_won then 'win_profit' else 'loss_stake' end,
    'pool_rounding_carry',v_pool_calc,
    'heaven_recovery',v_heaven_recovery,
    'net_profit',case when v_won then greatest(0,v_reward-p_stake_amount) else -p_stake_amount end
  );

  insert into public.casino_house_games(
    character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,
    reward_amount,nominal_reward_amount,fee_amount,pool_contribution,heaven_recovery_amount,
    result_payload,result_text
  ) values (
    v_character_id,p_game_code,v_stake_type,p_stake_amount,p_choice,
    case when v_won then 'win' else 'loss' end,
    v_reward,v_nominal_reward,0,v_pool_contribution,v_heaven_recovery,
    v_result_payload,v_result_text
  );

  return jsonb_build_object(
    'won',v_won,
    'reward',v_reward,
    'nominal_reward',v_nominal_reward,
    'nominal_profit',v_nominal_profit,
    'net_profit',case when v_won then greatest(0,v_reward-p_stake_amount) else -p_stake_amount end,
    'fee',0,
    'pool_contribution',v_pool_contribution,
    'heaven_recovery',v_heaven_recovery,
    'ticket_awarded',v_ticket,
    'result_text',v_result_text,
    'result_payload',v_result_payload,
    'drop',v_drop
  );
end;
$$;

revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;

comment on function public.casino_spirit_dice_rule_v0141_fix7a(integer,integer,integer,text,text,integer,integer) is
  'V0.14.1 FIX7A：大小各50%；普通豹子全服1/80、毛利润3倍；天命豹子全服1/5000、毛利润34倍。';
comment on function public.play_house_game_v1(text,text,bigint,text) is
  'V0.14.1 FIX7A：赢局按毛利润5%入池；败局下注10%入池、90%天道回收；灵骰结果独立于玩家选择。';

-- ---------------------------------------------------------------------------
-- 5. 发布控制：强制旧客户端刷新
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is not null then
    update public.jiuxiao_app_release_control
    set cache_epoch=greatest(coalesce(cache_epoch,0)+1,5),
        release_name='V0.14.1 FIX7A CACHE5',
        notice_text='赌坊赔率、豹子概率及输赢入池规则已更新，正在加载最新页面。',
        updated_at=now()
    where singleton_id=1;
  end if;
end;
$$;

commit;
notify pgrst,'reload schema';

-- ---------------------------------------------------------------------------
-- 6. 执行后检查：所有ok应为true
-- ---------------------------------------------------------------------------
select * from (values
  ('fix7a_columns_exist',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='casino_settings' and column_name='house_win_profit_pool_bps')
    and exists(select 1 from information_schema.columns where table_schema='public' and table_name='casino_settings' and column_name='house_loss_pool_bps')
    and exists(select 1 from information_schema.columns where table_schema='public' and table_name='casino_settings' and column_name='spirit_dice_ordinary_triple_denominator')
    and exists(select 1 from information_schema.columns where table_schema='public' and table_name='casino_settings' and column_name='spirit_dice_destiny_triple_result_denominator'),
    'FIX7A参数列存在'),
  ('pool_rates_are_5_and_10_percent',
    coalesce((select house_win_profit_pool_bps=500 and house_loss_pool_bps=1000 from public.casino_settings where singleton_id=1),false),
    '赢利5%入池、败局10%入池'),
  ('triple_probabilities_are_1_of_80_and_1_of_5000',
    coalesce((select spirit_dice_ordinary_triple_denominator=80 and spirit_dice_destiny_triple_result_denominator=5000 from public.casino_settings where singleton_id=1),false),
    '普通豹子1/80、天命豹子1/5000'),
  ('triple_odds_are_3_and_34',
    coalesce((select spirit_dice_ordinary_triple_net_odds=3 and spirit_dice_destiny_triple_net_odds=34 from public.casino_settings where singleton_id=1),false),
    '普通豹子毛利润3倍、天命豹子毛利润34倍'),
  ('pool_carry_table_exists',to_regclass('public.casino_pool_fraction_carry') is not null,'比例余数累计表存在'),
  ('pool_preview_function_exists',to_regprocedure('public.casino_pool_share_preview_v0141_fix7a(bigint,integer,integer)') is not null,'比例预览函数存在'),
  ('dice_rule_function_exists',to_regprocedure('public.casino_spirit_dice_rule_v0141_fix7a(integer,integer,integer,text,text,integer,integer)') is not null,'灵骰FIX7A规则函数存在'),
  ('house_rpc_exists',to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is not null,'大堂结算RPC存在'),
  ('triple_choice_disabled',not public.casino_validate_choice_v1('spirit_dice','triple'),'不允许独立押豹子'),
  ('normal_win_100_pool_is_5',
    coalesce((public.casino_pool_share_preview_v0141_fix7a(100,500,0)->>'pool_contribution')::bigint=5,false),
    '普通赢利100时5进入奖池'),
  ('ordinary_triple_profit_600_pool_is_30',
    coalesce((public.casino_pool_share_preview_v0141_fix7a(600,500,0)->>'pool_contribution')::bigint=30,false),
    '普通豹子赢利600时30进入奖池'),
  ('destiny_profit_6800_pool_is_340',
    coalesce((public.casino_pool_share_preview_v0141_fix7a(6800,500,0)->>'pool_contribution')::bigint=340,false),
    '天命豹子赢利6800时340进入奖池'),
  ('loss_100_pool_is_10',
    coalesce((public.casino_pool_share_preview_v0141_fix7a(100,1000,0)->>'pool_contribution')::bigint=10,false),
    '败局100时10进入奖池'),
  ('loss_100_heaven_is_90',
    100-coalesce((public.casino_pool_share_preview_v0141_fix7a(100,1000,0)->>'pool_contribution')::bigint,0)=90,
    '败局100时90由天道回收'),
  ('666_big_ordinary_is_3x',
    coalesce((public.casino_spirit_dice_rule_v0141_fix7a(6,6,6,'big','ordinary_triple',3,34)->>'won')::boolean,false)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix7a(6,6,6,'big','ordinary_triple',3,34)->>'net_odds')::integer=3,false),
    '押大遇普通666按毛利润3倍'),
  ('666_big_destiny_is_34x',
    coalesce((public.casino_spirit_dice_rule_v0141_fix7a(6,6,6,'big','destiny_triple',3,34)->>'won')::boolean,false)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix7a(6,6,6,'big','destiny_triple',3,34)->>'net_odds')::integer=34,false),
    '押大遇天命666按毛利润34倍'),
  ('111_big_loses',
    not coalesce((public.casino_spirit_dice_rule_v0141_fix7a(1,1,1,'big','ordinary_triple',3,34)->>'won')::boolean,true)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix7a(1,1,1,'big','ordinary_triple',3,34)->>'net_odds')::integer=0,false),
    '押大遇111判负'),
  ('fixed_side_expected_value_is_minus_0_999_percent',
    -- 普通非豹子命中9873/20000，普通豹子1/160，天命豹子1/10000，失败1/2。
    -- 赢局利润扣5%后分别为0.95、2.85、32.3倍。
    (9873::numeric/20000)*(19::numeric/20)
      +(1::numeric/160)*(57::numeric/20)
      +(1::numeric/10000)*(323::numeric/10)
      -(1::numeric/2)
      =(-999::numeric/100000),
    '固定押一边长期期望为-0.999%'),
  ('release_control_is_fix7a',
    case when to_regclass('public.jiuxiao_app_release_control') is null then true
      else coalesce((select release_name='V0.14.1 FIX7A CACHE5' and cache_epoch>=5 from public.jiuxiao_app_release_control where singleton_id=1),false)
    end,
    '发布控制已切换至FIX7A CACHE5')
) as checks(check_name,ok,meaning)
order by check_name;
