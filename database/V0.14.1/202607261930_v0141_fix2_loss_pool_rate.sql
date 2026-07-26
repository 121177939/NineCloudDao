-- 九霄问道 Web Alpha V0.14.1 FIX2
-- 赌坊造化池入池比例热修复
-- 规则：仅实际输掉的赌注参与分流，其中5%进入对应全服造化池，95%由天道回收。
-- 赢局、退款、取消、超时返还与同招流局均不进入造化池。
-- 本脚本依赖 V0.14.1 主迁移已成功执行。

begin;

-- ---------------------------------------------------------------------------
-- 0. 前置检查
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.casino_settings') is null
     or to_regclass('public.casino_pools') is null
     or to_regclass('public.casino_house_games') is null
     or to_regclass('public.casino_duels') is null then
    raise exception 'V0.14.1_REQUIRED_TABLES_MISSING';
  end if;
  if to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is null
     or to_regprocedure('public.casino_settle_duels_v1()') is null
     or to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null then
    raise exception 'V0.14.1_REQUIRED_FUNCTIONS_MISSING';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. 配置与审计字段
-- ---------------------------------------------------------------------------
alter table public.casino_settings
  add column if not exists loss_pool_rate numeric(6,5) not null default 0.05000;

update public.casino_settings
set loss_pool_rate=0.05000,
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
      and c.conname='casino_settings_loss_pool_rate_v0141_fix2_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_loss_pool_rate_v0141_fix2_check
      check (loss_pool_rate between 0 and 1);
  end if;
end;
$$;

alter table public.casino_house_games
  add column if not exists heaven_recovery_amount bigint not null default 0;

alter table public.casino_duels
  add column if not exists heaven_recovery_amount bigint not null default 0;

