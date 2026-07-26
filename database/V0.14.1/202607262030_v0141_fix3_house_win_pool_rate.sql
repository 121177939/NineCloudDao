-- 九霄问道 Web Alpha V0.14.1 FIX3
-- 大堂赢局造化池比例热修复
-- 规则：大堂每一笔成功结算的赌注，固定按赌注金额的5%进入对应全服造化池。
-- 赢局：返还本金，并发放扣除该5%后的赔率盈利；例如押100、1倍胜出，到账195，奖池增加5。
-- 败局：奖池增加赌注的5%，其余95%由天道回收。
-- 灵石与修为使用完全相同的结算规则。
-- 贵宾雅间继续沿用FIX2规则：仅败者实际损失的5%入池，同招流局不入池。
-- 本脚本依赖 V0.14.1 主迁移与 V0.14.1 FIX2 已成功执行。

begin;

-- ---------------------------------------------------------------------------
-- 0. 前置检查
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.casino_settings') is null
     or to_regclass('public.casino_pools') is null
     or to_regclass('public.casino_house_games') is null then
    raise exception 'V0.14.1_FIX2_REQUIRED_TABLES_MISSING';
  end if;

  if to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is null
     or to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null
     or to_regprocedure('public.casino_loss_split_v0141_fix2(bigint)') is null then
    raise exception 'V0.14.1_FIX2_REQUIRED_FUNCTIONS_MISSING';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. 大堂独立入池比例与审计字段
-- ---------------------------------------------------------------------------
alter table public.casino_settings
  add column if not exists house_pool_rate numeric(6,5) not null default 0.05000;

update public.casino_settings
set house_pool_rate=0.05000,
    updated_at=now()
where singleton_id=1;

do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public'
      and t.relname='casino_settings'
      and c.conname='casino_settings_house_pool_rate_v0141_fix3_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_house_pool_rate_v0141_fix3_check
      check (house_pool_rate between 0 and 1);
  end if;
end;
$$;

alter table public.casino_house_games
  add column if not exists nominal_reward_amount bigint not null default 0;

-- ---------------------------------------------------------------------------
-- 2. 计算大堂每局固定5%入池金额
-- ---------------------------------------------------------------------------
create or replace function public.casino_house_stake_split_v0141_fix3(p_stake_amount bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_rate numeric(6,5):=coalesce((
    select s.house_pool_rate
    from public.casino_settings s
    where s.singleton_id=1
  ),0.05000);
  v_pool bigint;
  v_remainder bigint;
begin
  if p_stake_amount is null or p_stake_amount<0 then
    raise exception 'CASINO_INVALID_STAKE_AMOUNT';
  end if;

  -- 灵石与修为都只使用整数。比例结果向下取整，确保不会多扣。
  v_pool:=floor(p_stake_amount::numeric*v_rate)::bigint;
  v_remainder:=p_stake_amount-v_pool;

  return jsonb_build_object(
    'stake_amount',p_stake_amount,
    'pool_rate',v_rate,
    'pool_contribution',v_pool,
    'stake_remainder',v_remainder
  );
end;
$$;

revoke all on function public.casino_house_stake_split_v0141_fix3(bigint) from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 3. 大堂结算
--    胜：本金 +（赔率盈利 - 赌注5%）
--    负：赌注5%入池，其余95%天道回收
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

  -- 每一局完成结算的大堂赌注都固定提取5%进入对应全服造化池。
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
    v_total:=v_d1+v_d2+v_d3;
    if p_choice='triple' then
      v_won:=v_d1=v_d2 and v_d2=v_d3;
      v_net_odds:=34;
    else
      v_won:=not(v_d1=v_d2 and v_d2=v_d3)
        and ((p_choice='small' and v_total between 4 and 10)
          or (p_choice='big' and v_total between 11 and 17));
      v_net_odds:=1;
    end if;
    v_result_text:=format(
      '荷老揭开玉盅，三枚灵骰显出【%s、%s、%s】，共%s点。%s',
      v_d1,v_d2,v_d3,v_total,
      case
        when v_d1=v_d2 and v_d2=v_d3 then '三相归一，围骰通杀。'
        when v_won then '你押中了此局。'
        else '此局与你所押不合。'
      end
    );
    v_result_payload:=jsonb_build_object(
      'dice',jsonb_build_array(v_d1,v_d2,v_d3),
      'total',v_total,
      'choice',p_choice
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
    -- 例：押100、净赔率1倍 => 名义奖励200，入池5，实际请求返还195。
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

  -- 每名本期参与者仍只有一份等权候选资格，与游玩次数和个人入池金额无关。
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

-- ---------------------------------------------------------------------------
-- 4. 权限、注释与执行后检查
-- ---------------------------------------------------------------------------
revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;

comment on table public.casino_pools is
  'V0.14.1 FIX3：大堂每一笔成功结算赌注的5%入池；大堂胜局从赔率盈利中扣除该5%，败局余下95%天道回收；雅间仅败者损失5%入池；40%开奖命中，未中全额滚存。';
comment on column public.casino_settings.house_pool_rate is
  '大堂每一笔成功结算赌注进入全服造化池的比例；V0.14.1 FIX3固定为0.05。';
comment on column public.casino_house_games.nominal_reward_amount is
  '大堂胜局按原始赔率计算、尚未扣除本局造化池贡献前的名义总返还；败局为0。';
comment on column public.casino_house_games.heaven_recovery_amount is
  '大堂败局中未进入造化池、由天道回收的部分；胜局为0。';
comment on function public.casino_house_stake_split_v0141_fix3(bigint) is
  'V0.14.1 FIX3：计算大堂每局赌注固定5%入池金额，整数结果向下取整。';

commit;
notify pgrst,'reload schema';

select * from (values
  ('house_pool_rate_is_5_percent',coalesce((select house_pool_rate=0.05000 from public.casino_settings where singleton_id=1),false),'大堂每一局固定5%入池'),
  ('nominal_reward_column_ready',exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='casino_house_games' and column_name='nominal_reward_amount'
  ),'大堂名义返还审计字段存在'),
  ('house_split_function_ready',to_regprocedure('public.casino_house_stake_split_v0141_fix3(bigint)') is not null,'大堂赌注分流函数存在'),
  ('house_rpc_ready',to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is not null,'大堂结算RPC已更新'),
  ('sample_100_pool_is_5',coalesce((public.casino_house_stake_split_v0141_fix3(100)->>'pool_contribution')::bigint=5,false),'押100时奖池增加5'),
  ('sample_100_remainder_is_95',coalesce((public.casino_house_stake_split_v0141_fix3(100)->>'stake_remainder')::bigint=95,false),'押100时剩余95'),
  ('sample_even_win_total_is_195',(100+100-(public.casino_house_stake_split_v0141_fix3(100)->>'pool_contribution')::bigint)=195,'押100、1倍胜出总到账195'),
  ('duel_loss_rate_still_5_percent',coalesce((select loss_pool_rate=0.05000 from public.casino_settings where singleton_id=1),false),'贵宾雅间败者损失仍为5%入池')
) as checks(name,ok,detail)
order by name;
