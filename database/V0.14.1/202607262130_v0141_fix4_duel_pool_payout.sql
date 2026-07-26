-- 九霄问道 Web Alpha V0.14.1 FIX4
-- 贵宾雅间胜者结算热修复
-- 规则：贵宾雅间与大堂采用一致的5%入池结算。
-- 例：A押100、B押100，A胜出，则A共到账195，B损失100，造化池增加5。
-- 其中A自己的100本金原数返还，败者100赌注中的95转给A，剩余5进入对应全服造化池。
-- 灵石与修为使用完全相同的规则；同招流局、取消、超时返还不入池。
-- 本脚本依赖 V0.14.1 主迁移、FIX2 与 FIX3 已成功执行。

begin;

-- ---------------------------------------------------------------------------
-- 0. 前置检查
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.casino_settings') is null
     or to_regclass('public.casino_pools') is null
     or to_regclass('public.casino_duels') is null then
    raise exception 'V0.14.1_FIX3_REQUIRED_TABLES_MISSING';
  end if;

  if to_regprocedure('public.casino_settle_duels_v1()') is null
     or to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null
     or to_regprocedure('public.casino_add_ticket_v1(uuid,text)') is null
     or to_regprocedure('public.casino_house_stake_split_v0141_fix3(bigint)') is null then
    raise exception 'V0.14.1_FIX3_REQUIRED_FUNCTIONS_MISSING';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. 雅间赌注分流：赌注5%入池、95%转给胜者
