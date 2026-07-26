-- 《九霄问道》Web Alpha V0.14.0 FIX2
-- 修复1：避开数据库中可能已存在的 public.world_events / public.world_event_settings 同名旧表。
-- 修复2：为 world_event_publish_v0140 的直接调用补充显式类型转换，避免 PostgreSQL 将事件等级字面量推断为 integer 而无法匹配 smallint 参数。
-- 本脚本使用 public.jiuxiao_world_events 与 public.jiuxiao_world_event_settings，绝不删除或改写旧表。
-- 市坊门户与九霄界闻。
--
-- 目标：
-- 1. 新增全服只读“九霄界闻”。
-- 2. 由数据库在突破、天品/仙品/专属机缘、赌坊胜负和造化池开奖后自动写入播报。
-- 3. 提供未来管理后台调用的“天道抹杀”服务端接口。
-- 4. 广播失败不得影响核心结算；所有触发器均采用故障隔离。
--
-- 前置：V0.13.0数据库迁移已完成，V0.12.0 FIX1赌场已存在。

begin;

create extension if not exists pgcrypto;

create table if not exists public.jiuxiao_world_event_settings (
  singleton_id smallint primary key default 1 check (singleton_id = 1),
  enabled boolean not null default true,
  breakthrough_enabled boolean not null default true,
  opportunity_enabled boolean not null default true,
  casino_enabled boolean not null default true,
  admin_enabled boolean not null default true,
  retention_days integer not null default 30 check (retention_days between 1 and 3650),
  max_feed_rows integer not null default 50 check (max_feed_rows between 10 and 200),
  updated_at timestamptz not null default now()
);
insert into public.jiuxiao_world_event_settings(singleton_id)
values (1)
on conflict (singleton_id) do nothing;

create table if not exists public.jiuxiao_world_events (
  id uuid primary key default gen_random_uuid(),
  world_id uuid references public.game_worlds(id) on delete set null,
  world_year integer,
  event_type text not null,
  event_level smallint not null default 1 check (event_level between 1 and 4),
  actor_character_id uuid references public.player_characters(id) on delete set null,
  actor_name_snapshot text not null default '无名修士',
  title text not null,
  content text not null,
  source_table text not null,
  source_key text not null,
  metadata jsonb not null default '{}'::jsonb,
  is_public boolean not null default true,
  is_pinned boolean not null default false,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  constraint jiuxiao_world_events_source_unique unique (source_table, source_key, event_type)
);

create index if not exists jiuxiao_world_events_public_feed_idx
  on public.jiuxiao_world_events(is_public, is_pinned desc, created_at desc);
create index if not exists jiuxiao_world_events_actor_idx
  on public.jiuxiao_world_events(actor_character_id, created_at desc);
create index if not exists jiuxiao_world_events_type_idx
  on public.jiuxiao_world_events(event_type, created_at desc);

alter table public.jiuxiao_world_event_settings enable row level security;
alter table public.jiuxiao_world_events enable row level security;
revoke all on table public.jiuxiao_world_event_settings from public, anon, authenticated;
revoke all on table public.jiuxiao_world_events from public, anon, authenticated;

create or replace function public.world_event_publish_v0140(
  p_world_id uuid,
  p_world_year integer,
  p_event_type text,
  p_event_level smallint,
  p_actor_character_id uuid,
  p_actor_name_snapshot text,
  p_title text,
  p_content text,
  p_source_table text,
  p_source_key text,
  p_metadata jsonb default '{}'::jsonb,
  p_is_pinned boolean default false,
  p_expires_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_enabled boolean := true;
  v_retention_days integer := 30;
  v_id uuid;
begin
  select s.enabled, s.retention_days
    into v_enabled, v_retention_days
  from public.jiuxiao_world_event_settings s
  where s.singleton_id = 1;

  if not coalesce(v_enabled, true) then return null; end if;
  if nullif(btrim(coalesce(p_title, '')), '') is null then return null; end if;
  if nullif(btrim(coalesce(p_content, '')), '') is null then return null; end if;
  if nullif(btrim(coalesce(p_source_key, '')), '') is null then return null; end if;

  insert into public.jiuxiao_world_events(
    world_id, world_year, event_type, event_level,
    actor_character_id, actor_name_snapshot, title, content,
    source_table, source_key, metadata, is_public, is_pinned, expires_at
  ) values (
    p_world_id, p_world_year, left(coalesce(p_event_type, 'system_notice'), 80), greatest(1, least(4, coalesce(p_event_level, 1))),
    p_actor_character_id, left(coalesce(nullif(btrim(p_actor_name_snapshot), ''), '无名修士'), 80),
    left(p_title, 80), left(p_content, 1200),
    left(coalesce(p_source_table, 'unknown'), 80), left(p_source_key, 160), coalesce(p_metadata, '{}'::jsonb),
    true, coalesce(p_is_pinned, false),
    coalesce(p_expires_at, now() + make_interval(days => greatest(1, coalesce(v_retention_days, 30))))
  )
  on conflict (source_table, source_key, event_type) do nothing
  returning id into v_id;

  return v_id;
end;
$$;
revoke all on function public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamptz) from public, anon, authenticated;

