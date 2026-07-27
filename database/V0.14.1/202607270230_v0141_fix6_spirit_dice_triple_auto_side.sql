-- 九霄问道 Web Alpha V0.14.1 FIX6 CACHE3
-- 灵骰豹子自动归入大小热修复
--
-- 最终规则：
-- 1. 玩家只押“大”或“小”，不再提供独立“围骰/豹子”押注。
-- 2. 三骰总点数3—10为小，11—18为大；豹子同样按总点数归类。
-- 3. 111/222/333归小，444/555/666归大。
-- 4. 普通非豹子命中：净赔率1倍。
-- 5. 豹子命中对应大小：净赔率34倍。
-- 6. 大堂每局赌注5%进入全服造化池的FIX3规则保持不变。
--    例：押100，豹子命中，赔率盈利3400，入池5，本金返还后实际总到账3495。
--
-- 前置：V0.14.1主迁移、FIX2、FIX3、FIX4已完成；FIX5可在此前或此后执行。

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
-- 1. 可审计的灵骰规则函数
-- ---------------------------------------------------------------------------
create or replace function public.casino_spirit_dice_rule_v0141_fix6(
  p_d1 integer,
  p_d2 integer,
  p_d3 integer,
  p_choice text
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

  v_total:=p_d1+p_d2+p_d3;
  v_side:=case when v_total between 3 and 10 then 'small' else 'big' end;
  v_is_triple:=p_d1=p_d2 and p_d2=p_d3;
  v_won:=p_choice=v_side;
  v_net_odds:=case when v_won and v_is_triple then 34 when v_won then 1 else 0 end;

  return jsonb_build_object(
    'total',v_total,
    'result_side',v_side,
    'is_triple',v_is_triple,
    'won',v_won,
    'net_odds',v_net_odds
  );
end;
$$;

revoke all on function public.casino_spirit_dice_rule_v0141_fix6(integer,integer,integer,text)
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
-- 2. 重建大堂结算RPC，仅修改灵骰规则；FIX3的5%入池账务完整继承
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
    v_d1:=1+floor(random()*6)::integer;
    v_d2:=1+floor(random()*6)::integer;
    v_d3:=1+floor(random()*6)::integer;

    v_dice_rule:=public.casino_spirit_dice_rule_v0141_fix6(v_d1,v_d2,v_d3,p_choice);
    v_total:=coalesce((v_dice_rule->>'total')::integer,v_d1+v_d2+v_d3);
    v_result_side:=v_dice_rule->>'result_side';
    v_side_name:=case when v_result_side='small' then '小' else '大' end;
    v_is_triple:=coalesce((v_dice_rule->>'is_triple')::boolean,false);
    v_won:=coalesce((v_dice_rule->>'won')::boolean,false);
    v_net_odds:=coalesce((v_dice_rule->>'net_odds')::integer,0);

    v_result_text:=format(
      '荷老揭开玉盅，三枚灵骰显出【%s、%s、%s】，共%s点，归于【%s】。%s',
      v_d1,v_d2,v_d3,v_total,v_side_name,
      case
        when v_is_triple and v_won then '三相归一，豹子显化；你押中大小，本局按净赔率34倍结算。'
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
    -- 普通押100命中：100本金+100盈利-5入池=195。
    -- 豹子押100命中：100本金+3400盈利-5入池=3495。
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

comment on function public.casino_spirit_dice_rule_v0141_fix6(integer,integer,integer,text) is
  'V0.14.1 FIX6：灵骰只押大小，豹子按总点数自动归类，命中对应大小时净赔率34倍。';
comment on function public.play_house_game_v1(text,text,bigint,text) is
  'V0.14.1 FIX6：大堂灵骰3—10小、11—18大，豹子自动归类并按净赔率34倍；每局5%入池规则继承FIX3。';

-- 已安装CACHE1及后续发布控制时，提升epoch以通知旧客户端刷新。
do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is not null then
    update public.jiuxiao_app_release_control
    set cache_epoch=greatest(coalesce(cache_epoch,0)+1,3),
        release_name='V0.14.1 FIX6 CACHE3',
        notice_text='灵骰豹子规则已更新，正在加载最新页面。',
        updated_at=now()
    where singleton_id=1;
  end if;
end;
$$;

commit;
notify pgrst,'reload schema';

-- ---------------------------------------------------------------------------
-- 3. 执行后检查
-- ---------------------------------------------------------------------------
select * from (values
  ('dice_rule_function_exists',to_regprocedure('public.casino_spirit_dice_rule_v0141_fix6(integer,integer,integer,text)') is not null,'灵骰FIX6规则函数存在'),
  ('house_rpc_exists',to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is not null,'大堂结算RPC存在'),
  ('triple_choice_disabled',not public.casino_validate_choice_v1('spirit_dice','triple'),'不再允许独立押豹子'),
  ('111_is_small_triple',
    coalesce((public.casino_spirit_dice_rule_v0141_fix6(1,1,1,'small')->>'result_side')='small',false)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix6(1,1,1,'small')->>'is_triple')::boolean,false),
    '111豹子归小'),
  ('111_small_wins_34x',
    coalesce((public.casino_spirit_dice_rule_v0141_fix6(1,1,1,'small')->>'won')::boolean,false)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix6(1,1,1,'small')->>'net_odds')::integer=34,false),
    '押小遇111按净赔率34倍'),
  ('111_big_loses',
    not coalesce((public.casino_spirit_dice_rule_v0141_fix6(1,1,1,'big')->>'won')::boolean,true),
    '押大遇111判负'),
  ('666_big_wins_34x',
    coalesce((public.casino_spirit_dice_rule_v0141_fix6(6,6,6,'big')->>'won')::boolean,false)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix6(6,6,6,'big')->>'net_odds')::integer=34,false),
    '押大遇666按净赔率34倍'),
  ('451_is_small_normal',
    coalesce((public.casino_spirit_dice_rule_v0141_fix6(4,5,1,'small')->>'won')::boolean,false)
    and not coalesce((public.casino_spirit_dice_rule_v0141_fix6(4,5,1,'small')->>'is_triple')::boolean,true)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix6(4,5,1,'small')->>'net_odds')::integer=1,false),
    '4+5+1=10，押小普通1倍'),
  ('452_is_big_normal',
    coalesce((public.casino_spirit_dice_rule_v0141_fix6(4,5,2,'big')->>'won')::boolean,false)
    and coalesce((public.casino_spirit_dice_rule_v0141_fix6(4,5,2,'big')->>'net_odds')::integer=1,false),
    '4+5+2=11，押大普通1倍'),
  ('sample_100_pool_is_5',
    coalesce((public.casino_house_stake_split_v0141_fix3(100)->>'pool_contribution')::bigint=5,false),
    '押100仍有5进入造化池'),
  ('sample_100_triple_total_is_3495',
    (100+100*34-(public.casino_house_stake_split_v0141_fix3(100)->>'pool_contribution')::bigint)=3495,
    '押100豹子命中实际总到账3495')
) as checks(check_name,ok,detail)
order by check_name;
