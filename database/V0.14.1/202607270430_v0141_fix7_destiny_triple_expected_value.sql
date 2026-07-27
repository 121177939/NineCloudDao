-- 九霄问道 Web Alpha V0.14.1 FIX7 CACHE4
-- 灵骰天命豹子期望值修复
--
-- 最终规则：
-- 1. 玩家只押“大”或“小”，不再提供独立“围骰/豹子”押注。
-- 2. 三骰总点数3—10为小，11—18为大；豹子同样按总点数归类。
-- 3. 111/222/333归小，444/555/666归大。
-- 4. 普通结果与普通豹子命中：净赔率1倍。
-- 5. 对应大小的豹子出现后，再以9/275（约3.2727%）判定是否成为“天命豹子”。
-- 6. 天命豹子命中：净赔率34倍；固定押一边时，实际触发概率恰为1/2200。
-- 7. 大堂每局赌注5%进入全服造化池的FIX3规则保持不变。
-- 8. 按当前规则每押100的长期数学期望为-1，赌场优势约1%。
--
-- 前置：V0.14.1主迁移、FIX2、FIX3、FIX4、FIX6已完成；FIX5可在此前或此后执行。

begin;

-- ---------------------------------------------------------------------------
-- 0. 前置检查
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.casino_settings') is null
     or to_regclass('public.casino_pools') is null
     or to_regclass('public.casino_house_games') is null then
    raise exception 'V0.14.1_FIX3_REQUIRED_TABLES_MISSING';
  end if;

  if to_regprocedure('public.casino_house_stake_split_v0141_fix3(bigint)') is null
     or to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null
     or to_regprocedure('public.casino_validate_choice_v1(text,text)') is null
     or to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is null then
    raise exception 'V0.14.1_FIX3_REQUIRED_FUNCTIONS_MISSING';
  end if;
end;
$$;


-- ---------------------------------------------------------------------------
-- 1. 天命豹子可配置参数
-- ---------------------------------------------------------------------------
alter table public.casino_settings
  add column if not exists spirit_dice_destiny_triple_numerator integer not null default 9,
  add column if not exists spirit_dice_destiny_triple_denominator integer not null default 275,
  add column if not exists spirit_dice_destiny_triple_net_odds integer not null default 34;

update public.casino_settings
set spirit_dice_destiny_triple_numerator=9,
    spirit_dice_destiny_triple_denominator=275,
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
      and c.conname='casino_settings_destiny_triple_chance_fix7_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_destiny_triple_chance_fix7_check
      check (
        spirit_dice_destiny_triple_denominator>0
        and spirit_dice_destiny_triple_numerator between 0 and spirit_dice_destiny_triple_denominator
      );
  end if;

  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_settings'
      and c.conname='casino_settings_destiny_triple_odds_fix7_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_destiny_triple_odds_fix7_check
      check (spirit_dice_destiny_triple_net_odds>=1);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. 可审计的灵骰规则函数
