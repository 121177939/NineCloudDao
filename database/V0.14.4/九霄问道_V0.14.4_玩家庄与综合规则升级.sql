-- 《九霄问道》V0.14.4：玩家自愿坐庄、修为境界锁、赌契即时结算、天劫感悟修炼加成与私人天谕
-- 前置：V0.14.3 CACHE7 + V0.14.1 FIX7A + V0.14.2严格界闻
-- 说明：本迁移整合B线玩家庄模块，并落实A线四项规则。
-- 严禁执行V0.14.1 FIX8。

begin;

-- 基线与关键对象门禁。
do $$
begin
  if to_regprocedure('public.get_wealth_ranking_v1(integer,integer)') is null then
    raise exception 'V0144_REQUIRES_V0143_WEALTH_RANKING';
  end if;
  if to_regprocedure('public.casino_spirit_dice_rule_v0141_fix7a(integer,integer,integer,text,text,integer,integer)') is null then
    raise exception 'V0144_REQUIRES_FIX7A';
  end if;
  if to_regprocedure('public.get_world_events_v1(integer)') is null then
    raise exception 'V0144_REQUIRES_V0142_WORLD_FEED';
  end if;
  if to_regclass('public.character_breakthrough_states') is null then
    raise exception 'V0144_REQUIRES_BREAKTHROUGH_STATES';
  end if;
end;
$$;

-- 《九霄问道》V0.14.4正式模块：财富榜第一玩家自愿坐庄
-- 模块ID：B-20260727-PLAYER-HOUSE-DEALER-01
-- 基线：Web Alpha V0.14.3 CACHE7 / FIX7A
--
-- 规则：
-- 1. 当前财富榜第一且统一灵石严格超过5,000,000，获得上庄资格；是否上庄由本人决定。
-- 2. 玩家庄模式只接受灵石，庄家本人不得下注自己的大堂。
-- 3. 闲家输：下注本金100%转给玩家庄家。
-- 4. 闲家赢：本金100%返还；按FIX7A实际净倍率计算毛利润，由玩家庄家100%赔付。
-- 5. 玩家庄模式不抽成、不入造化池、不发放造化池候选资格。
-- 6. 无有效玩家庄时，完整回退到原FIX7A荷老系统庄逻辑。
-- 7. 每局即时结算；受理前按该玩法最高可能净倍率检查庄家余额，避免开奖结果产生后无力赔付。
--
-- 本模块已由A线合并，脚本末尾统一更新V0.14.4 CACHE8发布控制。


-- ---------------------------------------------------------------------------
-- 0. 基线门禁
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.casino_settings') is null
     or to_regclass('public.casino_house_games') is null
     or to_regclass('public.player_characters') is null
     or to_regclass('public.character_inventory') is null then
    raise exception 'PLAYER_HOUSE_BASE_TABLES_MISSING';
  end if;

  if to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is null
     and to_regprocedure('public.play_system_house_game_v0141_fix7a(text,text,bigint,text)') is null then
    raise exception 'PLAYER_HOUSE_FIX7A_HOUSE_RPC_MISSING';
  end if;

  if to_regprocedure('public.casino_spirit_dice_rule_v0141_fix7a(integer,integer,integer,text,text,integer,integer)') is null
     or to_regprocedure('public.spirit_stone_balance_v0141(uuid)') is null
     or to_regprocedure('public.spirit_stone_debit_v0141(uuid,bigint,text)') is null
     or to_regprocedure('public.award_spirit_stones_v3(uuid,bigint)') is null then
    raise exception 'PLAYER_HOUSE_REQUIRED_FUNCTION_MISSING';
  end if;

  if not exists(
    select 1 from public.casino_settings s
    where s.singleton_id=1
      and s.spirit_dice_ordinary_triple_denominator=80
      and s.spirit_dice_destiny_triple_result_denominator=5000
      and s.spirit_dice_ordinary_triple_net_odds=3
      and s.spirit_dice_destiny_triple_net_odds=34
  ) then
    raise exception 'PLAYER_HOUSE_FIX7A_SETTINGS_MISMATCH';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. 配置、状态与审计
-- ---------------------------------------------------------------------------
alter table public.casino_settings
  add column if not exists player_house_enabled boolean not null default true,
  add column if not exists player_house_min_wealth bigint not null default 5000000;

update public.casino_settings
set player_house_enabled=true,
    player_house_min_wealth=5000000,
    updated_at=now()
where singleton_id=1;