-- ---------------------------------------------------------------------------
create or replace function public.casino_duel_stake_split_v0141_fix4(p_stake_amount bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_split jsonb;
  v_pool bigint;
  v_winner_transfer bigint;
begin
  if p_stake_amount is null or p_stake_amount<0 then
    raise exception 'CASINO_INVALID_STAKE_AMOUNT';
  end if;

  -- 雅间与大堂使用同一5%入池比例和同一整数向下取整规则。
  v_split:=public.casino_house_stake_split_v0141_fix3(p_stake_amount);
  v_pool:=coalesce((v_split->>'pool_contribution')::bigint,0);
  v_winner_transfer:=p_stake_amount-v_pool;

  return jsonb_build_object(
    'stake_amount',p_stake_amount,
    'pool_contribution',v_pool,
    'winner_transfer',v_winner_transfer,
    'winner_total_payout',p_stake_amount+v_winner_transfer,
    'heaven_recovery',0
  );
end;
$$;

revoke all on function public.casino_duel_stake_split_v0141_fix4(bigint) from public,anon,authenticated;

-- ---------------------------------------------------------------------------
-- 2. 贵宾雅间结算
--    胜者：返还自己的本金 + 获得败者赌注的95%
--    败者：损失全部赌注
--    造化池：获得败者赌注的5%
--    天道：本玩法不再额外回收败者赌注
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
  v_winner_transfer bigint;
  v_heaven_recovery bigint:=0;
  v_stake_split jsonb;
  v_winner uuid;
  v_loser uuid;
  v_creator_name text;
  v_opponent_name text;
  v_winner_name text;
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
      v_winner_name:=case when v_result=1 then coalesce(v_creator_name,'创建者') else coalesce(v_opponent_name,'应局者') end;

      -- 双方赌注已在开桌和应局时分别扣除。
      -- 胜者自己的本金原数返还；败者赌注的95%转给胜者，5%进入造化池。
      v_stake_split:=public.casino_duel_stake_split_v0141_fix4(d.stake_amount);
      v_pool_contribution:=coalesce((v_stake_split->>'pool_contribution')::bigint,0);
      v_winner_transfer:=coalesce((v_stake_split->>'winner_transfer')::bigint,d.stake_amount);
      v_requested_prize:=coalesce((v_stake_split->>'winner_total_payout')::bigint,d.stake_amount*2-v_pool_contribution);
      v_heaven_recovery:=0;

      if v_pool_contribution>0 then
        update public.casino_pools p
        set amount=p.amount+v_pool_contribution,
            updated_at=now()
        where p.stake_type=d.stake_type;
      end if;

      v_credit:=public.casino_credit_result_v0141(v_winner,d.stake_type,v_requested_prize);
      v_prize:=coalesce((v_credit->>'granted_amount')::bigint,0);

      if d.stake_type='cultivation' then
        v_drop:=public.casino_realign_after_loss_v1(v_loser);
      end if;

      v_creator_new_qualification:=public.casino_add_ticket_v1(d.creator_character_id,d.stake_type);
      v_opponent_new_qualification:=public.casino_add_ticket_v1(d.opponent_character_id,d.stake_type);

      v_result_text:=format(
        '无相阵盘开契：%s施展【%s】，%s施展【%s】。%s胜出；其自身本金%s%s原数返还，并取得败者赌注中的%s%s，合计到账%s%s。败者损失%s%s，剩余%s%s进入全服造化池。二人均已纳入本期等权候选名录。%s',
        coalesce(v_creator_name,'创建者'),public.casino_choice_name_v1(d.game_code,d.creator_choice),
        coalesce(v_opponent_name,'应局者'),public.casino_choice_name_v1(d.game_code,d.opponent_choice),
        v_winner_name,
        d.stake_amount,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        v_winner_transfer,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        v_prize,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        d.stake_amount,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        v_pool_contribution,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        case
          when d.stake_type='cultivation' and coalesce((v_credit->>'discarded_amount')::bigint,0)>0
            then format(' 受胜者当前境界修为上限所限，另有%s点修为未能纳入体内。',v_credit->>'discarded_amount')
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
          heaven_recovery_amount=0,
          settled_at=now(),
          result_text=v_result_text,
          updated_at=now()
      where x.id=d.id;
    end if;

    v_count:=v_count+1;
    v_drop:=null;
    v_credit:=null;
    v_stake_split:=null;
    v_pool_contribution:=0;
    v_winner_transfer:=0;
    v_heaven_recovery:=0;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.casino_settle_duels_v1() from public,anon,authenticated;

comment on function public.casino_duel_stake_split_v0141_fix4(bigint) is
  'V0.14.1 FIX4：贵宾雅间败者赌注的5%进入造化池，95%转给胜者；胜者另取回自己的本金。';
comment on function public.casino_settle_duels_v1() is
  'V0.14.1 FIX4：雅间双方等额下注，胜者到账=自身本金+败者赌注95%，败者赌注5%入池，天道不再回收雅间败者赌注。';
comment on column public.casino_duels.heaven_recovery_amount is
  '大堂败局可记录天道回收；V0.14.1 FIX4起贵宾雅间正常胜负固定为0，同招流局亦为0。';
comment on table public.casino_pools is
  'V0.14.1 FIX4：大堂每局赌注5%入池；贵宾雅间分胜负时败者赌注5%入池、95%转给胜者；同招流局与退款不入池；40%开奖命中，未中全额滚存。';

commit;
notify pgrst,'reload schema';

select * from (values
  ('duel_split_function_exists',to_regprocedure('public.casino_duel_stake_split_v0141_fix4(bigint)') is not null,'雅间5%分流函数存在'),
  ('duel_settle_function_exists',to_regprocedure('public.casino_settle_duels_v1()') is not null,'雅间结算函数存在'),
  ('sample_100_pool_is_5',coalesce((public.casino_duel_stake_split_v0141_fix4(100)->>'pool_contribution')::bigint=5,false),'双方各押100时奖池增加5'),
  ('sample_100_winner_transfer_is_95',coalesce((public.casino_duel_stake_split_v0141_fix4(100)->>'winner_transfer')::bigint=95,false),'败者赌注中的95转给胜者'),
  ('sample_100_winner_total_is_195',coalesce((public.casino_duel_stake_split_v0141_fix4(100)->>'winner_total_payout')::bigint=195,false),'胜者总到账195'),
  ('sample_100_heaven_recovery_is_0',coalesce((public.casino_duel_stake_split_v0141_fix4(100)->>'heaven_recovery')::bigint=0,false),'雅间正常胜负天道回收为0')
) as checks(check_name,ok,detail);