-- ---------------------------------------------------------------------------
create or replace function public.casino_spirit_dice_rule_v0141_fix7(
  p_d1 integer,
  p_d2 integer,
  p_d3 integer,
  p_choice text,
  p_destiny_triggered boolean,
  p_destiny_net_odds integer
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
  v_is_destiny_triple boolean;
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

  if p_destiny_net_odds is null or p_destiny_net_odds<1 then
    raise exception 'CASINO_INVALID_DESTINY_TRIPLE_ODDS';
  end if;

  v_total:=p_d1+p_d2+p_d3;
  v_side:=case when v_total between 3 and 10 then 'small' else 'big' end;
  v_is_triple:=p_d1=p_d2 and p_d2=p_d3;
  v_won:=p_choice=v_side;
  v_is_destiny_triple:=v_won and v_is_triple and coalesce(p_destiny_triggered,false);
  v_net_odds:=case
    when v_is_destiny_triple then p_destiny_net_odds
    when v_won then 1
    else 0
  end;

  return jsonb_build_object(
    'total',v_total,
    'result_side',v_side,
    'is_triple',v_is_triple,
    'is_destiny_triple',v_is_destiny_triple,
    'won',v_won,
    'net_odds',v_net_odds
  );
end;
$$;

revoke all on function public.casino_spirit_dice_rule_v0141_fix7(integer,integer,integer,text,boolean,integer)
from public,anon,authenticated;

-- 灵骰不再接受独立triple押注；其他玩法保持原样。
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
-- 3. 重建大堂结算RPC，仅修改灵骰天命判定；FIX3的5%入池账务完整继承
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
  v_stake_split jsonb;
  v_pool_contribution bigint:=0;
  v_heaven_recovery bigint:=0;
  v_dice_rule jsonb;
  v_is_triple boolean:=false;
  v_result_side text;
  v_side_name text;
  v_is_destiny_triple boolean:=false;
  v_destiny_roll integer;
  v_destiny_numerator integer:=9;
  v_destiny_denominator integer:=275;
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

  -- FIX3：每一笔完成结算的大堂赌注固定提取5%进入全服造化池。
  v_stake_split:=public.casino_house_stake_split_v0141_fix3(p_stake_amount);
  v_pool_contribution:=coalesce((v_stake_split->>'pool_contribution')::bigint,0);

  if v_pool_contribution>0 then
    update public.casino_pools p
    set amount=p.amount+v_pool_contribution,
        updated_at=now()
    where p.stake_type=v_stake_type;
  end if;

  if p_game_code='spirit_dice' then
    select
      coalesce(s.spirit_dice_destiny_triple_numerator,9),
      coalesce(s.spirit_dice_destiny_triple_denominator,275),
      coalesce(s.spirit_dice_destiny_triple_net_odds,34)
    into v_destiny_numerator,v_destiny_denominator,v_destiny_net_odds
    from public.casino_settings s
    where s.singleton_id=1;

    if not found then
      v_destiny_numerator:=9;
      v_destiny_denominator:=275;
      v_destiny_net_odds:=34;
    end if;

    if v_destiny_denominator<=0
       or v_destiny_numerator<0
       or v_destiny_numerator>v_destiny_denominator
       or v_destiny_net_odds<1 then
      raise exception 'CASINO_INVALID_DESTINY_TRIPLE_SETTINGS';
    end if;

    v_d1:=1+floor(random()*6)::integer;
    v_d2:=1+floor(random()*6)::integer;
    v_d3:=1+floor(random()*6)::integer;
    v_is_triple:=v_d1=v_d2 and v_d2=v_d3;

    if v_is_triple then
      v_destiny_roll:=1+floor(random()*v_destiny_denominator)::integer;
    else
      v_destiny_roll:=null;
    end if;

    v_dice_rule:=public.casino_spirit_dice_rule_v0141_fix7(
      v_d1,v_d2,v_d3,p_choice,
      v_is_triple and coalesce(v_destiny_roll<=v_destiny_numerator,false),
      v_destiny_net_odds
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
        when v_is_destiny_triple then '三相归一，紫气贯盅，天命豹子显化；你押中大小，本局按净赔率34倍结算。'
        when v_is_triple and v_won then '三相归一，豹子显化；你押中大小，但天命未至，本局按普通净赔率1倍结算。'
        when v_is_triple then format('三相归一，豹子显化，但豹子归【%s】，与你所押不合。',v_side_name)
        when v_won then '你押中了此局，按普通净赔率1倍结算。'
        else '此局与你所押不合。'
      end
    );

    v_result_payload:=jsonb_build_object(
      'dice',jsonb_build_array(v_d1,v_d2,v_d3),
      'total',v_total,
      'choice',p_choice,
      'result_side',v_result_side,
      'is_triple',v_is_triple,
      'is_destiny_triple',v_is_destiny_triple,
      'destiny_roll',v_destiny_roll,
      'destiny_numerator',v_destiny_numerator,
      'destiny_denominator',v_destiny_denominator,
      'destiny_net_odds',v_destiny_net_odds,
      'triple_auto_side',true
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
    -- 名义奖励=本金+赔率盈利；造化池5%从本局赔率盈利中扣除。
    -- 普通结果或普通豹子押100命中：100本金+100盈利-5入池=195。
    -- 只有天命豹子押100命中：100本金+3400盈利-5入池=3495。
    v_nominal_profit:=p_stake_amount*v_net_odds;
    v_net_profit:=greatest(0,v_nominal_profit-v_pool_contribution);
    v_nominal_reward:=p_stake_amount+v_nominal_profit;
    v_requested_reward:=p_stake_amount+v_net_profit;

    v_credit:=public.casino_credit_result_v0141(v_character_id,v_stake_type,v_requested_reward);
    v_reward:=coalesce((v_credit->>'granted_amount')::bigint,0);
    v_heaven_recovery:=0;

    v_result_text:=v_result_text||format(
      ' 本局押注%s%s，其中%s%s注入全服造化池；本金%s%s原数返还，按赔率净得%s%s，合计到账%s%s。',
      p_stake_amount,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_pool_contribution,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      p_stake_amount,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
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
    v_nominal_reward:=0;
    v_nominal_profit:=0;
    v_net_profit:=-p_stake_amount;
    v_heaven_recovery:=p_stake_amount-v_pool_contribution;

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
      ' 本局实际折损%s%s，其中%s%s进入全服造化池，余下%s%s由天道回收。',
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
    'nominal_reward',v_nominal_reward,
    'actual_reward',v_reward,
    'pool_contribution',v_pool_contribution,
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
    'net_profit',case when v_won then greatest(0,v_reward-p_stake_amount) else -p_stake_amount end,
    'fee',0,
    'pool_contribution',v_pool_contribution,
    'heaven_recovery',v_heaven_recovery,
    'ticket_awarded',v_ticket,
    'result_text',v_result_text,
    'drop',v_drop
  );
end;
$$;

revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. 天命豹子世界播报
-- ---------------------------------------------------------------------------
create or replace function public.world_event_from_house_game_v0140()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg boolean := true;
  v_character public.player_characters%rowtype;
  v_world_year integer;
  v_unit text := case when new.stake_type = 'cultivation' then '点修为' else '枚灵石' end;
  v_game_name text := case new.game_code when 'spirit_dice' then '灵骰问道' else '气运龟卜' end;
  v_title text;
  v_content text;
  v_level smallint := 1;
  v_net bigint := greatest(0, coalesce(new.reward_amount, 0) - coalesce(new.stake_amount, 0));
  v_destiny_triple boolean := false;
begin
  v_destiny_triple:=coalesce((new.result_payload->>'is_destiny_triple')::boolean,false);
  begin
    select s.casino_enabled into v_cfg from public.jiuxiao_world_event_settings s where s.singleton_id = 1;
    if not coalesce(v_cfg, true) then return new; end if;

    select pc.* into v_character from public.player_characters pc where pc.id = new.character_id;
    if v_character.id is null then return new; end if;
    select gw.current_year into v_world_year from public.game_worlds gw where gw.id = v_character.world_id;

    if new.outcome_code = 'win' and v_destiny_triple then
      v_title := '天命豹子';
      v_level := 3;
      v_content := format(
        '紫气贯入万运博弈楼，修士【%s】以%s%s落注“灵骰问道”，竟遇天命豹子，一局净得%s%s。',
        v_character.name,new.stake_amount,v_unit,v_net,v_unit
      );
    elsif new.outcome_code = 'win' then
      v_title := case when v_net >= greatest(100000, new.stake_amount * 10) then '一掷得势' else '赌运亨通' end;
      v_level := case when new.stake_type = 'cultivation' or v_net >= 100000 then 2 else 1 end;
      v_content := format('修士【%s】于万运博弈楼以%s%s落注“%s”，押中天机，一局净得%s%s。', v_character.name, new.stake_amount, v_unit, v_game_name, v_net, v_unit);
    else
      v_title := case when new.stake_type = 'cultivation' then '修为折损' else '时运不济' end;
      v_level := case when new.stake_type = 'cultivation' or new.stake_amount >= 100000 then 2 else 1 end;
      v_content := format('修士【%s】于万运博弈楼以%s%s落注“%s”，奈何天意难测，一局折损%s%s。', v_character.name, new.stake_amount, v_unit, v_game_name, new.stake_amount, v_unit);
    end if;

    perform public.world_event_publish_v0140(
      v_character.world_id, v_world_year,
      case when v_destiny_triple then 'casino_destiny_triple' else 'casino_house_' || new.outcome_code end,
      v_level,
      v_character.id, v_character.name, v_title, v_content,
      'casino_house_games', new.id::text,
      jsonb_build_object(
        'game_code',new.game_code,
        'stake_type',new.stake_type,
        'stake_amount',new.stake_amount,
        'reward_amount',new.reward_amount,
        'net_change',case when new.outcome_code='win' then v_net else -new.stake_amount end,
        'is_destiny_triple',v_destiny_triple
      ),
      false, null
    );
  exception when others then
    return new;
  end;
  return new;
end;
$$;

revoke all on function public.world_event_from_house_game_v0140() from public,anon,authenticated;

comment on function public.casino_spirit_dice_rule_v0141_fix7(integer,integer,integer,text,boolean,integer) is
  'V0.14.1 FIX7：豹子仍按点数归入大小；普通豹子按1倍，仅天命豹子按34倍。';
comment on function public.play_house_game_v1(text,text,bigint,text) is
  'V0.14.1 FIX7：对应豹子后以9/275判定天命豹子；固定押一边触发率1/2200，长期赌场优势约1%。';

-- 已安装CACHE1及后续发布控制时，提升epoch以通知旧客户端刷新。
do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is not null then
    update public.jiuxiao_app_release_control
    set cache_epoch=greatest(coalesce(cache_epoch,0)+1,4),
        release_name='V0.14.1 FIX7 CACHE4',
        notice_text='天命豹子与赌坊期望值已更新，正在加载最新页面。',
        updated_at=now()
    where singleton_id=1;
  end if;
end;
$$;

commit;
notify pgrst,'reload schema';

-- ---------------------------------------------------------------------------
-- 5. 执行后检查
-- ---------------------------------------------------------------------------
select * from (values
  ('destiny_columns_exist',
    exists(select 1 from information_schema.columns where table_schema='public' and table_name='casino_settings' and column_name='spirit_dice_destiny_triple_numerator')
    and exists(select 1 from information_schema.columns where table_schema='public' and table_name='casino_settings' and column_name='spirit_dice_destiny_triple_denominator')
    and exists(select 1 from information_schema.columns where table_schema='public' and table_name='casino_settings' and column_name='spirit_dice_destiny_triple_net_odds'),
    '天命豹子参数列存在'),
  ('destiny_chance_is_9_of_275',
    coalesce((select spirit_dice_destiny_triple_numerator=9 and spirit_dice_destiny_triple_denominator=275 from public.casino_settings where singleton_id=1),false),
    '豹子后9/275触发天命豹子'),
  ('destiny_odds_is_34',
    coalesce((select spirit_dice_destiny_triple_net_odds=34 from public.casino_settings where singleton_id=1),false),
    '天命豹子净赔率34倍'),
  ('dice_rule_function_exists',
    to_regprocedure('public.casino_spirit_dice_rule_v0141_fix7(integer,integer,integer,text,boolean,integer)') is not null,
    '灵骰FIX7规则函数存在'),
  ('house_rpc_exists',to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is not null,'大堂结算RPC存在'),
  ('world_event_function_exists',to_regprocedure('public.world_event_from_house_game_v0140()') is not null,'天命豹子播报函数存在'),
  ('triple_choice_disabled',not public.casino_validate_choice_v1('spirit_dice','triple'),'仍不允许独立押豹子'),
  ('111_small_normal_triple_is_1x',
    coalesce((public.casino_spirit_dice_rule_v0141_fix7(1,1,1,'small',false,34)->>'won')::boolean,false)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix7(1,1,1,'small',false,34)->>'is_triple')::boolean,false)
    and not coalesce((public.casino_spirit_dice_rule_v0141_fix7(1,1,1,'small',false,34)->>'is_destiny_triple')::boolean,true)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix7(1,1,1,'small',false,34)->>'net_odds')::integer=1,false),
    '押小遇普通111豹子按1倍'),
  ('111_small_destiny_is_34x',
    coalesce((public.casino_spirit_dice_rule_v0141_fix7(1,1,1,'small',true,34)->>'is_destiny_triple')::boolean,false)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix7(1,1,1,'small',true,34)->>'net_odds')::integer=34,false),
    '押小遇天命111按34倍'),
  ('111_big_still_loses',
    not coalesce((public.casino_spirit_dice_rule_v0141_fix7(1,1,1,'big',true,34)->>'won')::boolean,true)
    and not coalesce((public.casino_spirit_dice_rule_v0141_fix7(1,1,1,'big',true,34)->>'is_destiny_triple')::boolean,true),
    '押大遇111仍判负且不能触发天命豹子'),
  ('fixed_side_destiny_probability_is_1_of_2200',
    3::numeric*9::numeric*2200::numeric=216::numeric*275::numeric,
    '固定押一边时天命豹子概率恰为1/2200'),
  ('sample_100_ordinary_total_is_195',
    (100+100-(public.casino_house_stake_split_v0141_fix3(100)->>'pool_contribution')::bigint)=195,
    '普通结果及普通豹子押100命中到账195'),
  ('sample_100_destiny_total_is_3495',
    (100+100*34-(public.casino_house_stake_split_v0141_fix3(100)->>'pool_contribution')::bigint)=3495,
    '天命豹子押100命中到账3495'),
  ('expected_net_per_100_is_minus_1',
    (105::numeric*275::numeric*95::numeric
      +3::numeric*(9::numeric*3395::numeric+266::numeric*95::numeric)
      -108::numeric*275::numeric*100::numeric)
      =-(216::numeric*275::numeric),
    '每押100长期数学期望为-1，赌场优势1%')
) as checks(check_name,ok,detail)
order by check_name;