-- ---------------------------------------------------------------------------
-- 2. 统一计算“5%入池、95%天道回收”
-- ---------------------------------------------------------------------------
create or replace function public.casino_loss_split_v0141_fix2(p_loss_amount bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_rate numeric(6,5):=coalesce((
    select s.loss_pool_rate
    from public.casino_settings s
    where s.singleton_id=1
  ),0.05000);
  v_pool bigint;
  v_recovery bigint;
begin
  if p_loss_amount is null or p_loss_amount<0 then
    raise exception 'CASINO_INVALID_LOSS_AMOUNT';
  end if;

  -- 灵石与修为均为整数，比例结果向下取整，绝不超过实际亏损的5%。
  v_pool:=floor(p_loss_amount::numeric*v_rate)::bigint;
  v_recovery:=p_loss_amount-v_pool;

  return jsonb_build_object(
    'loss_amount',p_loss_amount,
    'pool_rate',v_rate,
    'pool_contribution',v_pool,
    'heaven_recovery',v_recovery
  );
end;
$$;

revoke all on function public.casino_loss_split_v0141_fix2(bigint) from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 3. 贵宾雅间结算：只分流败者实际损失的一笔赌注
-- ---------------------------------------------------------------------------
create or replace function public.casino_settle_duels_v1()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  d record;
  v_result integer;
  v_prize bigint;
  v_pool_contribution bigint;
  v_heaven_recovery bigint;
  v_loss_split jsonb;
  v_winner uuid;
  v_loser uuid;
  v_creator_name text;
  v_opponent_name text;
  v_credit jsonb;
  v_requested_prize bigint;
  v_result_text text;
  v_drop jsonb;
  v_count integer:=0;
  v_creator_new_qualification boolean;
  v_opponent_new_qualification boolean;
begin
  for d in
    select *
    from public.casino_duels x
    where x.status='sealed' and x.reveal_at<=now()
    for update skip locked
  loop
    v_result:=public.casino_result_v1(d.game_code,d.creator_choice,d.opponent_choice);
    select pc.name into v_creator_name from public.player_characters pc where pc.id=d.creator_character_id;
    select pc.name into v_opponent_name from public.player_characters pc where pc.id=d.opponent_character_id;

    if v_result=0 then
      perform public.casino_credit_v1(d.creator_character_id,d.stake_type,d.stake_amount);
      perform public.casino_credit_v1(d.opponent_character_id,d.stake_type,d.stake_amount);
      v_result_text:=format(
        '五分钟已尽，无相阵盘同时显出【%s】。双方同招，此局流局，赌注原数奉还；没有实际亏损，因此不进入造化池。',
        public.casino_choice_name_v1(d.game_code,d.creator_choice)
      );
      update public.casino_duels x
      set status='draw',
          fee_amount=0,
          prize_amount=0,
          pool_contribution=0,
          heaven_recovery_amount=0,
          settled_at=now(),
          result_text=v_result_text,
          updated_at=now()
      where x.id=d.id;
    else
      v_winner:=case when v_result=1 then d.creator_character_id else d.opponent_character_id end;
      v_loser:=case when v_result=1 then d.opponent_character_id else d.creator_character_id end;

      -- 贵宾雅间只有败者的一笔赌注属于“实际损失”。
      v_loss_split:=public.casino_loss_split_v0141_fix2(d.stake_amount);
      v_pool_contribution:=coalesce((v_loss_split->>'pool_contribution')::bigint,0);
      v_heaven_recovery:=coalesce((v_loss_split->>'heaven_recovery')::bigint,d.stake_amount);
      v_requested_prize:=d.stake_amount*2;

      if v_pool_contribution>0 then
        update public.casino_pools p
        set amount=p.amount+v_pool_contribution,
            updated_at=now()
        where p.stake_type=d.stake_type;
      end if;

      -- 保持现有雅间胜者奖励规则不变，只修正造化池资金来源。
      v_credit:=public.casino_credit_result_v0141(v_winner,d.stake_type,v_requested_prize);
      v_prize:=coalesce((v_credit->>'granted_amount')::bigint,0);

      if d.stake_type='cultivation' then
        v_drop:=public.casino_realign_after_loss_v1(v_loser);
      end if;

      v_creator_new_qualification:=public.casino_add_ticket_v1(d.creator_character_id,d.stake_type);
      v_opponent_new_qualification:=public.casino_add_ticket_v1(d.opponent_character_id,d.stake_type);

      v_result_text:=format(
        '无相阵盘开契：%s施展【%s】，%s施展【%s】。%s胜出，获得%s%s；败者实际折损%s%s，其中%s%s进入全服造化池，余下%s%s由天道回收。二人均已纳入本期等权候选名录。%s',
        coalesce(v_creator_name,'创建者'),public.casino_choice_name_v1(d.game_code,d.creator_choice),
        coalesce(v_opponent_name,'应局者'),public.casino_choice_name_v1(d.game_code,d.opponent_choice),
        case when v_result=1 then coalesce(v_creator_name,'创建者') else coalesce(v_opponent_name,'应局者') end,
        v_prize,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        d.stake_amount,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        v_pool_contribution,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        v_heaven_recovery,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        case
          when d.stake_type='cultivation' and coalesce((v_credit->>'discarded_amount')::bigint,0)>0
            then format(' 胜者受境界上限所限，另有%s点修为未能纳入体内。',v_credit->>'discarded_amount')
          when d.stake_type='cultivation' and coalesce((v_drop->>'stage_changed')::boolean,false)
            then format(' 败者境界由【%s】跌至【%s】，但未跌出当前大境界。',v_drop->>'stage_before_name',v_drop->>'stage_after_name')
          else ''
        end
      );

      update public.casino_duels x
      set status='settled',
          winner_character_id=v_winner,
          fee_amount=0,
          prize_amount=v_prize,
          pool_contribution=v_pool_contribution,
          heaven_recovery_amount=v_heaven_recovery,
          settled_at=now(),
          result_text=v_result_text,
          updated_at=now()
      where x.id=d.id;
    end if;

    v_count:=v_count+1;
    v_drop:=null;
    v_credit:=null;
    v_loss_split:=null;
    v_pool_contribution:=0;
    v_heaven_recovery:=0;
  end loop;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. 大堂结算：只有败局的实际损失按5%/95%分流
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
  v_loss_split jsonb;
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
    v_requested_reward:=p_stake_amount*(1+v_net_odds);
    v_credit:=public.casino_credit_result_v0141(v_character_id,v_stake_type,v_requested_reward);
    v_reward:=coalesce((v_credit->>'granted_amount')::bigint,0);
    if v_stake_type='cultivation' and coalesce((v_credit->>'discarded_amount')::bigint,0)>0 then
      v_result_text:=v_result_text||format(
        ' 受境界上限所限，另有%s点修为未能纳入体内。',
        v_credit->>'discarded_amount'
      );
    end if;
  else
    v_loss_split:=public.casino_loss_split_v0141_fix2(p_stake_amount);
    v_pool_contribution:=coalesce((v_loss_split->>'pool_contribution')::bigint,0);
    v_heaven_recovery:=coalesce((v_loss_split->>'heaven_recovery')::bigint,p_stake_amount);

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
  end if;

  -- 每名本期参与者仍只有一份等权候选资格，与个人入池金额无关。
  v_ticket:=public.casino_add_ticket_v1(v_character_id,v_stake_type);

  if v_won then
    v_result_text:=v_result_text||format(
      ' 本局没有实际亏损，不向造化池注入资源；%s',
      case
        when v_ticket then '你已取得本期等权候选资格。'
        else '你已在本期候选名录中，本局不会叠加个人中奖权重。'
      end
    );
  else
    v_result_text:=v_result_text||format(
      ' 本局实际折损%s%s，其中%s%s进入全服造化池，余下%s%s由天道回收；%s',
      p_stake_amount,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_pool_contribution,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_heaven_recovery,case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
      case
        when v_ticket then '你已取得本期等权候选资格。'
        else '你已在本期候选名录中，本局不会叠加个人中奖权重。'
      end
    );
  end if;

  insert into public.casino_house_games(
    character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,
    reward_amount,fee_amount,pool_contribution,heaven_recovery_amount,
    result_payload,result_text
  ) values (
    v_character_id,p_game_code,v_stake_type,p_stake_amount,p_choice,
    case when v_won then 'win' else 'loss' end,
    v_reward,0,v_pool_contribution,v_heaven_recovery,
    v_result_payload,v_result_text
  );

  return jsonb_build_object(
    'won',v_won,
    'reward',v_reward,
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
-- 5. 权限、注释与执行后检查
-- ---------------------------------------------------------------------------
revoke all on function public.casino_settle_duels_v1() from public,anon,authenticated;
revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;
grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;

comment on table public.casino_pools is
  'V0.14.1 FIX2：全服共享灵石/修为造化池；仅实际败局损失的5%入池，95%由天道回收；40%开奖命中，未中全额滚存。';
comment on column public.casino_settings.loss_pool_rate is
  '败局实际损失进入全服造化池的比例；V0.14.1 FIX2固定为0.05。';
comment on column public.casino_house_games.heaven_recovery_amount is
  '大堂败局中未进入造化池、由天道回收的实际损失；赢局为0。';
comment on column public.casino_duels.heaven_recovery_amount is
  '雅间胜负局中败者损失未进入造化池、由天道回收的部分；流局为0。';
comment on function public.casino_loss_split_v0141_fix2(bigint) is
  'V0.14.1 FIX2：将实际败局损失按5%造化池、95%天道回收分流，整数结果向下取整。';

commit;
notify pgrst,'reload schema';

select * from (values
  ('loss_pool_rate_is_5_percent',coalesce((select loss_pool_rate=0.05000 from public.casino_settings where singleton_id=1),false),'败局入池比例为5%'),
  ('house_recovery_column_ready',exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='casino_house_games' and column_name='heaven_recovery_amount'
  ),'大堂天道回收审计字段存在'),
  ('duel_recovery_column_ready',exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='casino_duels' and column_name='heaven_recovery_amount'
  ),'雅间天道回收审计字段存在'),
  ('loss_split_function_ready',to_regprocedure('public.casino_loss_split_v0141_fix2(bigint)') is not null,'败局分流函数存在'),
  ('house_rpc_ready',to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is not null,'大堂结算RPC已更新'),
  ('duel_rpc_ready',to_regprocedure('public.casino_settle_duels_v1()') is not null,'雅间结算RPC已更新'),
  ('sample_5000_pool_is_250',coalesce((public.casino_loss_split_v0141_fix2(5000)->>'pool_contribution')::bigint=250,false),'5000实际损失仅250进入造化池'),
  ('sample_5000_recovery_is_4750',coalesce((public.casino_loss_split_v0141_fix2(5000)->>'heaven_recovery')::bigint=4750,false),'5000实际损失中4750由天道回收')
) as checks(name,ok,detail)
order by name;