create or replace function public.get_world_events_v1(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_character_id uuid;
  v_world_id uuid;
  v_limit integer;
  v_enabled boolean := true;
  v_max integer := 50;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;

  select pc.id, pc.world_id
    into v_character_id, v_world_id
  from public.player_characters pc
  where pc.user_id = v_user_id
    and pc.status in ('active', 'secluded', 'missing')
  order by pc.created_at desc
  limit 1;

  if v_character_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;

  select s.enabled, s.max_feed_rows
    into v_enabled, v_max
  from public.jiuxiao_world_event_settings s
  where s.singleton_id = 1;

  v_limit := greatest(1, least(coalesce(v_max, 50), coalesce(p_limit, 20)));

  return jsonb_build_object(
    'status', case when coalesce(v_enabled, true) then 'active' else 'disabled' end,
    'title', '九霄界闻',
    'subtitle', '天道传音',
    'entries', coalesce((
      select jsonb_agg(x.obj order by x.is_pinned desc, x.created_at desc)
      from (
        select e.is_pinned, e.created_at,
          jsonb_build_object(
            'id', e.id,
            'event_type', e.event_type,
            'event_level', e.event_level,
            'actor_name', e.actor_name_snapshot,
            'title', e.title,
            'content', e.content,
            'world_year', e.world_year,
            'is_pinned', e.is_pinned,
            'created_at', e.created_at,
            'seconds_ago', greatest(0, floor(extract(epoch from (now() - e.created_at)))::bigint)
          ) obj
        from public.jiuxiao_world_events e
        where e.is_public
          and (e.world_id is null or e.world_id = v_world_id)
          and (e.expires_at is null or e.expires_at > now())
        order by e.is_pinned desc, e.created_at desc
        limit v_limit
      ) x
    ), '[]'::jsonb),
    'fetched_at', now()
  );
end;
$$;
revoke all on function public.get_world_events_v1(integer) from public, anon;
grant execute on function public.get_world_events_v1(integer) to authenticated;

-- 突破播报：仅元婴及以上或造成实际损失/死亡的失败进入全服界闻。
create or replace function public.world_event_from_breakthrough_v0140()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg boolean := true;
  v_character public.player_characters%rowtype;
  v_realm_order integer := 0;
  v_nascent_order integer := 4;
  v_outcome text := coalesce(new.calculation_snapshot->>'outcome', new.result, 'unknown');
  v_attempted text := coalesce(new.calculation_snapshot->>'attempted_stage', new.calculation_snapshot->>'to_stage', '未知道关');
  v_from text := coalesce(new.calculation_snapshot->>'from_stage', '未知境界');
  v_current_stage text := '未知境界';
  v_title text;
  v_content text;
  v_level smallint := 2;
  v_lost bigint := greatest(0, coalesce(new.cultivation_before, 0) - coalesce(new.cultivation_after, 0));
  v_insight boolean := coalesce((new.calculation_snapshot->>'insight_gained')::boolean, false);
begin
  begin
    select s.breakthrough_enabled into v_cfg from public.jiuxiao_world_event_settings s where s.singleton_id = 1;
    if not coalesce(v_cfg, true) or new.action_type <> 'breakthrough' then return new; end if;

    select pc.* into v_character from public.player_characters pc where pc.id = new.character_id;
    if v_character.id is null then return new; end if;

    select r.major_order, rs.stage_name
      into v_realm_order, v_current_stage
    from public.realm_stages rs
    join public.realms r on r.id = rs.realm_id
    where rs.id = v_character.realm_stage_id;

    select coalesce(min(r.major_order) filter (where r.code = 'nascent_soul' or r.name like '元婴%'), 4)
      into v_nascent_order
    from public.realms r;

    if new.result = 'success' then
      if coalesce(v_realm_order, 0) < coalesce(v_nascent_order, 4) then return new; end if;
      v_title := '破境功成';
      v_level := case when coalesce(v_realm_order, 0) >= coalesce(v_nascent_order, 4) + 2 then 3 else 2 end;
      v_content := format('修士【%s】闭关叩问天门，终破【%s】之关，自此踏入【%s】。', v_character.name, v_from, coalesce(v_current_stage, v_attempted));
    else
      if coalesce(v_realm_order, 0) < coalesce(v_nascent_order, 4)
         and v_outcome not in ('death', 'major_fall', 'minor_fall', 'stage_reset', 'stage_half') then return new; end if;
      if v_outcome in ('major_fall_guarded', 'realm_floor_guarded', 'low_realm_no_penalty') then return new; end if;

      case v_outcome
        when 'death' then
          v_title := '身死道消'; v_level := 4;
          v_content := format('修士【%s】冲击【%s】时劫云彻底失控，肉身神魂俱散，此世道途至此而终。', v_character.name, v_attempted);
        when 'major_fall' then
          v_title := '道基崩裂'; v_level := 4;
          v_content := format('修士【%s】冲击【%s】失败，道基崩裂，由【%s】跌落至【%s】。', v_character.name, v_attempted, v_from, v_current_stage);
        when 'minor_fall' then
          v_title := '境界跌落'; v_level := 3;
          v_content := format('修士【%s】冲击【%s】失败，雷火侵入经脉，由【%s】跌落至【%s】。', v_character.name, v_attempted, v_from, v_current_stage);
        when 'stage_reset' then
          v_title := '道基受挫'; v_level := 3;
          v_content := format('修士【%s】冲击【%s】失败，为破境凝聚的修为尽数崩散，共折损%s点修为。', v_character.name, v_attempted, v_lost);
        when 'stage_half' then
          v_title := '灵力溃散'; v_level := 2;
          v_content := format('修士【%s】冲击【%s】失败，灵力半途溃散，共折损%s点修为。', v_character.name, v_attempted, v_lost);
        else
          v_title := '渡劫未成'; v_level := 2;
          v_content := format('修士【%s】冲击【%s】未成，所幸有惊无险，境界与修为皆得保全。', v_character.name, v_attempted);
      end case;

      if v_insight then
        v_content := v_content || '其于劫雷余韵中悟得一丝天劫真意。';
      end if;
    end if;

    perform public.world_event_publish_v0140(
      v_character.world_id, new.world_year, 'breakthrough_' || v_outcome, v_level,
      v_character.id, v_character.name, v_title, v_content,
      'cultivation_records', new.id::text,
      jsonb_build_object('outcome', v_outcome, 'attempted_stage', v_attempted, 'from_stage', v_from, 'current_stage', v_current_stage, 'cultivation_lost', v_lost),
      v_level >= 4, null
    );
  exception when others then
    -- 界闻只是旁路，不得让播报异常回滚突破结算。
    return new;
  end;
  return new;
end;
$$;
revoke all on function public.world_event_from_breakthrough_v0140() from public, anon, authenticated;

drop trigger if exists trg_world_event_breakthrough_v0140 on public.cultivation_records;
create trigger trg_world_event_breakthrough_v0140
after insert on public.cultivation_records
for each row execute function public.world_event_from_breakthrough_v0140();

-- 机缘播报：天品、仙品、专属必播；地品涉险造成损失时播报。
create or replace function public.world_event_from_opportunity_v0140()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg boolean := true;
  v_character public.player_characters%rowtype;
  v_title_name text := coalesce(new.result_data->>'title', new.rarity || '机缘');
  v_title text;
  v_content text;
  v_level smallint;
  v_world_year integer;
begin
  begin
    select s.opportunity_enabled into v_cfg from public.jiuxiao_world_event_settings s where s.singleton_id = 1;
    if not coalesce(v_cfg, true) then return new; end if;
    if new.rarity not in ('天品', '仙品', '专属') and not (new.rarity = '地品' and new.path_key = 'risk') then return new; end if;

    select pc.* into v_character from public.player_characters pc where pc.id = new.character_id;
    if v_character.id is null then return new; end if;
    select gw.current_year into v_world_year from public.game_worlds gw where gw.id = v_character.world_id;

    v_level := case new.rarity when '专属' then 4 when '仙品' then 4 when '天品' then 3 else 2 end;
    if new.path_key = 'risk' then
      v_title := case when new.rarity in ('仙品', '专属') then '仙缘反噬' else '天品机缘' end;
      v_content := format(
        '修士【%s】撞见一桩%s机缘【%s】，奈何气运未至，未能承接，反受其害：%s。',
        v_character.name, new.rarity, v_title_name, coalesce(nullif(new.penalty_text, ''), '机缘自眼前散去')
      );
    else
      v_title := case when new.rarity = '专属' then '命格传承' when new.rarity = '仙品' then '仙缘降世' else '天品机缘' end;
      v_content := format(
        '修士【%s】得遇%s机缘【%s】，顺势承接天机：%s。',
        v_character.name, new.rarity, v_title_name, coalesce(nullif(new.reward_text, ''), '福缘已入命数')
      );
    end if;

    perform public.world_event_publish_v0140(
      v_character.world_id, v_world_year, 'opportunity_' || lower(new.path_key) || '_' || new.rarity, v_level,
      v_character.id, v_character.name, v_title, v_content,
      'opportunity_v3_results', new.id::text,
      jsonb_build_object('rarity', new.rarity, 'path', new.path_key, 'title', v_title_name, 'reward_text', new.reward_text, 'penalty_text', new.penalty_text),
      v_level >= 4, null
    );
  exception when others then
    return new;
  end;
  return new;
end;
$$;
revoke all on function public.world_event_from_opportunity_v0140() from public, anon, authenticated;

drop trigger if exists trg_world_event_opportunity_v0140 on public.opportunity_v3_results;
create trigger trg_world_event_opportunity_v0140
after insert on public.opportunity_v3_results
for each row execute function public.world_event_from_opportunity_v0140();

-- 赌坊大堂：每一局胜负均播报。
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
begin
  begin
    select s.casino_enabled into v_cfg from public.jiuxiao_world_event_settings s where s.singleton_id = 1;
    if not coalesce(v_cfg, true) then return new; end if;

    select pc.* into v_character from public.player_characters pc where pc.id = new.character_id;
    if v_character.id is null then return new; end if;
    select gw.current_year into v_world_year from public.game_worlds gw where gw.id = v_character.world_id;

    if new.outcome_code = 'win' then
      v_title := case when v_net >= greatest(100000, new.stake_amount * 10) then '一掷得势' else '赌运亨通' end;
      v_level := case when new.stake_type = 'cultivation' or v_net >= 100000 then 2 else 1 end;
      v_content := format('修士【%s】于万运博弈楼以%s%s落注“%s”，押中天机，一局净得%s%s。', v_character.name, new.stake_amount, v_unit, v_game_name, v_net, v_unit);
    else
      v_title := case when new.stake_type = 'cultivation' then '修为折损' else '时运不济' end;
      v_level := case when new.stake_type = 'cultivation' or new.stake_amount >= 100000 then 2 else 1 end;
      v_content := format('修士【%s】于万运博弈楼以%s%s落注“%s”，奈何天意难测，一局折损%s%s。', v_character.name, new.stake_amount, v_unit, v_game_name, new.stake_amount, v_unit);
    end if;

    perform public.world_event_publish_v0140(
      v_character.world_id, v_world_year, 'casino_house_' || new.outcome_code, v_level,
      v_character.id, v_character.name, v_title, v_content,
      'casino_house_games', new.id::text,
      jsonb_build_object('game_code', new.game_code, 'stake_type', new.stake_type, 'stake_amount', new.stake_amount, 'reward_amount', new.reward_amount, 'net_change', case when new.outcome_code='win' then v_net else -new.stake_amount end),
      false, null
    );
  exception when others then
    return new;
  end;
  return new;
end;
$$;
revoke all on function public.world_event_from_house_game_v0140() from public, anon, authenticated;

drop trigger if exists trg_world_event_house_game_v0140 on public.casino_house_games;
create trigger trg_world_event_house_game_v0140
after insert on public.casino_house_games
for each row execute function public.world_event_from_house_game_v0140();

-- 赌坊雅间：开契后用一条合并消息同时播报胜者和败者。
create or replace function public.world_event_from_duel_v0140()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg boolean := true;
  v_winner public.player_characters%rowtype;
  v_loser public.player_characters%rowtype;
  v_world_year integer;
  v_unit text := case when new.stake_type = 'cultivation' then '点修为' else '枚灵石' end;
  v_net bigint := greatest(0, coalesce(new.prize_amount, 0) - coalesce(new.stake_amount, 0));
  v_loser_id uuid;
  v_level smallint := 1;
begin
  begin
    if old.status is not distinct from new.status or new.status <> 'settled' or new.winner_character_id is null then return new; end if;
    select s.casino_enabled into v_cfg from public.jiuxiao_world_event_settings s where s.singleton_id = 1;
    if not coalesce(v_cfg, true) then return new; end if;

    v_loser_id := case when new.winner_character_id = new.creator_character_id then new.opponent_character_id else new.creator_character_id end;
    select pc.* into v_winner from public.player_characters pc where pc.id = new.winner_character_id;
    select pc.* into v_loser from public.player_characters pc where pc.id = v_loser_id;
    if v_winner.id is null or v_loser.id is null then return new; end if;
    select gw.current_year into v_world_year from public.game_worlds gw where gw.id = v_winner.world_id;
    v_level := case when new.stake_type = 'cultivation' or new.stake_amount >= 100000 then 2 else 1 end;

    perform public.world_event_publish_v0140(
      v_winner.world_id, v_world_year, 'casino_duel_result', v_level,
      v_winner.id, v_winner.name, '赌契揭晓',
      format('修士【%s】与【%s】于万运博弈楼贵宾雅间立下赌契。开契之后【%s】胜出，净得%s%s；【%s】一局失利，折损%s%s。', v_winner.name, v_loser.name, v_winner.name, v_net, v_unit, v_loser.name, new.stake_amount, v_unit),
      'casino_duels', new.id::text,
      jsonb_build_object('winner_character_id', v_winner.id, 'winner_name', v_winner.name, 'loser_character_id', v_loser.id, 'loser_name', v_loser.name, 'stake_type', new.stake_type, 'stake_amount', new.stake_amount, 'winner_net', v_net),
      false, null
    );
  exception when others then
    return new;
  end;
  return new;
end;
$$;
revoke all on function public.world_event_from_duel_v0140() from public, anon, authenticated;

drop trigger if exists trg_world_event_duel_v0140 on public.casino_duels;
create trigger trg_world_event_duel_v0140
after update on public.casino_duels
for each row execute function public.world_event_from_duel_v0140();

-- 造化池开奖。
create or replace function public.world_event_from_casino_draw_v0140()
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
begin
  begin
    select s.casino_enabled into v_cfg from public.jiuxiao_world_event_settings s where s.singleton_id = 1;
    if not coalesce(v_cfg, true) or new.winner_character_id is null or new.prize_amount <= 0 then return new; end if;
    select pc.* into v_character from public.player_characters pc where pc.id = new.winner_character_id;
    if v_character.id is null then return new; end if;
    select gw.current_year into v_world_year from public.game_worlds gw where gw.id = v_character.world_id;

    perform public.world_event_publish_v0140(
      v_character.world_id, v_world_year, 'casino_pool_draw', 3,
      v_character.id, v_character.name, '造化开奖',
      format('万运博弈楼钟鸣九响，修士【%s】手中造化签无火自燃，独得本期造化池%s%s。', v_character.name, new.prize_amount, v_unit),
      'casino_draws', new.id::text,
      jsonb_build_object('stake_type', new.stake_type, 'prize_amount', new.prize_amount, 'ticket_count', new.ticket_count),
      true, null
    );
  exception when others then
    return new;
  end;
  return new;
end;
$$;
revoke all on function public.world_event_from_casino_draw_v0140() from public, anon, authenticated;

drop trigger if exists trg_world_event_casino_draw_v0140 on public.casino_draws;
create trigger trg_world_event_casino_draw_v0140
after insert on public.casino_draws
for each row execute function public.world_event_from_casino_draw_v0140();

-- 管理后台预留接口：先发布公开裁决文案，再由后台完成账号/角色删除。
create or replace function public.admin_publish_account_erasure_v1(
  p_character_name text,
  p_reason_code text default 'heaven_law_repeated',
  p_custom_reason text default null,
  p_source_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg boolean := true;
  v_reason text;
  v_key text := coalesce(nullif(btrim(p_source_key), ''), gen_random_uuid()::text);
  v_world_id uuid;
  v_world_year integer;
  v_event_id uuid;
begin
  if current_user not in ('postgres', 'service_role', 'supabase_admin')
     and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'ADMIN_REQUIRED';
  end if;
  if nullif(btrim(coalesce(p_character_name, '')), '') is null then raise exception 'INVALID_CHARACTER_NAME'; end if;

  select s.admin_enabled into v_cfg from public.jiuxiao_world_event_settings s where s.singleton_id = 1;
  if not coalesce(v_cfg, true) then raise exception 'WORLD_EVENT_ADMIN_DISABLED'; end if;

  v_reason := case p_reason_code
    when 'causal_disruption' then '屡次扰乱因果'
    when 'fate_tampering' then '妄图篡改命数'
    when 'forbidden_gain' then '借邪法谋取修为'
    when 'harassment' then '恶意侵扰同道'
    when 'heaven_law_repeated' then '屡逆天规'
    when 'custom' then nullif(btrim(p_custom_reason), '')
    else '违逆九霄律令'
  end;
  v_reason := coalesce(v_reason, '违逆九霄律令');

  select gw.id, gw.current_year into v_world_id, v_world_year
  from public.game_worlds gw
  order by gw.id
  limit 1;

  v_event_id := public.world_event_publish_v0140(
    v_world_id, v_world_year, 'admin_account_erasure'::text, 4::smallint,
    null::uuid, p_character_name, '天道裁决'::text,
    format('修士【%s】%s，已被天道抹去名籍，自此不存于九霄界中。', p_character_name, v_reason),
    'admin_account_erasure'::text, v_key,
    jsonb_build_object('reason_code', p_reason_code, 'public_reason', v_reason),
    true, null::timestamptz
  );

  return jsonb_build_object('success', v_event_id is not null, 'event_id', v_event_id, 'source_key', v_key);
end;
$$;
revoke all on function public.admin_publish_account_erasure_v1(text,text,text,text) from public, anon, authenticated;
grant execute on function public.admin_publish_account_erasure_v1(text,text,text,text) to service_role;

-- 一次性启用公告，避免部署后界闻长期空白。
select public.world_event_publish_v0140(
  (select gw.id from public.game_worlds gw order by gw.id limit 1),
  (select gw.current_year from public.game_worlds gw order by gw.id limit 1),
  'system_world_feed_open', 2::smallint, null::uuid, '天道'::text, '界闻初启'::text,
  '九霄天机重新汇聚，自今日起，重大破境、珍稀机缘与赌坊胜负皆将传遍诸域。'::text,
  'system'::text, 'v0140-world-feed-open'::text, jsonb_build_object('version', '0.14.0'), true, null::timestamptz
);

comment on table public.jiuxiao_world_events is 'V0.14.0 FIX2：九霄界闻全服重大事件，只能通过受保护函数和触发器写入。';
comment on function public.get_world_events_v1(integer) is 'V0.14.0 FIX2：认证玩家读取最近九霄界闻。';
comment on function public.admin_publish_account_erasure_v1(text,text,text,text) is 'V0.14.0 FIX2：仅service_role/数据库管理员可调用的天道抹杀公开播报接口。';

commit;