do $$
begin
  if not exists(
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_settings'
      and c.conname='casino_settings_player_house_min_wealth_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_player_house_min_wealth_check
      check(player_house_min_wealth>=0);
  end if;
end;
$$;

create table if not exists public.casino_player_house_state (
  singleton_id smallint primary key default 1 check(singleton_id=1),
  dealer_character_id uuid references public.player_characters(id) on delete set null,
  is_active boolean not null default false,
  activated_at timestamptz,
  deactivated_at timestamptz,
  last_reason text,
  updated_at timestamptz not null default now(),
  check((is_active and dealer_character_id is not null) or not is_active)
);

insert into public.casino_player_house_state(singleton_id,is_active,last_reason)
values(1,false,'module_initialized')
on conflict(singleton_id) do nothing;

create table if not exists public.casino_player_house_events (
  id uuid primary key default gen_random_uuid(),
  action_code text not null check(action_code in ('activate','deactivate','auto_deactivate')),
  dealer_character_id uuid references public.player_characters(id) on delete set null,
  actor_character_id uuid references public.player_characters(id) on delete set null,
  dealer_wealth bigint not null default 0,
  reason_code text not null,
  created_at timestamptz not null default now()
);

create index if not exists casino_player_house_events_created_idx
  on public.casino_player_house_events(created_at desc);
create index if not exists casino_player_house_events_dealer_idx
  on public.casino_player_house_events(dealer_character_id,created_at desc);

alter table public.casino_player_house_state enable row level security;
alter table public.casino_player_house_events enable row level security;
revoke all on table public.casino_player_house_state from public,anon,authenticated;
revoke all on table public.casino_player_house_events from public,anon,authenticated;

alter table public.casino_house_games
  add column if not exists house_mode text not null default 'system',
  add column if not exists dealer_character_id uuid references public.player_characters(id) on delete set null,
  add column if not exists dealer_name_snapshot text,
  add column if not exists dealer_debit_amount bigint not null default 0,
  add column if not exists dealer_credit_amount bigint not null default 0,
  add column if not exists max_liability_amount bigint not null default 0;

do $$
begin
  if not exists(
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_house_games'
      and c.conname='casino_house_games_house_mode_check'
  ) then
    alter table public.casino_house_games
      add constraint casino_house_games_house_mode_check
      check(house_mode in ('system','player'));
  end if;

  if not exists(
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_house_games'
      and c.conname='casino_house_games_player_dealer_amounts_check'
  ) then
    alter table public.casino_house_games
      add constraint casino_house_games_player_dealer_amounts_check
      check(dealer_debit_amount>=0 and dealer_credit_amount>=0 and max_liability_amount>=0);
  end if;
end;
$$;

create index if not exists casino_house_games_dealer_created_idx
  on public.casino_house_games(dealer_character_id,created_at desc)
  where dealer_character_id is not null;

-- ---------------------------------------------------------------------------
-- 2. 财富榜第一候选人与有效庄家解析
-- ---------------------------------------------------------------------------
create or replace function public.casino_player_house_top_candidate_v1()
returns table(character_id uuid,character_name text,wealth bigint)
language sql
stable
security definer
set search_path=pg_catalog,public,auth,pg_temp
as $$
  select
    pc.id,
    pc.name,
    coalesce(stones.wealth,0)::bigint
  from public.player_characters pc
  join public.realm_stages rs on rs.id=pc.realm_stage_id
  join public.realms r on r.id=rs.realm_id
  left join lateral (
    select coalesce(sum(greatest(ci.quantity,0)),0)::bigint as wealth
    from public.character_inventory ci
    where ci.character_id=pc.id
      and ci.item_definition_id=public.spirit_stone_item_id_v0141()
  ) stones on true
  where pc.status in ('active','secluded','missing')
  order by
    coalesce(stones.wealth,0) desc,
    r.major_order desc,
    rs.minor_level desc,
    pc.cultivation desc,
    pc.created_at asc,
    pc.id asc
  limit 1;
$$;

create or replace function public.casino_player_house_resolve_dealer_v1()
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_state public.casino_player_house_state%rowtype;
  v_top_id uuid;
  v_top_wealth bigint:=0;
  v_enabled boolean:=false;
  v_min_wealth bigint:=5000000;
  v_old_dealer uuid;
  v_old_wealth bigint:=0;
begin
  perform pg_advisory_xact_lock(hashtextextended('casino-player-house-dealer',14301));

  insert into public.casino_player_house_state(singleton_id,is_active,last_reason)
  values(1,false,'state_recreated')
  on conflict(singleton_id) do nothing;

  select * into v_state
  from public.casino_player_house_state
  where singleton_id=1
  for update;

  select coalesce(s.player_house_enabled,false),coalesce(s.player_house_min_wealth,5000000)
  into v_enabled,v_min_wealth
  from public.casino_settings s
  where s.singleton_id=1;

  select x.character_id,x.wealth
  into v_top_id,v_top_wealth
  from public.casino_player_house_top_candidate_v1() x;

  if not coalesce(v_state.is_active,false) then
    return null;
  end if;

  if v_enabled
     and v_state.dealer_character_id is not null
     and v_state.dealer_character_id=v_top_id
     and coalesce(v_top_wealth,0)>v_min_wealth then
    return v_state.dealer_character_id;
  end if;

  v_old_dealer:=v_state.dealer_character_id;
  if v_old_dealer is not null then
    v_old_wealth:=public.spirit_stone_balance_v0141(v_old_dealer);
  end if;

  update public.casino_player_house_state
  set is_active=false,
      dealer_character_id=null,
      deactivated_at=now(),
      last_reason=case
        when not v_enabled then 'feature_disabled'
        when v_top_id is null then 'wealth_board_empty'
        when v_old_dealer is distinct from v_top_id then 'dealer_lost_rank_one'
        when coalesce(v_top_wealth,0)<=v_min_wealth then 'dealer_below_wealth_threshold'
        else 'dealer_invalid'
      end,
      updated_at=now()
  where singleton_id=1;

  insert into public.casino_player_house_events(
    action_code,dealer_character_id,actor_character_id,dealer_wealth,reason_code
  ) values(
    'auto_deactivate',v_old_dealer,null,coalesce(v_old_wealth,0),
    case
      when not v_enabled then 'feature_disabled'
      when v_top_id is null then 'wealth_board_empty'
      when v_old_dealer is distinct from v_top_id then 'dealer_lost_rank_one'
      when coalesce(v_top_wealth,0)<=v_min_wealth then 'dealer_below_wealth_threshold'
      else 'dealer_invalid'
    end
  );

  return null;
end;
$$;

create or replace function public.get_casino_player_house_status_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_current_id uuid;
  v_dealer_id uuid;
  v_top_id uuid;
  v_top_name text;
  v_top_wealth bigint:=0;
  v_dealer_name text;
  v_dealer_wealth bigint:=0;
  v_enabled boolean:=false;
  v_min_wealth bigint:=5000000;
  v_destiny_odds integer:=34;
  v_can_activate boolean:=false;
begin
  v_current_id:=public.casino_current_character_id_v1();
  v_dealer_id:=public.casino_player_house_resolve_dealer_v1();

  select coalesce(s.player_house_enabled,false),coalesce(s.player_house_min_wealth,5000000),
         coalesce(s.spirit_dice_destiny_triple_net_odds,34)
  into v_enabled,v_min_wealth,v_destiny_odds
  from public.casino_settings s
  where s.singleton_id=1;

  select x.character_id,x.character_name,x.wealth
  into v_top_id,v_top_name,v_top_wealth
  from public.casino_player_house_top_candidate_v1() x;

  if v_dealer_id is not null then
    select pc.name,public.spirit_stone_balance_v0141(pc.id)
    into v_dealer_name,v_dealer_wealth
    from public.player_characters pc
    where pc.id=v_dealer_id;
  end if;

  v_can_activate:=v_enabled
    and v_dealer_id is null
    and v_current_id=v_top_id
    and coalesce(v_top_wealth,0)>v_min_wealth;

  return jsonb_build_object(
    'status','ok',
    'mode',case when v_dealer_id is null then 'system' else 'player' end,
    'dealer_name',case when v_dealer_id is null then '荷老' else coalesce(v_dealer_name,'无名庄家') end,
    'dealer_wealth',case when v_dealer_id is null then null else v_dealer_wealth end,
    'is_self_dealer',v_dealer_id=v_current_id,
    'can_activate',v_can_activate,
    'can_deactivate',v_dealer_id=v_current_id,
    'top_name',v_top_name,
    'top_wealth',coalesce(v_top_wealth,0),
    'is_self_top',v_current_id=v_top_id,
    'eligibility_threshold',v_min_wealth,
    'eligibility_rule','财富榜第1且统一灵石严格超过500万，由本人自愿上庄',
    'player_house_only_spirit_stone',v_dealer_id is not null,
    'player_house_pool_contribution_bps',0,
    'player_house_heaven_recovery_bps',0,
    'max_stake_spirit_dice',case when v_dealer_id is null then null else floor(v_dealer_wealth::numeric/greatest(v_destiny_odds,1))::bigint end,
    'max_stake_turtle_oracle',case when v_dealer_id is null then null else floor(v_dealer_wealth::numeric/3)::bigint end
  );
end;
$$;

create or replace function public.set_casino_player_house_v1(p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_current_id uuid;
  v_top_id uuid;
  v_top_wealth bigint:=0;
  v_enabled boolean:=false;
  v_min_wealth bigint:=5000000;
  v_state public.casino_player_house_state%rowtype;
  v_previous_dealer uuid;
  v_previous_wealth bigint:=0;
begin
  if p_active is null then
    raise exception 'CASINO_PLAYER_HOUSE_INVALID_ACTION';
  end if;

  perform public.casino_assert_enabled_v1();
  v_current_id:=public.casino_current_character_id_v1();
  perform pg_advisory_xact_lock(hashtextextended('casino-player-house-dealer',14301));

  insert into public.casino_player_house_state(singleton_id,is_active,last_reason)
  values(1,false,'state_recreated')
  on conflict(singleton_id) do nothing;

  select * into v_state
  from public.casino_player_house_state
  where singleton_id=1
  for update;

  select coalesce(s.player_house_enabled,false),coalesce(s.player_house_min_wealth,5000000)
  into v_enabled,v_min_wealth
  from public.casino_settings s
  where s.singleton_id=1;

  select x.character_id,x.wealth
  into v_top_id,v_top_wealth
  from public.casino_player_house_top_candidate_v1() x;

  if p_active then
    if not v_enabled then
      raise exception 'CASINO_PLAYER_HOUSE_DISABLED';
    end if;
    if v_current_id is distinct from v_top_id or coalesce(v_top_wealth,0)<=v_min_wealth then
      raise exception 'CASINO_PLAYER_HOUSE_NOT_ELIGIBLE';
    end if;

    if v_state.is_active and v_state.dealer_character_id=v_current_id then
      return public.get_casino_player_house_status_v1();
    end if;

    if v_state.is_active and v_state.dealer_character_id is not null then
      v_previous_dealer:=v_state.dealer_character_id;
      v_previous_wealth:=public.spirit_stone_balance_v0141(v_previous_dealer);
      insert into public.casino_player_house_events(
        action_code,dealer_character_id,actor_character_id,dealer_wealth,reason_code
      ) values(
        'auto_deactivate',v_previous_dealer,v_current_id,v_previous_wealth,'new_rank_one_activated'
      );
    end if;

    update public.casino_player_house_state
    set dealer_character_id=v_current_id,
        is_active=true,
        activated_at=now(),
        deactivated_at=null,
        last_reason='dealer_voluntary_activate',
        updated_at=now()
    where singleton_id=1;

    insert into public.casino_player_house_events(
      action_code,dealer_character_id,actor_character_id,dealer_wealth,reason_code
    ) values(
      'activate',v_current_id,v_current_id,v_top_wealth,'dealer_voluntary_activate'
    );
  else
    if not v_state.is_active or v_state.dealer_character_id is distinct from v_current_id then
      raise exception 'CASINO_PLAYER_HOUSE_NOT_CURRENT_DEALER';
    end if;

    update public.casino_player_house_state
    set dealer_character_id=null,
        is_active=false,
        deactivated_at=now(),
        last_reason='dealer_voluntary_deactivate',
        updated_at=now()
    where singleton_id=1;

    insert into public.casino_player_house_events(
      action_code,dealer_character_id,actor_character_id,dealer_wealth,reason_code
    ) values(
      'deactivate',v_current_id,v_current_id,public.spirit_stone_balance_v0141(v_current_id),'dealer_voluntary_deactivate'
    );
  end if;

  return public.get_casino_player_house_status_v1();
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. 玩家庄随机结果：完全复用FIX7A概率与实际净倍率
-- ---------------------------------------------------------------------------
create or replace function public.casino_player_house_draw_result_v1(
  p_game_code text,
  p_choice text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_roll integer;
  v_won boolean:=false;
  v_net_odds integer:=1;
  v_result_text text;
  v_payload jsonb;
  v_d1 integer;
  v_d2 integer;
  v_d3 integer;
  v_total integer;
  v_side_roll integer;
  v_kind_roll integer;
  v_face_roll integer;
  v_generation_attempt integer:=0;
  v_result_side text;
  v_side_name text;
  v_result_kind text;
  v_dice_rule jsonb;
  v_ordinary_net_odds integer:=3;
  v_destiny_net_odds integer:=34;
begin
  if p_game_code not in ('spirit_dice','turtle_oracle') then
    raise exception 'CASINO_INVALID_HOUSE_GAME';
  end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then
    raise exception 'CASINO_INVALID_CHOICE';
  end if;

  select coalesce(s.spirit_dice_ordinary_triple_net_odds,3),
         coalesce(s.spirit_dice_destiny_triple_net_odds,34)
  into v_ordinary_net_odds,v_destiny_net_odds
  from public.casino_settings s
  where s.singleton_id=1;

  if p_game_code='spirit_dice' then
    v_side_roll:=1+floor(random()*2)::integer;
    v_result_side:=case when v_side_roll=1 then 'small' else 'big' end;
    v_side_name:=case when v_result_side='small' then '小' else '大' end;

    v_kind_roll:=1+floor(random()*20000)::integer;
    v_result_kind:=case
      when v_kind_roll<=4 then 'destiny_triple'
      when v_kind_roll<=254 then 'ordinary_triple'
      else 'normal'
    end;

    if v_result_kind in ('ordinary_triple','destiny_triple') then
      v_face_roll:=1+floor(random()*3)::integer;
      v_d1:=case when v_result_side='small' then v_face_roll else v_face_roll+3 end;
      v_d2:=v_d1;
      v_d3:=v_d1;
    else
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
    v_won:=coalesce((v_dice_rule->>'won')::boolean,false);
    v_net_odds:=coalesce((v_dice_rule->>'net_odds')::integer,0);

    v_result_text:=format(
      '三枚灵骰显出【%s、%s、%s】，共%s点，归于【%s】。%s',
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

    v_payload:=jsonb_build_object(
      'dice',jsonb_build_array(v_d1,v_d2,v_d3),
      'total',v_total,
      'choice',p_choice,
      'result_side',v_result_side,
      'result_kind',v_result_kind,
      'is_triple',v_d1=v_d2 and v_d2=v_d3,
      'is_destiny_triple',v_result_kind='destiny_triple',
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
    v_result_text:=v_result_text||case when v_won then ' 你押中了。' else ' 此局与你所押不合。' end;
    v_payload:=jsonb_build_object(
      'roll',v_roll,
      'choice',p_choice,
      'result',case when v_roll<25 then 'auspicious' when v_roll<75 then 'neutral' else 'ominous' end
    );
  end if;

  return jsonb_build_object(
    'won',v_won,
    'net_odds',v_net_odds,
    'result_text',v_result_text,
    'result_payload',v_payload
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. 玩家庄即时结算
-- ---------------------------------------------------------------------------
create or replace function public.casino_play_player_house_v1(
  p_dealer_character_id uuid,
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
  v_bettor_id uuid;
  v_dealer_name text;
  v_bettor_balance bigint:=0;
  v_dealer_balance bigint:=0;
  v_dealer_balance_after bigint:=0;
  v_max_net_odds integer:=1;
  v_max_liability_numeric numeric:=0;
  v_max_liability bigint:=0;
  v_draw jsonb;
  v_won boolean:=false;
  v_net_odds integer:=0;
  v_profit_numeric numeric:=0;
  v_profit bigint:=0;
  v_reward bigint:=0;
  v_dealer_debit bigint:=0;
  v_dealer_credit bigint:=0;
  v_result_text text;
  v_result_payload jsonb;
  v_debit jsonb;
begin
  perform public.casino_assert_enabled_v1();

  if p_dealer_character_id is null then
    raise exception 'CASINO_PLAYER_HOUSE_DEALER_MISSING';
  end if;
  if p_game_code not in ('spirit_dice','turtle_oracle') then
    raise exception 'CASINO_INVALID_HOUSE_GAME';
  end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then
    raise exception 'CASINO_INVALID_CHOICE';
  end if;
  if p_stake_type<>'spirit_stone' then
    raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE';
  end if;
  if p_stake_amount is null or p_stake_amount<10 then
    raise exception 'CASINO_STAKE_BELOW_MINIMUM';
  end if;
  if p_stake_amount>9007199254740991 then
    raise exception 'CASINO_STAKE_TOO_LARGE';
  end if;

  v_bettor_id:=public.casino_current_character_id_v1();
  if v_bettor_id=p_dealer_character_id then
    raise exception 'CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN';
  end if;

  -- 统一按UUID文本顺序锁两侧唯一灵石账户，减少与其他资源写入发生锁顺序反转的风险。
  if v_bettor_id::text<p_dealer_character_id::text then
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bettor_id::text,141));
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_dealer_character_id::text,141));
  else
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_dealer_character_id::text,141));
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bettor_id::text,141));
  end if;

  perform public.spirit_stone_normalize_character_v0141(v_bettor_id);
  perform public.spirit_stone_normalize_character_v0141(p_dealer_character_id);

  v_bettor_balance:=public.spirit_stone_balance_v0141(v_bettor_id);
  v_dealer_balance:=public.spirit_stone_balance_v0141(p_dealer_character_id);
  select pc.name into v_dealer_name from public.player_characters pc where pc.id=p_dealer_character_id;

  v_max_net_odds:=case
    when p_game_code='spirit_dice' then coalesce((select s.spirit_dice_destiny_triple_net_odds from public.casino_settings s where s.singleton_id=1),34)
    else 3
  end;
  v_max_liability_numeric:=p_stake_amount::numeric*v_max_net_odds::numeric;
  if v_max_liability_numeric>9007199254740991::numeric then
    raise exception 'CASINO_STAKE_TOO_LARGE';
  end if;
  v_max_liability:=v_max_liability_numeric::bigint;

  if v_bettor_balance<p_stake_amount then
    raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES';
  end if;
  if v_dealer_balance<v_max_liability then
    raise exception 'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT';
  end if;

  perform public.casino_record_activity_v1(v_bettor_id,'house','spirit_stone');
  v_debit:=public.casino_debit_v1(v_bettor_id,'spirit_stone',p_stake_amount,'house',p_game_code);
  v_draw:=public.casino_player_house_draw_result_v1(p_game_code,p_choice);
  v_won:=coalesce((v_draw->>'won')::boolean,false);
  v_net_odds:=coalesce((v_draw->>'net_odds')::integer,0);
  v_result_payload:=coalesce(v_draw->'result_payload','{}'::jsonb);

  if v_won then
    v_profit_numeric:=p_stake_amount::numeric*v_net_odds::numeric;
    if v_profit_numeric>9007199254740991::numeric then
      raise exception 'CASINO_STAKE_TOO_LARGE';
    end if;
    v_profit:=v_profit_numeric::bigint;
    perform public.spirit_stone_debit_v0141(
      p_dealer_character_id,v_profit,'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT'
    );
    perform public.award_spirit_stones_v3(v_bettor_id,p_stake_amount+v_profit);
    v_reward:=p_stake_amount+v_profit;
    v_dealer_debit:=v_profit;
    v_dealer_credit:=0;
    v_result_text:=format(
      '玩家庄家【%s】开局：%s 本局押注%s枚灵石；本金%s枚原数返还，按实际净倍率%s倍赔付毛利润%s枚，玩家合计到账%s枚。庄家承担全部赔付，本局不抽成、不入造化池。',
      coalesce(v_dealer_name,'无名庄家'),v_draw->>'result_text',
      p_stake_amount,p_stake_amount,v_net_odds,v_profit,v_reward
    );
  else
    perform public.award_spirit_stones_v3(p_dealer_character_id,p_stake_amount);
    v_reward:=0;
    v_profit:=0;
    v_dealer_debit:=0;
    v_dealer_credit:=p_stake_amount;
    v_result_text:=format(
      '玩家庄家【%s】开局：%s 本局押注%s枚灵石全部归庄家；本局不抽成、不入造化池。',
      coalesce(v_dealer_name,'无名庄家'),v_draw->>'result_text',p_stake_amount
    );
  end if;

  v_dealer_balance_after:=public.spirit_stone_balance_v0141(p_dealer_character_id);
  v_result_payload:=v_result_payload||jsonb_build_object(
    'house_mode','player',
    'dealer_name',coalesce(v_dealer_name,'无名庄家'),
    'stake_type','spirit_stone',
    'net_odds',v_net_odds,
    'nominal_profit',v_profit,
    'nominal_reward',case when v_won then p_stake_amount+v_profit else 0 end,
    'actual_reward',v_reward,
    'pool_contribution',0,
    'pool_rate_bps',0,
    'heaven_recovery',0,
    'ticket_awarded',false,
    'dealer_debit_amount',v_dealer_debit,
    'dealer_credit_amount',v_dealer_credit,
    'dealer_balance_before',v_dealer_balance,
    'dealer_balance_after',v_dealer_balance_after,
    'max_liability_amount',v_max_liability,
    'settlement_rule','zero_fee_full_transfer'
  );

  insert into public.casino_house_games(
    character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,
    reward_amount,nominal_reward_amount,fee_amount,pool_contribution,heaven_recovery_amount,
    result_payload,result_text,house_mode,dealer_character_id,dealer_name_snapshot,
    dealer_debit_amount,dealer_credit_amount,max_liability_amount
  ) values(
    v_bettor_id,p_game_code,'spirit_stone',p_stake_amount,p_choice,
    case when v_won then 'win' else 'loss' end,
    v_reward,case when v_won then p_stake_amount+v_profit else 0 end,0,0,0,
    v_result_payload,v_result_text,'player',p_dealer_character_id,coalesce(v_dealer_name,'无名庄家'),
    v_dealer_debit,v_dealer_credit,v_max_liability
  );

  return jsonb_build_object(
    'won',v_won,
    'reward',v_reward,
    'nominal_reward',case when v_won then p_stake_amount+v_profit else 0 end,
    'nominal_profit',v_profit,
    'net_profit',case when v_won then v_profit else -p_stake_amount end,
    'fee',0,
    'pool_contribution',0,
    'heaven_recovery',0,
    'ticket_awarded',false,
    'house_mode','player',
    'dealer_name',coalesce(v_dealer_name,'无名庄家'),
    'dealer_debit_amount',v_dealer_debit,
    'dealer_credit_amount',v_dealer_credit,
    'max_liability_amount',v_max_liability,
    'result_text',v_result_text,
    'result_payload',v_result_payload,
    'drop',null
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. 保存原FIX7A系统庄RPC并建立安全分派入口
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.play_system_house_game_v0141_fix7a(text,text,bigint,text)') is null then
    if to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is null then
      raise exception 'PLAYER_HOUSE_FIX7A_ENTRY_MISSING';
    end if;
    alter function public.play_house_game_v1(text,text,bigint,text)
      rename to play_system_house_game_v0141_fix7a;
  end if;
end;
$$;

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
  v_dealer_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('casino-player-house-dealer',14301));
  v_dealer_id:=public.casino_player_house_resolve_dealer_v1();

  if v_dealer_id is null then
    return public.play_system_house_game_v0141_fix7a(
      p_game_code,p_stake_type,p_stake_amount,p_choice
    );
  end if;

  return public.casino_play_player_house_v1(
    v_dealer_id,p_game_code,p_stake_type,p_stake_amount,p_choice
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. 权限与注释
-- ---------------------------------------------------------------------------
revoke all on function public.casino_player_house_top_candidate_v1() from public,anon,authenticated;
revoke all on function public.casino_player_house_resolve_dealer_v1() from public,anon,authenticated;
revoke all on function public.casino_player_house_draw_result_v1(text,text) from public,anon,authenticated;
revoke all on function public.casino_play_player_house_v1(uuid,text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.play_system_house_game_v0141_fix7a(text,text,bigint,text) from public,anon,authenticated;

revoke all on function public.get_casino_player_house_status_v1() from public,anon,authenticated;
revoke all on function public.set_casino_player_house_v1(boolean) from public,anon,authenticated;
revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;

grant execute on function public.get_casino_player_house_status_v1() to authenticated;
grant execute on function public.set_casino_player_house_v1(boolean) to authenticated;
grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;

comment on table public.casino_player_house_state is
  'V0.14.4：财富榜第一且灵石严格超过500万的玩家可自愿接管大堂坐庄；仅保存当前选择状态。';
comment on table public.casino_player_house_events is
  'V0.14.4：玩家庄上庄、下庄与资格失效自动下庄审计。';
comment on function public.play_system_house_game_v0141_fix7a(text,text,bigint,text) is
  '原V0.14.1 FIX7A系统庄完整实现，仅由统一分派RPC内部调用。';
comment on function public.play_house_game_v1(text,text,bigint,text) is
  '统一大堂入口：有效玩家庄时执行零抽成全额对赌；否则完整调用原FIX7A系统庄。';
comment on function public.set_casino_player_house_v1(boolean) is
  '财富榜第一且统一灵石严格超过500万的当前角色可自愿上庄；当前玩家庄可主动下庄。';


-- ---------------------------------------------------------------------------
-- A1. 修为赌局永久锁定当前小境界：只能损失当前境界起始线以上的进度。
-- ---------------------------------------------------------------------------
create or replace function public.casino_current_stage_floor_v0144(p_character_id uuid)
returns bigint
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce(rs.cultivation_required,0)::bigint
  from public.player_characters pc
  join public.realm_stages rs on rs.id=pc.realm_stage_id
  where pc.id=p_character_id;
$$;

create or replace function public.casino_available_v1(p_character_id uuid,p_stake_type text)
returns bigint
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_amount bigint:=0;
  v_floor bigint:=0;
begin
  if p_stake_type='spirit_stone' then
    return public.spirit_stone_balance_v0141(p_character_id);
  elsif p_stake_type='cultivation' then
    select pc.cultivation,coalesce(rs.cultivation_required,0)
    into v_amount,v_floor
    from public.player_characters pc
    join public.realm_stages rs on rs.id=pc.realm_stage_id
    where pc.id=p_character_id;
    return greatest(0,coalesce(v_amount,0)-coalesce(v_floor,0));
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

create or replace function public.casino_debit_v1(
  p_character_id uuid,p_stake_type text,p_amount bigint,p_context text,p_game_code text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_balance bigint:=0;
  v_cultivation bigint:=0;
  v_floor bigint:=0;
  v_available bigint:=0;
  v_minimum bigint:=0;
  v_major_order smallint;
  v_stage_id smallint;
  v_stage_name text;
begin
  if p_amount is null or p_amount<=0 then raise exception 'CASINO_INVALID_STAKE_AMOUNT'; end if;
  if p_amount>9007199254740991 then raise exception 'CASINO_STAKE_TOO_LARGE'; end if;
  if p_context not in ('house','duel') then raise exception 'CASINO_INVALID_CONTEXT'; end if;

  if p_stake_type='spirit_stone' then
    if p_amount<10 then raise exception 'CASINO_STAKE_BELOW_MINIMUM'; end if;
    v_balance:=public.spirit_stone_balance_v0141(p_character_id);
    if v_balance<p_amount then raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES'; end if;
    perform public.spirit_stone_debit_v0141(p_character_id,p_amount,'CASINO_INSUFFICIENT_SPIRIT_STONES');
    return jsonb_build_object('stake_type',p_stake_type,'amount',p_amount,'available_before',v_balance,'available_after',v_balance-p_amount);
  elsif p_stake_type='cultivation' then
    select pc.cultivation,pc.realm_stage_id,rs.stage_name,r.major_order,coalesce(rs.cultivation_required,0)
    into v_cultivation,v_stage_id,v_stage_name,v_major_order,v_floor
    from public.player_characters pc
    join public.realm_stages rs on rs.id=pc.realm_stage_id
    join public.realms r on r.id=rs.realm_id
    where pc.id=p_character_id
    for update of pc;

    if v_stage_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
    if v_major_order<public.casino_nascent_major_order_v1() then raise exception 'CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL'; end if;

    v_available:=greatest(0,v_cultivation-v_floor);
    if v_available<=0 then raise exception 'CASINO_INSUFFICIENT_CULTIVATION'; end if;
    v_minimum:=least(50000,v_available);
    if p_amount<v_minimum then raise exception 'CULTIVATION_STAKE_MINIMUM'; end if;
    if p_amount>v_available then raise exception 'CASINO_INSUFFICIENT_CULTIVATION'; end if;

    update public.player_characters pc
    set cultivation=greatest(v_floor,pc.cultivation-p_amount),updated_at=now()
    where pc.id=p_character_id;

    return jsonb_build_object(
      'stake_type',p_stake_type,'amount',p_amount,
      'available_before',v_available,'available_after',v_available-p_amount,
      'cultivation_before',v_cultivation,'cultivation_after',greatest(v_floor,v_cultivation-p_amount),
      'stage_before_id',v_stage_id,'stage_before_name',v_stage_name,
      'stage_after_id',v_stage_id,'stage_after_name',v_stage_name,
      'major_order',v_major_order,'stage_floor',v_floor,'realm_locked',true
    );
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

create or replace function public.casino_realign_after_loss_v1(p_character_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_cultivation bigint;
  v_floor bigint;
  v_stage_id smallint;
  v_stage_name text;
begin
  select pc.cultivation,pc.realm_stage_id,rs.stage_name,coalesce(rs.cultivation_required,0)
  into v_cultivation,v_stage_id,v_stage_name,v_floor
  from public.player_characters pc
  join public.realm_stages rs on rs.id=pc.realm_stage_id
  where pc.id=p_character_id
  for update of pc;

  if v_stage_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  if v_cultivation<v_floor then
    update public.player_characters set cultivation=v_floor,updated_at=now() where id=p_character_id;
    v_cultivation:=v_floor;
  end if;

  return jsonb_build_object(
    'stage_changed',false,
    'stage_before_id',v_stage_id,'stage_before_name',v_stage_name,
    'stage_after_id',v_stage_id,'stage_after_name',v_stage_name,
    'cultivation_after',v_cultivation,'stage_floor',v_floor,'realm_locked',true
  );
end;
$$;

revoke all on function public.casino_current_stage_floor_v0144(uuid) from public,anon,authenticated;
revoke all on function public.casino_available_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.casino_debit_v1(uuid,text,bigint,text,text) from public,anon,authenticated;
revoke all on function public.casino_realign_after_loss_v1(uuid) from public,anon,authenticated;

create or replace function public.get_market_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;v_stones bigint:=0;v_cultivation_available bigint:=0;
  v_major_order smallint;v_stage_name text;v_activity jsonb:='{}'::jsonb;v_enabled boolean;
  v_cultivation_cap bigint;v_cultivation_full boolean:=false;
begin
  perform public.casino_process_v1();
  v_character_id:=public.casino_current_character_id_v1();
  perform public.spirit_stone_normalize_character_v0141(v_character_id);
  select s.enabled into v_enabled from public.casino_settings s where s.singleton_id=1;
  v_stones:=public.casino_available_v1(v_character_id,'spirit_stone');
  v_cultivation_available:=public.casino_available_v1(v_character_id,'cultivation');
  select r.major_order,rs.stage_name,public.character_cultivation_cap_v1(pc.realm_stage_id),public.character_cultivation_full_v1(pc.id)
  into v_major_order,v_stage_name,v_cultivation_cap,v_cultivation_full
  from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id join public.realms r on r.id=rs.realm_id
  where pc.id=v_character_id;
  select to_jsonb(a) into v_activity from public.casino_daily_activity a
  where a.character_id=v_character_id and a.activity_date=current_date;

  return jsonb_build_object(
    'status',case when v_enabled then 'active' else 'disabled' end,
    'settings',(select jsonb_build_object(
      'reveal_delay_seconds',0,'open_expiry_seconds',s.open_expiry_seconds,
      'draw_interval_seconds',s.draw_interval_seconds,'pool_hit_chance',s.pool_hit_chance,
      'stone_minimum',10,'cultivation_minimum',50000,'cultivation_all_in_below_minimum',true,'quick_multipliers',jsonb_build_array(1,5,10,50,100),
      'qualification_rule','one_per_character_per_round'
    ) from public.casino_settings s where s.singleton_id=1),
    'character',jsonb_build_object(
      'stage_name',v_stage_name,'major_order',v_major_order,
      'cultivation_eligible',v_major_order>=public.casino_nascent_major_order_v1() and v_cultivation_available>0,
      'cultivation_full',v_cultivation_full,'cultivation_cap',v_cultivation_cap,
      'spirit_stones',v_stones,'cultivation_available',v_cultivation_available,'cultivation_max_stake',v_cultivation_available
    ),
    'activity',coalesce(v_activity,jsonb_build_object('house_count',0,'duel_count',0,'cultivation_count',0,'total_count',0,'spirit_stone_ticket_count',0,'cultivation_ticket_count',0)),
    'pools',(select jsonb_object_agg(p.stake_type,jsonb_build_object(
      'amount',p.amount,'next_draw_at',p.next_draw_at,'seconds_remaining',greatest(0,extract(epoch from p.next_draw_at-now()))::integer,
      'ticket_count',(select count(*)::integer from public.casino_tickets t where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at),
      'last_prize',p.last_prize,'last_winner_name',winner.name,'last_draw_hit',p.last_draw_hit,
      'last_candidate_name',candidate.name,'last_ticket_count',p.last_ticket_count
    )) from public.casino_pools p
       left join public.player_characters winner on winner.id=p.last_winner_character_id
       left join public.player_characters candidate on candidate.id=p.last_candidate_character_id),
    'tickets',(select jsonb_object_agg(p.stake_type,coalesce(t.ticket_count,0))
      from public.casino_pools p left join public.casino_tickets t
      on t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at and t.character_id=v_character_id),
    'latest_draws',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'stake_type',d.stake_type,'prize_amount',d.prize_amount,'pool_amount',d.pool_amount,
        'did_hit',d.did_hit,'hit_chance',d.hit_chance,'winner_name',winner.name,'candidate_name',candidate.name,
        'ticket_count',d.ticket_count,'result_text',d.result_text,'created_at',d.created_at
      ) obj
      from public.casino_draws d
      left join public.player_characters winner on winner.id=d.winner_character_id
      left join public.player_characters candidate on candidate.id=d.candidate_character_id
      order by d.created_at desc limit 8
    ) x),
    'open_duels',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'id',d.id,'creator_name',pc.name,'game_code',d.game_code,'stake_type',d.stake_type,'stake_amount',d.stake_amount,
        'expires_in',greatest(0,extract(epoch from (d.created_at+make_interval(secs=>s.open_expiry_seconds))-now()))::integer
      ) obj
      from public.casino_duels d join public.player_characters pc on pc.id=d.creator_character_id
      cross join public.casino_settings s
      where d.status='open' and d.creator_character_id<>v_character_id
        and (d.stake_type<>'cultivation' or v_cultivation_available>=d.stake_amount)
      order by d.created_at desc limit 30
    ) x),
    'my_duels',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'id',d.id,'game_code',d.game_code,'status',d.status,
        'status_name',case d.status when 'open' then '等待应局' when 'sealed' then '立即结算中' when 'settled' then '胜负已分' when 'draw' then '流局' when 'cancelled' then '已取消' else d.status end,
        'stake_type',d.stake_type,'stake_amount',d.stake_amount,'fee_amount',d.fee_amount,'prize_amount',d.prize_amount,'pool_contribution',d.pool_contribution,
        'seconds_remaining',case when d.reveal_at is null then 0 else greatest(0,extract(epoch from d.reveal_at-now()))::integer end,
        'result_text',d.result_text,
        'opponent_name',coalesce(case when d.creator_character_id=v_character_id then op.name else cr.name end,'等待道友'),
        'outcome',case when d.status='draw' then 'draw' when d.status='settled' and d.winner_character_id=v_character_id then 'win' when d.status='settled' then 'loss' else d.status end,
        'my_choice',public.casino_choice_name_v1(d.game_code,case when d.creator_character_id=v_character_id then d.creator_choice else d.opponent_choice end),
        'opponent_choice',case when d.status in ('settled','draw') then public.casino_choice_name_v1(d.game_code,case when d.creator_character_id=v_character_id then d.opponent_choice else d.creator_choice end) end,
        'can_cancel',d.status='open' and d.creator_character_id=v_character_id
      ) obj
      from public.casino_duels d
      join public.player_characters cr on cr.id=d.creator_character_id
      left join public.player_characters op on op.id=d.opponent_character_id
      where v_character_id in (d.creator_character_id,d.opponent_character_id)
      order by d.created_at desc limit 20
    ) x)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- A2. 贵宾赌契有人应局后立即开奖结算，不再等待五分钟。
-- 旧版本把揭晓延迟限制在60-3600秒，本版先放宽约束再归零。
-- ---------------------------------------------------------------------------
alter table public.casino_settings
  drop constraint if exists casino_settings_reveal_delay_seconds_check;
alter table public.casino_settings
  add constraint casino_settings_reveal_delay_seconds_check
  check (reveal_delay_seconds between 0 and 3600);

update public.casino_settings
set reveal_delay_seconds=0,updated_at=now()
where singleton_id=1;

create or replace function public.create_duel_v1(p_game_code text,p_stake_type text,p_stake_amount bigint,p_choice text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;
  v_duel_id uuid;
begin
  perform public.casino_assert_enabled_v1();
  perform public.casino_process_v1();
  if p_game_code not in ('spirit_fist','five_elements') then raise exception 'CASINO_INVALID_DUEL_GAME'; end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE'; end if;
  v_character_id:=public.casino_current_character_id_v1();
  perform pg_advisory_xact_lock(hashtextextended('casino:'||v_character_id::text,120));
  if exists(select 1 from public.casino_duels d where d.status in ('open','sealed') and v_character_id in(d.creator_character_id,d.opponent_character_id)) then
    raise exception 'CASINO_ACTIVE_DUEL_EXISTS';
  end if;
  perform public.casino_record_activity_v1(v_character_id,'duel',p_stake_type);
  perform public.casino_debit_v1(v_character_id,p_stake_type,p_stake_amount,'duel',p_game_code);
  insert into public.casino_duels(creator_character_id,game_code,stake_type,stake_amount,creator_choice,status)
  values(v_character_id,p_game_code,p_stake_type,p_stake_amount,p_choice,'open') returning id into v_duel_id;
  return jsonb_build_object('success',true,'duel_id',v_duel_id,'content','招式已封入无相阵盘。三十分钟内若无人应局，赌契将自行散去并原数返还；一旦有人应局，立即开契结算。');
end;
$$;

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
        '应局即开契，无相阵盘同时显出【%s】。双方同招，此局流局，赌注原数奉还；没有实际亏损，因此不进入造化池。',
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
        '应局即开契：%s施展【%s】，%s施展【%s】。%s胜出；其自身本金%s%s原数返还，并取得败者赌注中的%s%s，合计到账%s%s。败者损失%s%s，剩余%s%s进入全服造化池。二人均已纳入本期等权候选名录。%s',
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
          else case when d.stake_type='cultivation' then ' 败者仅损失当前小境界内修为进度，大小境界均保持不变。' else '' end
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


create or replace function public.join_duel_v1(p_duel_id uuid,p_choice text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;
  d public.casino_duels%rowtype;
  v_outcome text;
begin
  perform public.casino_assert_enabled_v1();
  perform public.casino_process_v1();
  v_character_id:=public.casino_current_character_id_v1();
  perform pg_advisory_xact_lock(hashtextextended('casino:'||v_character_id::text,120));

  select * into d from public.casino_duels x where x.id=p_duel_id for update;
  if d.id is null or d.status<>'open' then raise exception 'DUEL_NOT_AVAILABLE'; end if;
  if d.creator_character_id=v_character_id then raise exception 'DUEL_OWN_TABLE'; end if;
  if not public.casino_validate_choice_v1(d.game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE'; end if;
  if exists(select 1 from public.casino_duels x where x.id<>p_duel_id and x.status in('open','sealed') and v_character_id in(x.creator_character_id,x.opponent_character_id)) then
    raise exception 'CASINO_ACTIVE_DUEL_EXISTS';
  end if;

  perform public.casino_record_activity_v1(v_character_id,'duel',d.stake_type);
  perform public.casino_debit_v1(v_character_id,d.stake_type,d.stake_amount,'duel',d.game_code);

  update public.casino_duels x
  set opponent_character_id=v_character_id,
      opponent_choice=p_choice,
      status='sealed',
      reveal_at=now(),
      updated_at=now()
  where x.id=d.id and x.status='open';

  if not found then raise exception 'DUEL_NOT_AVAILABLE'; end if;

  perform public.casino_settle_duels_v1();
  select * into d from public.casino_duels x where x.id=p_duel_id;

  v_outcome:=case
    when d.status='draw' then 'draw'
    when d.status='settled' and d.winner_character_id=v_character_id then 'win'
    when d.status='settled' then 'loss'
    else 'pending'
  end;

  return jsonb_build_object(
    'success',d.status in('settled','draw'),
    'status',d.status,
    'outcome',v_outcome,
    'winner_character_id',d.winner_character_id,
    'prize_amount',d.prize_amount,
    'pool_contribution',d.pool_contribution,
    'result_text',d.result_text,
    'content',coalesce(d.result_text,'应局成功，赌契正在立即结算。')
  );
end;
$$;

revoke all on function public.create_duel_v1(text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.join_duel_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.casino_settle_duels_v1() from public,anon,authenticated;
grant execute on function public.create_duel_v1(text,text,bigint,text) to authenticated;
grant execute on function public.join_duel_v1(uuid,text) to authenticated;


-- ---------------------------------------------------------------------------
-- A3. 每丝天劫感悟：突破率继续+5个百分点，并额外提供总修炼速度+10%。
-- ---------------------------------------------------------------------------
create or replace function public.heavenly_insight_cultivation_multiplier_v0144(p_character_id uuid)
returns numeric
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select round(1 + coalesce(bs.heavenly_insight_count,0)::numeric * 0.10, 6)
  from (select 1) seed
  left join public.character_breakthrough_states bs on bs.character_id=p_character_id;
$$;

revoke all on function public.heavenly_insight_cultivation_multiplier_v0144(uuid) from public,anon,authenticated;

create or replace function public.claim_cultivation_v1()
returns table (
  character_id uuid,
  gained bigint,
  cultivation_total bigint,
  elapsed_seconds bigint,
  current_rate_per_second numeric,
  base_rate_per_second numeric,
  root_multiplier numeric,
  qi_multiplier numeric,
  fate_bonus numeric,
  technique_flat_rate numeric,
  technique_multiplier_bonus numeric,
  effect_flat_rate numeric,
  effect_multiplier_bonus numeric,
  claimed_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_character_id uuid;
  v_world_id uuid;
  v_realm_stage_id smallint;
  v_age integer;
  v_player_realm_order integer := 0;
  v_mainstream_realm_order integer := 0;
  v_realm_gap integer := 0;
  v_heaven_coefficient numeric := 1;
  v_cultivation_before bigint;
  v_base_rate numeric := 0;
  v_root_multiplier numeric := 1;
  v_qi_base numeric := 1;
  v_effective_qi_multiplier numeric := 1;
  v_fate_bonus numeric := 0;
  v_technique_flat numeric := 0;
  v_technique_multiplier numeric := 0;
  v_effect_flat numeric := 0;
  v_effect_multiplier numeric := 0;
  v_last_claim timestamptz;
  v_now timestamptz := clock_timestamp();
  v_cursor timestamptz;
  v_boundary timestamptz;
  v_segment_seconds numeric;
  v_segment_effect_flat numeric;
  v_segment_effect_multiplier numeric;
  v_segment_fixed_rate numeric;
  v_segment_rate numeric;
  v_exact_gain numeric := 0;
  v_fraction numeric := 0;
  v_gained bigint := 0;
  v_elapsed bigint := 0;
  v_current_fixed_rate numeric := 0;
  v_current_rate numeric := 0;
  v_cultivation_cap bigint;
  v_requested_gain bigint := 0;
  v_discarded_gain bigint := 0;
  v_insight_multiplier numeric := 1;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select
    pc.id, pc.world_id, pc.realm_stage_id, pc.age, pc.cultivation,
    r.major_order, cs.last_claim_at, cs.fractional_remainder
  into
    v_character_id, v_world_id, v_realm_stage_id, v_age, v_cultivation_before,
    v_player_realm_order, v_last_claim, v_fraction
  from public.player_characters pc
  join public.character_cultivation_state cs on cs.character_id = pc.id
  join public.realm_stages rs on rs.id = pc.realm_stage_id
  join public.realms r on r.id = rs.realm_id
  where pc.user_id = v_user_id
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1
  for update of pc, cs;

  if v_character_id is null then
    raise exception 'NO_ACTIVE_CHARACTER';
  end if;

  v_insight_multiplier := public.heavenly_insight_cultivation_multiplier_v0144(v_character_id);

  v_base_rate := coalesce(public.realm_base_cultivation_rate_v1(v_realm_stage_id), 10);
  v_last_claim := least(coalesce(v_last_claim, v_now), v_now);
  v_elapsed := greatest(0, floor(extract(epoch from (v_now - v_last_claim)))::bigint);

  select coalesce(sr.cultivation_multiplier, 1.000000)
  into v_root_multiplier
  from public.character_spirit_roots csr
  join public.spirit_roots sr on sr.id = csr.spirit_root_id
  where csr.character_id = v_character_id and csr.is_primary
  limit 1;
  v_root_multiplier := coalesce(v_root_multiplier, 1.000000);

  select coalesce(gw.spiritual_qi_level, 1.000000)
  into v_qi_base
  from public.game_worlds gw
  where gw.id = v_world_id;
  v_qi_base := coalesce(v_qi_base, 1.000000);

  select coalesce(round(avg(r.major_order))::integer, v_player_realm_order)
  into v_mainstream_realm_order
  from public.player_characters pc
  join public.realm_stages rs on rs.id = pc.realm_stage_id
  join public.realms r on r.id = rs.realm_id
  where pc.world_id = v_world_id
    and pc.status in ('active','secluded','missing');

  v_mainstream_realm_order := coalesce(v_mainstream_realm_order, v_player_realm_order);
  v_realm_gap := coalesce(v_player_realm_order, 0) - coalesce(v_mainstream_realm_order, 0);
  v_heaven_coefficient := public.heaven_balance_multiplier_v1(v_realm_gap);
  v_effective_qi_multiplier := greatest(0, v_qi_base * v_heaven_coefficient);

  select coalesce(sum(
    case
      when f.code = 'late_bloomer' then
        case
          when v_age >= coalesce((f.trigger_rules->>'late_age')::integer, 60)
            then coalesce((f.modifiers->>'late_cultivation')::numeric, 0)
          else coalesce((f.modifiers->>'early_cultivation')::numeric, 0)
        end
      else coalesce((f.modifiers->>'cultivation')::numeric, 0)
    end
  ), 0)
  into v_fate_bonus
  from public.character_fates cf
  join public.fates f on f.id = cf.fate_id
  where cf.character_id = v_character_id and cf.is_active;

  select
    coalesce(sum(coalesce((t.fixed_effects->>'cultivation_per_second')::numeric, 0) * ct.level), 0),
    coalesce(sum(greatest(coalesce((t.fixed_effects->>'cultivation_multiplier')::numeric, 1) - 1, 0)), 0)
  into v_technique_flat, v_technique_multiplier
  from public.character_techniques ct
  join public.techniques t on t.id = ct.technique_id
  where ct.character_id = v_character_id
    and ct.is_equipped
    and t.is_active;

  v_exact_gain := coalesce(v_fraction, 0);
  v_cursor := v_last_claim;

  for v_boundary in
    select boundary_at
    from (
      select v_now as boundary_at
      union
      select greatest(e.starts_at, v_last_claim)
      from public.character_cultivation_effects e
      where e.character_id = v_character_id and e.is_active
        and e.starts_at > v_last_claim and e.starts_at < v_now
      union
      select least(e.expires_at, v_now)
      from public.character_cultivation_effects e
      where e.character_id = v_character_id and e.is_active
        and e.expires_at is not null
        and e.expires_at > v_last_claim and e.expires_at < v_now
    ) boundaries
    where boundary_at > v_last_claim
    order by boundary_at
  loop
    if v_boundary <= v_cursor then continue; end if;

    select coalesce(sum(e.flat_rate_per_second), 0), coalesce(sum(e.multiplier_bonus), 0)
    into v_segment_effect_flat, v_segment_effect_multiplier
    from public.character_cultivation_effects e
    where e.character_id = v_character_id and e.is_active
      and e.starts_at <= v_cursor
      and (e.expires_at is null or e.expires_at > v_cursor);

    v_segment_seconds := greatest(0, extract(epoch from (v_boundary - v_cursor)));
    v_segment_fixed_rate := greatest(
      0,
      (v_base_rate + v_technique_flat + v_segment_effect_flat)
      * v_root_multiplier
      * greatest(0, 1 + v_fate_bonus + v_technique_multiplier + v_segment_effect_multiplier)
    );

    -- 天道动态系数是最后一层，对前面完整结果整体相乘。
    v_segment_rate := greatest(0, v_segment_fixed_rate * v_effective_qi_multiplier * v_insight_multiplier);
    v_exact_gain := v_exact_gain + (v_segment_rate * v_segment_seconds);
    v_cursor := v_boundary;
  end loop;

  v_requested_gain := floor(v_exact_gain)::bigint;
  v_gained := v_requested_gain;
  v_fraction := v_exact_gain - v_requested_gain;
  v_cultivation_cap := public.character_cultivation_cap_v1(v_realm_stage_id);
  if v_cultivation_cap is not null then
    v_gained := least(v_requested_gain, greatest(0, v_cultivation_cap - v_cultivation_before));
    v_discarded_gain := greatest(0, v_requested_gain - v_gained);
    if v_discarded_gain > 0 or v_cultivation_before >= v_cultivation_cap then
      -- 圆满后的超额修为与小数余量直接舍弃，不能带入下一境界。
      v_fraction := 0;
    end if;
  end if;

  select coalesce(sum(e.flat_rate_per_second), 0), coalesce(sum(e.multiplier_bonus), 0)
  into v_effect_flat, v_effect_multiplier
  from public.character_cultivation_effects e
  where e.character_id = v_character_id and e.is_active
    and e.starts_at <= v_now
    and (e.expires_at is null or e.expires_at > v_now);

  v_current_fixed_rate := greatest(
    0,
    (v_base_rate + v_technique_flat + v_effect_flat)
    * v_root_multiplier
    * greatest(0, 1 + v_fate_bonus + v_technique_multiplier + v_effect_multiplier)
  );
  v_current_rate := greatest(0, v_current_fixed_rate * v_effective_qi_multiplier * v_insight_multiplier);
  if v_cultivation_cap is not null and v_cultivation_before + v_gained >= v_cultivation_cap then
    v_current_rate := 0;
  end if;

  if v_gained > 0 then
    update public.player_characters
    set cultivation = cultivation + v_gained, updated_at = now()
    where id = v_character_id;
  end if;

  update public.character_cultivation_state as ccs
  set base_rate_per_second = v_base_rate,
      last_claim_at = v_now,
      fractional_remainder = v_fraction,
      total_cultivation_seconds = ccs.total_cultivation_seconds + v_elapsed,
      updated_at = now()
  where ccs.character_id = v_character_id;

  if v_gained > 0 and v_elapsed >= 300 then
    insert into public.cultivation_records (
      character_id, world_year, action_type, years_spent,
      cultivation_before, cultivation_delta, cultivation_after,
      result, calculation_snapshot
    )
    select
      v_character_id, gw.current_year, 'cultivate', 0,
      v_cultivation_before, v_gained, v_cultivation_before + v_gained,
      'success',
      jsonb_build_object(
        'mode', 'automatic_v0144_insight_total_multiplier',
        'elapsed_seconds', v_elapsed,
        'realm_base_rate', v_base_rate,
        'rate_before_heaven', v_current_fixed_rate,
        'rate_per_second', v_current_rate,
        'root_multiplier', v_root_multiplier,
        'world_qi_base', v_qi_base,
        'heaven_balance_coefficient', v_heaven_coefficient,
        'effective_qi_multiplier', v_effective_qi_multiplier,
        'heavenly_insight_multiplier', v_insight_multiplier,
        'fate_bonus', v_fate_bonus,
        'technique_flat_rate', v_technique_flat,
        'technique_multiplier_bonus', v_technique_multiplier,
        'effect_flat_rate', v_effect_flat,
        'effect_multiplier_bonus', v_effect_multiplier,
        'cultivation_cap', v_cultivation_cap,
        'requested_gain', v_requested_gain,
        'discarded_gain', v_discarded_gain,
        'cap_rule', 'v0130_hard_cap'
      )
    from public.game_worlds gw where gw.id = v_world_id;
  end if;

  return query select
    v_character_id, v_gained, v_cultivation_before + v_gained, v_elapsed,
    round(v_current_rate, 6), round(v_base_rate, 6), round(v_root_multiplier, 6),
    round(v_effective_qi_multiplier, 6), round(v_fate_bonus, 6),
    round(v_technique_flat, 6), round(v_technique_multiplier, 6),
    round(v_effect_flat, 6), round(v_effect_multiplier, 6), v_now;
end;
$$;


revoke all on function public.claim_cultivation_v1() from public,anon;
grant execute on function public.claim_cultivation_v1() to authenticated;


-- ---------------------------------------------------------------------------
-- A4. 指定玩家一次性私人天道赏罚公告。
-- ---------------------------------------------------------------------------
create table if not exists public.player_divine_notices (
  id uuid primary key default gen_random_uuid(),
  target_user_id uuid not null references auth.users(id) on delete cascade,
  target_character_id uuid references public.player_characters(id) on delete set null,
  target_character_name text not null,
  notice_type text not null check(notice_type in('reward','compensation','punishment')),
  title text not null,
  content text not null,
  reason text,
  resource_code text not null default 'spirit_stone',
  amount_delta bigint not null,
  balance_before bigint not null,
  balance_after bigint not null,
  source_type text not null,
  source_record_id text not null,
  status text not null default 'pending' check(status in('pending','displayed','acknowledged')),
  displayed_at timestamptz,
  display_session_id text,
  acknowledged_at timestamptz,
  created_at timestamptz not null default now(),
  unique(source_type,source_record_id)
);

create index if not exists player_divine_notices_target_pending_idx
  on public.player_divine_notices(target_user_id,status,created_at,id);

alter table public.player_divine_notices enable row level security;
revoke all on table public.player_divine_notices from public,anon,authenticated;

create or replace function public.enqueue_divine_notice_v0144(
  p_target_user_id uuid,
  p_target_character_id uuid,
  p_target_character_name text,
  p_notice_type text,
  p_title text,
  p_content text,
  p_reason text,
  p_amount_delta bigint,
  p_balance_before bigint,
  p_balance_after bigint,
  p_source_type text,
  p_source_record_id text
)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_id uuid;
  v_type text:=lower(trim(coalesce(p_notice_type,'')));
begin
  if p_target_user_id is null or p_target_character_id is null then raise exception 'DIVINE_NOTICE_TARGET_REQUIRED'; end if;
  if v_type not in('reward','compensation','punishment') then raise exception 'DIVINE_NOTICE_TYPE_INVALID'; end if;
  if nullif(trim(coalesce(p_source_type,'')),'') is null or nullif(trim(coalesce(p_source_record_id,'')),'') is null then
    raise exception 'DIVINE_NOTICE_SOURCE_REQUIRED';
  end if;

  insert into public.player_divine_notices(
    target_user_id,target_character_id,target_character_name,notice_type,title,content,reason,
    amount_delta,balance_before,balance_after,source_type,source_record_id
  ) values(
    p_target_user_id,p_target_character_id,coalesce(nullif(trim(p_target_character_name),''),'无名修士'),v_type,
    coalesce(nullif(trim(p_title),''),'天道谕令'),coalesce(nullif(trim(p_content),''),'天意已定。'),nullif(trim(coalesce(p_reason,'')),''),
    coalesce(p_amount_delta,0),coalesce(p_balance_before,0),coalesce(p_balance_after,0),trim(p_source_type),trim(p_source_record_id)
  )
  on conflict(source_type,source_record_id) do update
    set source_record_id=excluded.source_record_id
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function public.claim_next_divine_notice_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_notice public.player_divine_notices%rowtype;
  v_headers jsonb:=coalesce(nullif(current_setting('request.headers',true),''),'{}')::jsonb;
  v_session text;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  v_session:=coalesce(v_headers->>'x-game-session-id','unknown');
  perform pg_advisory_xact_lock(hashtextextended('divine-notice:'||v_user_id::text,14401));

  select * into v_notice
  from public.player_divine_notices n
  where n.target_user_id=v_user_id and n.status='pending'
  order by n.created_at,n.id
  limit 1
  for update skip locked;

  if v_notice.id is null then return '{}'::jsonb; end if;

  update public.player_divine_notices
  set status='displayed',displayed_at=now(),display_session_id=v_session
  where id=v_notice.id and status='pending';

  if not found then return '{}'::jsonb; end if;

  return jsonb_build_object(
    'id',v_notice.id,
    'notice_type',v_notice.notice_type,
    'title',v_notice.title,
    'content',v_notice.content,
    'reason',v_notice.reason,
    'resource_code',v_notice.resource_code,
    'amount_delta',v_notice.amount_delta,
    'balance_before',v_notice.balance_before,
    'balance_after',v_notice.balance_after,
    'created_at',v_notice.created_at
  );
end;
$$;

create or replace function public.acknowledge_divine_notice_v1(p_notice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_notice public.player_divine_notices%rowtype;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_notice
  from public.player_divine_notices n
  where n.id=p_notice_id and n.target_user_id=v_user_id
  for update;
  if v_notice.id is null then raise exception 'DIVINE_NOTICE_NOT_FOUND'; end if;

  update public.player_divine_notices
  set status='acknowledged',acknowledged_at=coalesce(acknowledged_at,now())
  where id=v_notice.id;

  return jsonb_build_object('success',true,'notice_id',v_notice.id,'status','acknowledged');
end;
$$;

revoke all on function public.enqueue_divine_notice_v0144(uuid,uuid,text,text,text,text,text,bigint,bigint,bigint,text,text) from public,anon,authenticated;
revoke all on function public.claim_next_divine_notice_v1() from public,anon,authenticated;
revoke all on function public.acknowledge_divine_notice_v1(uuid) from public,anon,authenticated;
grant execute on function public.claim_next_divine_notice_v1() to authenticated;
grant execute on function public.acknowledge_divine_notice_v1(uuid) to authenticated;


-- ---------------------------------------------------------------------------
-- 发布控制与自检。
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.app_release_control') is not null then
    update public.app_release_control
    set release_name='V0.14.4 CACHE8',cache_epoch=greatest(cache_epoch,8),updated_at=now()
    where singleton_id=1;
  end if;
end;
$$;

comment on function public.casino_current_stage_floor_v0144(uuid) is 'V0.14.4：赌场修为保底线固定为当前小境界起始修为。';
comment on function public.join_duel_v1(uuid,text) is 'V0.14.4：应局后在同一事务中立即开奖结算。';
comment on function public.heavenly_insight_cultivation_multiplier_v0144(uuid) is 'V0.14.4：每丝天劫感悟使最终总修炼速度增加10%。';
comment on table public.player_divine_notices is 'V0.14.4：管理员赏罚等指定玩家私人一次性天道公告。';

commit;
notify pgrst,'reload schema';

select * from (
  values
    ('player_house_rpc',to_regprocedure('public.get_casino_player_house_status_v1()') is not null),
    ('player_house_dispatch',to_regprocedure('public.play_system_house_game_v0141_fix7a(text,text,bigint,text)') is not null),
    ('stage_floor_rpc',to_regprocedure('public.casino_current_stage_floor_v0144(uuid)') is not null),
    ('cultivation_all_in',position('v_minimum:=least(50000,v_available)' in pg_get_functiondef(to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)')))>0),
    ('realm_stage_unchanged',position('set realm_stage_id' in lower(pg_get_functiondef(to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)'))))=0),
    ('duel_reveal_zero',(select reveal_delay_seconds=0 from public.casino_settings where singleton_id=1)),
    ('duel_immediate',position('perform public.casino_settle_duels_v1()' in pg_get_functiondef(to_regprocedure('public.join_duel_v1(uuid,text)')))>0),
    ('insight_multiplier_rpc',to_regprocedure('public.heavenly_insight_cultivation_multiplier_v0144(uuid)') is not null),
    ('claim_uses_insight',position('v_insight_multiplier' in pg_get_functiondef(to_regprocedure('public.claim_cultivation_v1()')))>0),
    ('notice_table',to_regclass('public.player_divine_notices') is not null),
    ('notice_claim_rpc',to_regprocedure('public.claim_next_divine_notice_v1()') is not null),
    ('notice_ack_rpc',to_regprocedure('public.acknowledge_divine_notice_v1(uuid)') is not null),
    ('fix7a_odds',(select spirit_dice_ordinary_triple_denominator=80 and spirit_dice_destiny_triple_result_denominator=5000 and spirit_dice_ordinary_triple_net_odds=3 and spirit_dice_destiny_triple_net_odds=34 from public.casino_settings where singleton_id=1))
) as checks(check_name,ok);
