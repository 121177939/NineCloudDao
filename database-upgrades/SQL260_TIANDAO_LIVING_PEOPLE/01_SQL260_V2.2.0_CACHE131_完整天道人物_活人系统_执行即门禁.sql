-- 九霄问道 SQL260 R2 · V2.2.0 CACHE131
-- 完整天道人物：每日生活 / 主动传音 / 人生事件线 / 自由交谈 / 情境赠礼 / 情境相约 / 承诺 / 记忆去重 / 关系画像
-- 基线要求：SQL259 ONLINE / SQL259_GATE_PASSED
-- 兼容：继续复用已上线 tiandao-ai Edge Function；无需重新部署 Edge。Cloudflare 仍只负责人格与语言提案，所有状态变化继续由 PostgreSQL 审核。
-- 成功后：SQL260 ONLINE / NEXT SQL261
-- R2兼容热修：SQL259线上 tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb) 的 ABI 为 p_type + RETURNS void。
-- 本版保持原参数名与返回类型，仅替换函数体加入去重逻辑；不 DROP FUNCTION，避免破坏现有依赖。
-- 如果曾执行 R1 并遇到 42P13 cannot change return type，该次事务未能 COMMIT；直接从头执行本 R2。

begin;

-- ==================== PRECHECK ====================
do $precheck$
begin
  if to_regclass('public.tiandao_people_settings_v259') is null then raise exception 'SQL260_PRECHECK_SQL259_SETTINGS_MISSING'; end if;
  if to_regclass('public.tiandao_npcs_v259') is null then raise exception 'SQL260_PRECHECK_SQL259_NPCS_MISSING'; end if;
  if to_regclass('public.tiandao_relations_v259') is null then raise exception 'SQL260_PRECHECK_SQL259_RELATIONS_MISSING'; end if;
  if to_regclass('public.tiandao_ai_requests_v259') is null then raise exception 'SQL260_PRECHECK_SQL259_AI_REQUESTS_MISSING'; end if;
  if to_regprocedure('public.tianxu_active_character_v255()') is null then raise exception 'SQL260_PRECHECK_ACTIVE_CHARACTER_HELPER_MISSING'; end if;
  if to_regprocedure('public.tianxu_inventory_adjust_v255(uuid,text,bigint)') is null then raise exception 'SQL260_PRECHECK_INVENTORY_HELPER_MISSING'; end if;
  if to_regprocedure('public.admin_whoami_v1()') is null then raise exception 'SQL260_PRECHECK_ADMIN_WHOAMI_MISSING'; end if;
  if to_regprocedure('public.tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb)') is null then raise exception 'SQL260_PRECHECK_MEMORY_FUNCTION_MISSING'; end if;
  if pg_get_function_result(to_regprocedure('public.tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb)'))<>'void' then raise exception 'SQL260_PRECHECK_MEMORY_FUNCTION_ABI_NOT_VOID'; end if;
end
$precheck$;

-- ==================== SETTINGS / RELATION EXTENSIONS ====================
alter table public.tiandao_people_settings_v259 add column if not exists living_people_enabled boolean not null default true;
alter table public.tiandao_people_settings_v259 add column if not exists daily_life_enabled boolean not null default true;
alter table public.tiandao_people_settings_v259 add column if not exists npc_initiative_enabled boolean not null default true;
alter table public.tiandao_people_settings_v259 add column if not exists story_enabled boolean not null default true;
alter table public.tiandao_people_settings_v259 add column if not exists free_talk_enabled boolean not null default true;
alter table public.tiandao_people_settings_v259 add column if not exists daily_refresh_hours integer not null default 18 check(daily_refresh_hours between 1 and 168);
alter table public.tiandao_people_settings_v259 add column if not exists max_active_stories integer not null default 3 check(max_active_stories between 1 and 10);
alter table public.tiandao_people_settings_v259 add column if not exists max_unread_inbox integer not null default 6 check(max_unread_inbox between 1 and 30);
alter table public.tiandao_people_settings_v259 add column if not exists story_expire_hours integer not null default 72 check(story_expire_hours between 12 and 720);
alter table public.tiandao_people_settings_v259 add column if not exists promise_hours integer not null default 48 check(promise_hours between 6 and 336);
alter table public.tiandao_people_settings_v259 add column if not exists memory_dedupe_hours integer not null default 168 check(memory_dedupe_hours between 1 and 8760);

alter table public.tiandao_relations_v259 add column if not exists respect integer not null default 0 check(respect between 0 and 100);
alter table public.tiandao_relations_v259 add column if not exists promise_kept integer not null default 0 check(promise_kept >= 0);
alter table public.tiandao_relations_v259 add column if not exists promise_broken integer not null default 0 check(promise_broken >= 0);

-- ==================== LIVING PEOPLE TABLES ====================
create table if not exists public.tiandao_life_state_v260(
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  mood_code text not null default 'calm',
  mood_label text not null default '平静',
  mood_detail text not null default '',
  current_activity text not null default '',
  current_place text not null default '九霄界',
  current_need text not null default '',
  current_topic text not null default '',
  life_phase integer not null default 1 check(life_phase between 1 and 99),
  daily_key text not null default '',
  last_initiative_at timestamptz,
  updated_at timestamptz not null default clock_timestamp(),
  primary key(character_id,npc_id)
);
create index if not exists tiandao_life_state_updated_idx_v260 on public.tiandao_life_state_v260(character_id,updated_at desc);

create table if not exists public.tiandao_story_threads_v260(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  story_key text not null,
  title text not null,
  premise text not null,
  stage integer not null default 1 check(stage between 1 and 5),
  branch text not null default 'open',
  current_summary text not null default '',
  choices jsonb not null default '[]'::jsonb,
  status text not null default 'active' check(status in('active','resolved','expired')),
  started_at timestamptz not null default clock_timestamp(),
  last_advanced_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp()+interval '72 hours'),
  resolved_at timestamptz
);
create unique index if not exists tiandao_story_active_unique_v260 on public.tiandao_story_threads_v260(character_id,npc_id) where status='active';
create index if not exists tiandao_story_character_idx_v260 on public.tiandao_story_threads_v260(character_id,status,last_advanced_at desc);

create table if not exists public.tiandao_inbox_v260(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  message_kind text not null default 'initiative',
  title text not null,
  content text not null,
  actions jsonb not null default '[]'::jsonb,
  context jsonb not null default '{}'::jsonb,
  status text not null default 'unread' check(status in('unread','read','resolved','expired')),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp()+interval '7 days'),
  read_at timestamptz,
  resolved_at timestamptz
);
create index if not exists tiandao_inbox_character_idx_v260 on public.tiandao_inbox_v260(character_id,status,created_at desc);
create index if not exists tiandao_inbox_npc_idx_v260 on public.tiandao_inbox_v260(character_id,npc_id,created_at desc);

create table if not exists public.tiandao_promises_v260(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  thread_id uuid references public.tiandao_story_threads_v260(id) on delete set null,
  promise_code text not null,
  title text not null,
  status text not null default 'active' check(status in('active','fulfilled','broken','cancelled')),
  due_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz
);
create index if not exists tiandao_promises_character_idx_v260 on public.tiandao_promises_v260(character_id,status,due_at);
create unique index if not exists tiandao_promises_active_story_unique_v260 on public.tiandao_promises_v260(character_id,thread_id) where status='active' and thread_id is not null;

-- ==================== GENERIC HELPERS ====================
create or replace function public.tiandao_relation_band_v260(p_value integer,p_kind text default 'normal')
returns text language plpgsql immutable set search_path='' as $$
begin
  if p_kind='affinity' then
    return case when p_value>=80 then '很在意你' when p_value>=55 then '亲近' when p_value>=30 then '有好感' when p_value>=10 then '不排斥' when p_value<=-40 then '明显厌恶' when p_value<0 then '有些反感' else '平淡' end;
  elsif p_kind='trust' then
    return case when p_value>=80 then '几乎没有戒备' when p_value>=55 then '愿意信你' when p_value>=30 then '开始信任' when p_value>=10 then '仍在观察' else '很谨慎' end;
  elsif p_kind='intimacy' then
    return case when p_value>=80 then '彼此极为熟悉' when p_value>=55 then '相处自然' when p_value>=30 then '有不少共同经历' when p_value>=10 then '刚开始熟悉' else '还很生疏' end;
  elsif p_kind='respect' then
    return case when p_value>=80 then '非常敬重你的选择' when p_value>=55 then '认可你' when p_value>=30 then '对你有几分敬意' when p_value>=10 then '尚可' else '还没有形成评价' end;
  elsif p_kind='gratitude' then
    return case when p_value>=70 then '欠你很深的人情' when p_value>=40 then '记得你的帮助' when p_value>=15 then '承过你的情' else '没有明显亏欠' end;
  end if;
  return case when p_value>=80 then '很深' when p_value>=55 then '较深' when p_value>=30 then '一般' when p_value>=10 then '轻微' else '很低' end;
end $$;

create or replace function public.tiandao_gift_category_v260(p_preference text)
returns text language plpgsql immutable set search_path='' as $$
declare v text:=coalesce(p_preference,'');
begin
  if v='' then return 'practical'; end if;
  if v='无' then return 'none'; end if;
  if v ~ '(乐谱|茶|花酿|书卷|古卷|琴|酒)' then return 'elegant'; end if;
  if v ~ '(奇物|奇珍|星石)' then return 'rare'; end if;
  if v ~ '(阵|剑|刀|药|灵草|寒玉|矿石|木材|符|护|火晶|灵兽)' then return 'cultivation'; end if;
  return 'practical';
end $$;

create or replace function public.tiandao_story_choices_v260(p_stage integer,p_branch text)
returns jsonb language plpgsql immutable set search_path='' as $$
begin
  if p_stage<=1 then
    return jsonb_build_array(
      jsonb_build_object('code','story:offer_help','label','主动问能不能帮忙','tone','承担'),
      jsonb_build_object('code','story:listen','label','先听TA把话说完','tone','倾听'),
      jsonb_build_object('code','story:give_space','label','不追问，给TA一点空间','tone','尊重')
    );
  elsif p_stage=2 and p_branch='promised' then
    return jsonb_build_array(
      jsonb_build_object('code','story:fulfill','label','把答应的事做到','tone','守诺'),
      jsonb_build_object('code','story:be_honest','label','坦白自己现在做不到','tone','诚实'),
      jsonb_build_object('code','story:withdraw','label','临时反悔','tone','失约')
    );
  elsif p_stage=2 then
    return jsonb_build_array(
      jsonb_build_object('code','story:ask_progress','label','问问事情有没有进展','tone','关心'),
      jsonb_build_object('code','story:encourage','label','鼓励TA按自己的想法做','tone','支持'),
      jsonb_build_object('code','story:leave_it','label','不再插手','tone','克制')
    );
  elsif p_stage=3 then
    return jsonb_build_array(
      jsonb_build_object('code','story:stand_with','label','站在TA这边','tone','同行'),
      jsonb_build_object('code','story:advise','label','认真给一个建议','tone','理性'),
      jsonb_build_object('code','story:let_choose','label','把最后决定留给TA','tone','尊重')
    );
  elsif p_stage=4 then
    return jsonb_build_array(
      jsonb_build_object('code','story:celebrate','label','陪TA庆祝结果','tone','亲近'),
      jsonb_build_object('code','story:remember','label','把这件事认真记下来','tone','珍重'),
      jsonb_build_object('code','story:move_on','label','让事情过去，继续前行','tone','洒脱')
    );
  end if;
  return '[]'::jsonb;
end $$;

create or replace function public.tiandao_story_seed_v260(p_character_id uuid,p_npc_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare n public.tiandao_npcs_v259%rowtype;v_title text;v_premise text;v_key text;
begin
  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;
  if n.id is null then return '{}'::jsonb; end if;
  v_key:=n.npc_code||':'||to_char(clock_timestamp(),'IYYY-IW');
  if n.identity ~ '(阵)' then v_title:='未合的阵纹';v_premise:=n.name||'最近反复推演一处阵纹，似乎卡在关键地方。';
  elsif n.identity ~ '(丹|药|医|灵植)' then v_title:='一味难寻';v_premise:=n.name||'最近为了修行中的一味关键材料四处奔波，看起来并不顺利。';
  elsif n.identity ~ '(剑|刀|守|镇|巡)' then v_title:='临行之前';v_premise:=n.name||'近期要面对一件并不轻松的事，言语间比往常更谨慎。';
  elsif n.identity ~ '(商|舟)' then v_title:='一段不稳的路';v_premise:=n.name||'手上的一段行程或商路出了岔子，正在权衡要不要冒险继续。';
  elsif n.identity ~ '(琴|乐|书|观星|儒)' then v_title:='未完之作';v_premise:=n.name||'最近一直惦记着一件没有完成的作品，似乎已经到了必须作出取舍的时候。';
  elsif n.identity ~ '(驭兽)' then v_title:='迟迟未归';v_premise:=n.name||'最近总会望向远处，像是在等一个迟迟没有回来的消息。';
  else v_title:='眼前的一桩事';v_premise:=n.name||'最近明显有件事牵着心神，却还没有主动说透。';end if;
  return jsonb_build_object('story_key',v_key,'title',v_title,'premise',v_premise);
end $$;

-- ==================== MEMORY DEDUPE ====================
create or replace function public.tiandao_add_memory_v259(
  p_character_id uuid,p_npc_id uuid,p_type text,p_content text,p_importance integer default 1,p_public boolean default true,p_metadata jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_hours integer:=168;v_content text:=left(trim(coalesce(p_content,'')),700);v_type text:=left(coalesce(nullif(trim(p_type),''),'event'),60);
begin
  if v_content='' then return; end if;
  select coalesce(memory_dedupe_hours,168) into v_hours from public.tiandao_people_settings_v259 where singleton_id=1;
  if exists(
    select 1 from public.tiandao_memories_v259 m
    where m.character_id=p_character_id and m.npc_id=p_npc_id and m.memory_type=v_type
      and regexp_replace(lower(m.content),'\s+','','g')=regexp_replace(lower(v_content),'\s+','','g')
      and m.created_at>clock_timestamp()-make_interval(hours=>v_hours)
  ) then
    return;
  end if;
  insert into public.tiandao_memories_v259(character_id,npc_id,memory_type,content,importance,public_to_player,metadata)
  values(p_character_id,p_npc_id,v_type,v_content,greatest(1,least(5,coalesce(p_importance,1))),coalesce(p_public,true),coalesce(p_metadata,'{}'::jsonb));
  -- 继续保留 SQL259 的容量上限：每组人物关系最多保留最近50条低重要度记忆，重要度4/5永久保留。
  delete from public.tiandao_memories_v259 m
  where m.id in(
    select x.id from public.tiandao_memories_v259 x
    where x.character_id=p_character_id and x.npc_id=p_npc_id and x.importance<=3
    order by x.created_at desc offset 50
  );
end $$;

-- 清理历史中完全重复的低重要度流水账；重要记忆不动。
with ranked as (
  select id,row_number() over(partition by character_id,npc_id,memory_type,regexp_replace(lower(content),'\s+','','g') order by created_at desc,id desc) rn
  from public.tiandao_memories_v259 where importance<=2
)
delete from public.tiandao_memories_v259 m using ranked r where m.id=r.id and r.rn>1;

-- ==================== DAILY LIFE / STORY / INITIATIVE ====================
create or replace function public.tiandao_refresh_person_life_v260(p_character_id uuid,p_npc_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare s public.tiandao_people_settings_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;ls public.tiandao_life_state_v260%rowtype;v_key text;v_roll int;v_mood text;v_label text;v_detail text;v_activity text;v_place text;v_need text;v_topic text;
begin
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not s.enabled or not s.living_people_enabled or not s.daily_life_enabled then return; end if;
  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;if n.id is null then return;end if;
  select * into r from public.tiandao_relations_v259 where character_id=p_character_id and npc_id=n.id;if r.npc_id is null or r.known_level='unknown' then return;end if;
  v_key:=to_char(clock_timestamp(),'YYYY-MM-DD');
  select * into ls from public.tiandao_life_state_v260 where character_id=p_character_id and npc_id=n.id;
  if ls.npc_id is not null and ls.daily_key=v_key and ls.updated_at>clock_timestamp()-make_interval(hours=>s.daily_refresh_hours) then return;end if;
  v_roll:=mod(mod(hashtextextended(p_character_id::text||':'||n.id::text||':'||v_key,260),8)+8,8)::int;
  v_mood:=case v_roll when 0 then 'calm' when 1 then 'focused' when 2 then 'cheerful' when 3 then 'tired' when 4 then 'restless' when 5 then 'troubled' when 6 then 'curious' else 'quiet' end;
  v_label:=case v_mood when 'calm' then '平静' when 'focused' then '专注' when 'cheerful' then '心情不错' when 'tired' then '有些疲惫' when 'restless' then '有点坐不住' when 'troubled' then '似有心事' when 'curious' then '兴致正浓' else '安静' end;
  v_activity:=case
    when n.identity ~ '(阵)' then '正在推演阵纹'
    when n.identity ~ '(剑|刀)' then '正在磨炼招式'
    when n.identity ~ '(丹|药|医|灵植)' then '正在整理药材与修行心得'
    when n.identity ~ '(商)' then '正在核对最近的物资与消息'
    when n.identity ~ '(舟)' then '正在整备下一段行程'
    when n.identity ~ '(琴|乐)' then '正在练一段尚未完成的曲子'
    when n.identity ~ '(书|儒)' then '正在整理手边的书卷'
    when n.identity ~ '(符)' then '正在试画新的符式'
    when n.identity ~ '(驭兽)' then '正在照料灵兽'
    when n.identity ~ '(守|镇|巡|执法)' then '正在处理值守之事'
    else '正在处理自己的修行与日常' end;
  v_place:=case mod(mod(hashtextextended(n.npc_code||':'||v_key,261),6)+6,6)::int when 0 then '宗门附近' when 1 then '坊市一带' when 2 then '后山' when 3 then '云海渡口' when 4 then '修炼静室' else '九霄界途中' end;
  v_detail:=case v_mood
    when 'focused' then n.name||'今天明显把心思都放在'||v_activity||'上。'
    when 'cheerful' then n.name||'今天比平时放松，似乎刚遇到一件顺心事。'
    when 'tired' then n.name||'看起来昨夜没有休息好，但仍在处理自己的事。'
    when 'restless' then n.name||'今天不太愿意久坐，像是在等什么消息。'
    when 'troubled' then n.name||'今天有些心不在焉，几次欲言又止。'
    when 'curious' then n.name||'最近对一件新鲜事颇有兴趣，提起时话会多一些。'
    when 'quiet' then n.name||'今天话不多，更像是在独自整理思绪。'
    else n.name||'今天心境平稳，正在按自己的节奏生活。' end;
  v_need:=case v_mood when 'troubled' then '也许需要一个愿意认真听的人' when 'tired' then '也许更需要轻松一点的陪伴' when 'focused' then '正在为手上的事情寻找突破口' when 'restless' then '可能更想出去走走' else '没有明显向外求助' end;
  v_topic:=case when r.trust>=55 then '最近愿意和你谈更私人的事' when r.trust>=25 then '最近愿意聊自己的近况' else '目前仍偏向聊轻松、安全的话题' end;
  insert into public.tiandao_life_state_v260(character_id,npc_id,mood_code,mood_label,mood_detail,current_activity,current_place,current_need,current_topic,life_phase,daily_key,updated_at)
  values(p_character_id,n.id,v_mood,v_label,v_detail,v_activity,v_place,v_need,v_topic,coalesce(ls.life_phase,1),v_key,clock_timestamp())
  on conflict(character_id,npc_id) do update set mood_code=excluded.mood_code,mood_label=excluded.mood_label,mood_detail=excluded.mood_detail,current_activity=excluded.current_activity,current_place=excluded.current_place,current_need=excluded.current_need,current_topic=excluded.current_topic,daily_key=excluded.daily_key,updated_at=clock_timestamp();
end $$;

create or replace function public.tiandao_spawn_story_v260(p_character_id uuid,p_npc_id uuid,p_force boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.tiandao_people_settings_v259%rowtype;r public.tiandao_relations_v259%rowtype;n public.tiandao_npcs_v259%rowtype;v_seed jsonb;v_id uuid;v_recent timestamptz;v_active int;v_roll int;
begin
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not s.enabled or not s.living_people_enabled or not s.story_enabled then return null;end if;
  select * into r from public.tiandao_relations_v259 where character_id=p_character_id and npc_id=p_npc_id;
  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;
  if r.npc_id is null or n.id is null or r.known_level not in('acquainted','familiar','close') then return null;end if;
  select id into v_id from public.tiandao_story_threads_v260 where character_id=p_character_id and npc_id=p_npc_id and status='active' limit 1;
  if v_id is not null then return v_id;end if;
  select count(*) into v_active from public.tiandao_story_threads_v260 where character_id=p_character_id and status='active';
  if v_active>=s.max_active_stories then return null;end if;
  select max(started_at) into v_recent from public.tiandao_story_threads_v260 where character_id=p_character_id and npc_id=p_npc_id;
  if not p_force and v_recent is not null and v_recent>clock_timestamp()-interval '5 days' then return null;end if;
  v_roll:=mod(mod(hashtextextended(p_character_id::text||':'||p_npc_id::text||':'||to_char(clock_timestamp(),'IYYY-IW'),262),100)+100,100)::int;
  if not p_force and v_roll>least(65,12+greatest(0,r.affinity)/5+r.trust/6+r.interaction_count) then return null;end if;
  v_seed:=public.tiandao_story_seed_v260(p_character_id,p_npc_id);
  if v_seed='{}'::jsonb then return null;end if;
  insert into public.tiandao_story_threads_v260(character_id,npc_id,story_key,title,premise,stage,branch,current_summary,choices,status,expires_at)
  values(p_character_id,p_npc_id,v_seed->>'story_key',v_seed->>'title',v_seed->>'premise',1,'open',v_seed->>'premise',public.tiandao_story_choices_v260(1,'open'),'active',clock_timestamp()+make_interval(hours=>s.story_expire_hours))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.tiandao_maybe_initiative_v260(p_character_id uuid,p_npc_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.tiandao_people_settings_v259%rowtype;r public.tiandao_relations_v259%rowtype;n public.tiandao_npcs_v259%rowtype;ls public.tiandao_life_state_v260%rowtype;t public.tiandao_story_threads_v260%rowtype;v_count int;v_roll int;v_id uuid;v_title text;v_content text;
begin
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not s.enabled or not s.living_people_enabled or not s.npc_initiative_enabled then return null;end if;
  select * into r from public.tiandao_relations_v259 where character_id=p_character_id and npc_id=p_npc_id;
  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;
  if r.npc_id is null or n.id is null or r.known_level not in('acquainted','familiar','close') then return null;end if;
  perform public.tiandao_refresh_person_life_v260(p_character_id,p_npc_id);
  select * into ls from public.tiandao_life_state_v260 where character_id=p_character_id and npc_id=p_npc_id;
  select * into t from public.tiandao_story_threads_v260 where character_id=p_character_id and npc_id=p_npc_id and status='active' order by started_at desc limit 1;
  if exists(select 1 from public.tiandao_inbox_v260 where character_id=p_character_id and npc_id=p_npc_id and status in('unread','read') and created_at>clock_timestamp()-interval '20 hours') then return null;end if;
  select count(*) into v_count from public.tiandao_inbox_v260 where character_id=p_character_id and status='unread' and expires_at>clock_timestamp();
  if v_count>=s.max_unread_inbox then return null;end if;
  v_roll:=mod(mod(hashtextextended(p_character_id::text||':'||p_npc_id::text||':'||to_char(clock_timestamp(),'YYYY-MM-DD'),263),100)+100,100)::int;
  if v_roll>least(45,8+greatest(0,r.affinity)/6+r.trust/8+case when t.id is not null then 12 else 0 end) then return null;end if;
  if t.id is not null then
    v_title:=n.name||'想和你再聊聊';
    v_content:='关于“'||t.title||'”，'||n.name||'给你留了一句话：若你有空，想再听听你的想法。';
  elsif ls.mood_code='troubled' then v_title:=n.name||'给你传了句话';v_content:=n.name||'今日似乎有些心事，只简单问了一句：“你若有空，能不能来坐一会？”';
  elsif ls.mood_code='cheerful' then v_title:=n.name||'忽然想起了你';v_content:=n.name||'今天心情不错，路过'||coalesce(nullif(ls.current_place,''),'某处')||'时忽然想起你，给你留了条轻松的讯息。';
  elsif ls.mood_code='tired' then v_title:=n.name||'今日有些疲惫';v_content:=n.name||'忙了一阵后给你传来一条短讯，没有说大事，只是想听听你的声音。';
  else v_title:=n.name||'主动联系了你';v_content:=n.name||'处理完手边的事后主动找你，问你最近修行得怎么样。';end if;
  insert into public.tiandao_inbox_v260(character_id,npc_id,message_kind,title,content,actions,context,status,expires_at)
  values(p_character_id,n.id,'initiative',v_title,v_content,jsonb_build_array(
    jsonb_build_object('code','inbox:reply','label','认真回TA'),jsonb_build_object('code','inbox:accept','label','去见TA'),jsonb_build_object('code','inbox:later','label','晚些再说')
  ),jsonb_build_object('story_id',t.id,'mood',ls.mood_code),'unread',clock_timestamp()+interval '7 days') returning id into v_id;
  update public.tiandao_life_state_v260 set last_initiative_at=clock_timestamp() where character_id=p_character_id and npc_id=n.id;
  return v_id;
end $$;

create or replace function public.tiandao_refresh_world_v260(p_character_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare s public.tiandao_people_settings_v259%rowtype;x record;v_story_count int;v_initiative_done boolean:=false;v_id uuid;
begin
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not s.enabled or not s.living_people_enabled then return;end if;
  update public.tiandao_inbox_v260 set status='expired' where character_id=p_character_id and status in('unread','read') and expires_at<=clock_timestamp();
  -- 逾期承诺：只在真正过期后结算一次；不清空关系，只留下长期后果。
  for x in select p.id,p.npc_id,p.thread_id from public.tiandao_promises_v260 p where p.character_id=p_character_id and p.status='active' and p.due_at<clock_timestamp() for update loop
    update public.tiandao_promises_v260 set status='broken',resolved_at=clock_timestamp() where id=x.id;
    update public.tiandao_relations_v259 set trust=greatest(0,trust-5),respect=greatest(0,respect-6),promise_broken=promise_broken+1,latest_rumor='你曾答应过一件事，却最终错过了约定的时间。',updated_at=clock_timestamp() where character_id=p_character_id and npc_id=x.npc_id;
    perform public.tiandao_add_memory_v259(p_character_id,x.npc_id,'promise_broken','你曾答应过一件事，却最终没有在约定时间内做到。',4,true,jsonb_build_object('promise_id',x.id,'thread_id',x.thread_id));
  end loop;
  -- 人生事件过期时NPC会自己继续生活，不会冻结等待玩家。
  for x in select t.id,t.npc_id,t.title from public.tiandao_story_threads_v260 t where t.character_id=p_character_id and t.status='active' and t.expires_at<clock_timestamp() for update loop
    update public.tiandao_story_threads_v260 set status='expired',branch='self_resolved',current_summary='你没有继续介入，TA最终按自己的方式把事情走完了。',resolved_at=clock_timestamp() where id=x.id;
    update public.tiandao_relations_v259 set current_status='TA的人生仍在继续，并没有停在等待你的地方。',updated_at=clock_timestamp() where character_id=p_character_id and npc_id=x.npc_id;
    perform public.tiandao_add_memory_v259(p_character_id,x.npc_id,'story_missed','“'||x.title||'”后来由TA自己走到了结果。你没有参与其中。',3,true,jsonb_build_object('story_id',x.id));
  end loop;
  for x in
    select r.npc_id,r.affinity,r.trust,r.interaction_count
    from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id and n.enabled
    where r.character_id=p_character_id and r.known_level<>'unknown'
    order by (case r.known_level when 'close' then 0 when 'familiar' then 1 when 'acquainted' then 2 else 3 end),r.updated_at desc
    limit 50
  loop
    perform public.tiandao_refresh_person_life_v260(p_character_id,x.npc_id);
  end loop;
  select count(*) into v_story_count from public.tiandao_story_threads_v260 where character_id=p_character_id and status='active';
  if s.story_enabled and v_story_count<s.max_active_stories then
    for x in
      select r.npc_id from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id and n.enabled
      where r.character_id=p_character_id and r.known_level in('acquainted','familiar','close')
      order by r.interaction_count desc,r.trust desc,r.affinity desc,r.updated_at desc limit 8
    loop
      v_id:=public.tiandao_spawn_story_v260(p_character_id,x.npc_id,false);
      exit when v_id is not null;
    end loop;
  end if;
  if s.npc_initiative_enabled then
    for x in
      select r.npc_id from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id and n.enabled
      where r.character_id=p_character_id and r.known_level in('acquainted','familiar','close')
      order by (r.trust+r.affinity+r.intimacy) desc,r.updated_at desc limit 10
    loop
      v_id:=public.tiandao_maybe_initiative_v260(p_character_id,x.npc_id);
      if v_id is not null then v_initiative_done:=true;exit;end if;
    end loop;
  end if;
end $$;

-- ==================== PLAYER READ RPCS ====================
create or replace function public.get_tiandao_people_hub_v1()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();v_people jsonb;v_enc jsonb;v_rom jsonb;v_comp jsonb;v_counts jsonb;v_inbox jsonb;v_stories jsonb;
begin
  if not (select enabled from public.tiandao_people_settings_v259 where singleton_id=1) then return jsonb_build_object('status','disabled','people','[]'::jsonb,'encounters','[]'::jsonb,'romance','[]'::jsonb,'companion',null,'inbox','[]'::jsonb,'stories','[]'::jsonb,'counts','{}'::jsonb);end if;
  perform public.tiandao_seed_visibility_v259(v_char);
  perform public.tiandao_maybe_spawn_encounter_v259(v_char,'天道缘遇');
  perform public.tiandao_refresh_world_v260(v_char);
  update public.tiandao_encounters_v259 set status='expired' where character_id=v_char and status='pending' and expires_at<=clock_timestamp();

  select coalesce(jsonb_agg(x.obj order by x.sort_key,x.name),'[]'::jsonb) into v_people from(
    select n.name,case r.known_level when 'close' then 0 when 'familiar' then 1 when 'acquainted' then 2 else 3 end sort_key,
      jsonb_build_object(
        'npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'gender',n.gender,'realm_label',n.realm_label,'identity',n.identity,'element',n.element,
        'known_level',r.known_level,'relation_stage',public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,c.character_id is not null),
        'affinity',r.affinity,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'respect',r.respect,
        'current_status',r.current_status,'latest_rumor',r.latest_rumor,'mood_label',ls.mood_label,'mood_detail',ls.mood_detail,'current_activity',ls.current_activity,'current_place',ls.current_place,
        'active_story_title',st.title,'active_story_stage',st.stage,'unread_count',(select count(*) from public.tiandao_inbox_v260 i where i.character_id=v_char and i.npc_id=n.id and i.status='unread' and i.expires_at>clock_timestamp()),
        'is_companion',(c.character_id is not null),
        'can_confess',(n.romanceable and c.character_id is null and r.affinity>=(select confess_affinity_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.trust>=(select confess_trust_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.intimacy>=(select confess_intimacy_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.romance>=(select confess_romance_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.hatred<25)
      ) obj
    from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id
    left join public.tiandao_companions_v259 c on c.character_id=v_char and c.npc_id=n.id and c.status='active'
    left join public.tiandao_life_state_v260 ls on ls.character_id=v_char and ls.npc_id=n.id
    left join public.tiandao_story_threads_v260 st on st.character_id=v_char and st.npc_id=n.id and st.status='active'
    where r.character_id=v_char and r.known_level<>'unknown' and n.enabled
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'encounter_id',e.id,'npc_id',e.npc_id,'npc_name',n.name,'title',e.title,'summary',e.summary,'location_name',e.location_name,'source_label',e.source_label,
    'actions',e.actions,'action_code',coalesce(e.actions->0->>'code','approach'),'action_label',coalesce(e.actions->0->>'label','回应'),'expires_at',e.expires_at
  ) order by e.created_at desc),'[]'::jsonb) into v_enc
  from public.tiandao_encounters_v259 e join public.tiandao_npcs_v259 n on n.id=e.npc_id
  where e.character_id=v_char and e.status='pending' and e.expires_at>clock_timestamp();

  select coalesce(jsonb_agg(jsonb_build_object(
    'message_id',i.id,'npc_id',i.npc_id,'npc_name',n.name,'title',i.title,'content',i.content,'message_kind',i.message_kind,'actions',i.actions,'context',i.context,'status',i.status,'created_at',i.created_at,'expires_at',i.expires_at
  ) order by case when i.status='unread' then 0 else 1 end,i.created_at desc),'[]'::jsonb) into v_inbox
  from public.tiandao_inbox_v260 i join public.tiandao_npcs_v259 n on n.id=i.npc_id
  where i.character_id=v_char and i.status in('unread','read') and i.expires_at>clock_timestamp();

  select coalesce(jsonb_agg(jsonb_build_object(
    'story_id',t.id,'npc_id',t.npc_id,'npc_name',n.name,'title',t.title,'premise',t.premise,'stage',t.stage,'branch',t.branch,'current_summary',t.current_summary,'choices',t.choices,'expires_at',t.expires_at
  ) order by t.last_advanced_at desc),'[]'::jsonb) into v_stories
  from public.tiandao_story_threads_v260 t join public.tiandao_npcs_v259 n on n.id=t.npc_id
  where t.character_id=v_char and t.status='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'realm_label',n.realm_label,'identity',n.identity,
    'known_level',r.known_level,'relation_stage',public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,c.character_id is not null),
    'affinity',r.affinity,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'respect',r.respect,
    'current_status',r.current_status,'latest_rumor',r.latest_rumor,'mood_label',ls.mood_label,'current_activity',ls.current_activity,'is_companion',(c.character_id is not null),
    'can_confess',(c.character_id is null and r.affinity>=(select confess_affinity_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.trust>=(select confess_trust_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.intimacy>=(select confess_intimacy_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.romance>=(select confess_romance_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.hatred<25)
  ) order by r.romance desc,r.intimacy desc,r.affinity desc),'[]'::jsonb) into v_rom
  from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id and n.romanceable and n.enabled
  left join public.tiandao_companions_v259 c on c.character_id=v_char and c.npc_id=n.id and c.status='active'
  left join public.tiandao_life_state_v260 ls on ls.character_id=v_char and ls.npc_id=n.id
  where r.character_id=v_char and r.known_level<>'unknown' and (r.affinity>=10 or r.romance>0 or c.character_id is not null);

  select jsonb_build_object(
    'npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'realm_label',n.realm_label,'identity',n.identity,'relation_stage','道侣','is_companion',true,
    'current_status',r.current_status,'latest_rumor',r.latest_rumor,'mood_label',ls.mood_label,'mood_detail',ls.mood_detail,'current_activity',ls.current_activity,'current_place',ls.current_place,
    'affinity',r.affinity,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'respect',r.respect,'bond_level',c.bond_level,'formed_at',c.formed_at
  ) into v_comp
  from public.tiandao_companions_v259 c join public.tiandao_npcs_v259 n on n.id=c.npc_id join public.tiandao_relations_v259 r on r.character_id=c.character_id and r.npc_id=c.npc_id
  left join public.tiandao_life_state_v260 ls on ls.character_id=c.character_id and ls.npc_id=c.npc_id
  where c.character_id=v_char and c.status='active';

  select jsonb_build_object(
    'known',(select count(*) from public.tiandao_relations_v259 where character_id=v_char and known_level in('acquainted','familiar','close')),
    'heard',(select count(*) from public.tiandao_relations_v259 where character_id=v_char and known_level='heard'),
    'encounters',(select count(*) from public.tiandao_encounters_v259 where character_id=v_char and status='pending' and expires_at>clock_timestamp()),
    'romance',(select count(*) from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id where r.character_id=v_char and n.romanceable and (r.affinity>=10 or r.romance>0)),
    'unread',(select count(*) from public.tiandao_inbox_v260 where character_id=v_char and status='unread' and expires_at>clock_timestamp()),
    'active_stories',(select count(*) from public.tiandao_story_threads_v260 where character_id=v_char and status='active'),
    'active_promises',(select count(*) from public.tiandao_promises_v260 where character_id=v_char and status='active')
  ) into v_counts;
  return jsonb_build_object('status','ok','people',v_people,'encounters',v_enc,'inbox',v_inbox,'stories',v_stories,'romance',v_rom,'companion',v_comp,'counts',v_counts,'build','TIANDAO_LIVING_PEOPLE_V260');
end $$;

create or replace function public.get_tiandao_person_detail_v1(p_npc_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;ls public.tiandao_life_state_v260%rowtype;t public.tiandao_story_threads_v260%rowtype;p public.tiandao_promises_v260%rowtype;v_comp boolean;v_mem jsonb;v_minor jsonb;v_stage text;v_can boolean;v_hint text;v_secret text;v_profile jsonb;
begin
  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
  select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=n.id;if r.npc_id is null or r.known_level='unknown' then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
  perform public.tiandao_refresh_person_life_v260(v_char,n.id);
  perform public.tiandao_spawn_story_v260(v_char,n.id,false);
  select * into ls from public.tiandao_life_state_v260 where character_id=v_char and npc_id=n.id;
  select * into t from public.tiandao_story_threads_v260 where character_id=v_char and npc_id=n.id and status='active' order by started_at desc limit 1;
  if t.id is not null then select * into p from public.tiandao_promises_v260 where character_id=v_char and thread_id=t.id and status='active' order by created_at desc limit 1;end if;
  select exists(select 1 from public.tiandao_companions_v259 where character_id=v_char and npc_id=n.id and status='active') into v_comp;
  v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,v_comp);
  v_can:=n.romanceable and not v_comp and r.affinity>=(select confess_affinity_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.trust>=(select confess_trust_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.intimacy>=(select confess_intimacy_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.romance>=(select confess_romance_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.hatred<25;
  select coalesce(jsonb_agg(jsonb_build_object('content',m.content,'memory_type',m.memory_type,'importance',m.importance,'created_at',m.created_at) order by m.importance desc,m.created_at desc),'[]'::jsonb) into v_mem
  from (
    select * from (
      select distinct on (regexp_replace(lower(content),'\s+','','g')) *
      from public.tiandao_memories_v259
      where character_id=v_char and npc_id=n.id and public_to_player and importance>=2
      order by regexp_replace(lower(content),'\s+','','g'),created_at desc
    ) d order by importance desc,created_at desc limit 12
  ) m;
  select coalesce(jsonb_agg(jsonb_build_object('content',m.content,'memory_type',m.memory_type,'created_at',m.created_at) order by m.created_at desc),'[]'::jsonb) into v_minor
  from (
    select * from (
      select distinct on (regexp_replace(lower(content),'\s+','','g')) *
      from public.tiandao_memories_v259
      where character_id=v_char and npc_id=n.id and public_to_player and importance=1
      order by regexp_replace(lower(content),'\s+','','g'),created_at desc
    ) d order by created_at desc limit 5
  ) m;
  v_hint:=case when coalesce(n.personality->>'gift_preference','')='无' then case when r.trust>=20 then 'TA并不喜欢用礼物衡量关系。' else '你还不太清楚TA对礼物的态度。' end when r.trust>=45 or r.interaction_count>=8 then '你已经知道：TA似乎偏爱“'||coalesce(n.personality->>'gift_preference','实用之物')||'”一类的东西。' when r.trust>=20 then '相处下来，你开始能看出TA对礼物的偏好。' else '你还不太了解TA真正喜欢什么。' end;
  v_secret:=case when r.trust>=75 and r.intimacy>=55 then n.private_goal when r.trust>=50 then 'TA似乎有一件长期放在心里的事，只是还没有完全告诉你。' else '' end;
  v_profile:=jsonb_build_object('affection',public.tiandao_relation_band_v260(r.affinity,'affinity'),'trust',public.tiandao_relation_band_v260(r.trust,'trust'),'intimacy',public.tiandao_relation_band_v260(r.intimacy,'intimacy'),'respect',public.tiandao_relation_band_v260(r.respect,'respect'),'gratitude',public.tiandao_relation_band_v260(r.gratitude,'gratitude'),'tension',case when r.hatred>=40 then '明显有怨' when r.fear>=40 then '对你有所畏惧' when r.hatred>=15 then '心里还有疙瘩' else '没有明显敌意' end,'promise_kept',r.promise_kept,'promise_broken',r.promise_broken);
  return jsonb_build_object(
    'npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'gender',n.gender,'realm_label',n.realm_label,'identity',n.identity,'element',n.element,'public_profile',n.public_profile,
    'known_level',r.known_level,'relation_stage',v_stage,'affinity',r.affinity,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'respect',r.respect,
    'attitude_text',public.tiandao_public_attitude_v259(v_stage),'relationship_profile',v_profile,'current_status',r.current_status,'latest_rumor',r.latest_rumor,
    'life',case when ls.npc_id is null then '{}'::jsonb else jsonb_build_object('mood_code',ls.mood_code,'mood_label',ls.mood_label,'mood_detail',ls.mood_detail,'current_activity',ls.current_activity,'current_place',ls.current_place,'current_need',ls.current_need,'current_topic',ls.current_topic,'life_phase',ls.life_phase) end,
    'active_story',case when t.id is null then null else jsonb_build_object('story_id',t.id,'title',t.title,'premise',t.premise,'stage',t.stage,'branch',t.branch,'current_summary',t.current_summary,'choices',t.choices,'expires_at',t.expires_at,'promise',case when p.id is null then null else jsonb_build_object('promise_id',p.id,'title',p.title,'due_at',p.due_at,'status',p.status) end) end,
    'gift_hint',v_hint,'known_secret',v_secret,'public_memories',v_mem,'recent_moments',v_minor,'is_companion',v_comp,'can_confess',v_can,
    'unread_count',(select count(*) from public.tiandao_inbox_v260 i where i.character_id=v_char and i.npc_id=n.id and i.status='unread' and i.expires_at>clock_timestamp()),
    'free_talk_enabled',(select free_talk_enabled from public.tiandao_people_settings_v259 where singleton_id=1),
    'interaction_costs',(select jsonb_build_object(
      'gift_practical',greatest(200,gift_spirit_stone_cost*6/10),
      'gift_cultivation',greatest(500,gift_spirit_stone_cost),
      'gift_elegant',greatest(800,gift_spirit_stone_cost*2),
      'gift_rare',greatest(1500,gift_spirit_stone_cost*5)
    ) from public.tiandao_people_settings_v259 where singleton_id=1)
  );
end $$;

create or replace function public.tiandao_people_mark_read_v260(p_message_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();v_row public.tiandao_inbox_v260%rowtype;
begin
  update public.tiandao_inbox_v260 set status=case when status='unread' then 'read' else status end,read_at=coalesce(read_at,clock_timestamp()) where id=p_message_id and character_id=v_char and status in('unread','read') returning * into v_row;
  if v_row.id is null then raise exception 'TIANDAO_INBOX_NOT_FOUND';end if;
  return jsonb_build_object('status','ok','message_id',v_row.id,'npc_id',v_row.npc_id);
end $$;

-- ==================== FALLBACK PERSONALITY ====================
create or replace function public.server_personality_v1(p_context jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_name text:=coalesce(p_context#>>'{npc,name}','TA');v_action text:=coalesce(p_context->>'action','talk');v_kind text:=coalesce(p_context->>'request_kind','interaction');v_mood text:=coalesce(p_context#>>'{life,mood_label}','');v_story text:=coalesce(p_context#>>'{active_story,title}','');v_player_msg text:=left(coalesce(p_context->>'player_message',''),180);v_dialogue text;v_goal text;v_intent text;v_reason text;v_decision text:='neutral';
begin
  if v_kind='romance' then
    v_dialogue:=v_name||'认真听完了你的话，没有让这一刻被轻描淡写地带过。';v_goal:='根据真实关系与共同经历判断这份心意';v_intent:='谨慎回应表白';v_reason:='本地人格兜底只提供语言与意图，最终关系由服务端规则审核。';
  elsif v_action like 'talk:free%' then
    v_dialogue:=case when v_player_msg<>'' then v_name||'听你说完，想了想才回应：“我记住你刚才说的这些了。”' else v_name||'看着你，等你把想说的话说完。' end;v_goal:='延续自然交流';v_intent:='回应玩家自由交谈';v_reason:='Cloudflare不可用，使用安全的自由交谈兜底。';
  elsif v_action like 'talk:%' then v_dialogue:=v_name||'和你聊了一会。'||case when v_mood<>'' then '今天的TA看起来'||v_mood||'。' else '' end;v_goal:='保持自然来往';v_intent:='继续对话';v_reason:='Cloudflare不可用，使用确定性对话兜底。';
  elsif v_action like 'gift:%' then v_dialogue:=v_name||'看了看你准备的东西，没有立刻把心意换算成一句客套话。';v_goal:='按自己的偏好判断这份礼物';v_intent:='对赠礼作出自然反应';v_reason:='礼物效果由服务端偏好规则决定。';
  elsif v_action like 'meeting:%' then v_dialogue:=v_name||'答应和你一起出去走一段。路上没有刻意找话题，却也不显得尴尬。';v_goal:='通过共同经历加深理解';v_intent:='参与相约';v_reason:='相约关系变化由服务端固定规则决定。';
  elsif v_action like 'story:%' then v_dialogue:=v_name||'在“'||coalesce(nullif(v_story,''),'这件事')||'”上听见了你的选择，神情有了一点变化。';v_goal:='继续自己的事件线';v_intent:='根据玩家选择推进个人经历';v_reason:='人生事件推进由服务端阶段规则控制。';
  elsif v_action like 'inbox:%' then v_dialogue:=v_name||'很快看到了你的回应。哪怕只是几句话，也比一直没有回音更真实。';v_goal:='维持主动联系';v_intent:='回应玩家回信';v_reason:='主动来信状态由服务端控制。';
  elsif v_kind='encounter' then v_dialogue:=v_name||'与你在这段缘遇中真正打了照面。';v_goal:='判断这次相识是否值得继续';v_intent:='回应缘遇';v_reason:='缘遇状态由服务端规则处理。';
  elsif v_kind='companion' then v_dialogue:=v_name||'以道侣的身份回应了你。';v_goal:='经营共同生活';v_intent:='回应道侣互动';v_reason:='道侣数值仍由服务端规则处理。';
  else v_dialogue:=v_name||'暂时没有多说什么。';v_goal:='继续自己的修行与人生目标';v_intent:='根据当前关系保持自然往来';v_reason:='Cloudflare不可用，使用确定性的 server_personality_v1。';end if;
  return jsonb_build_object('proposal',jsonb_build_object('decision',v_decision,'dialogue',left(v_dialogue,500),'next_goal',left(v_goal,240),'action_intent',left(v_intent,240),'rationale',left(v_reason,360)),'engine','server_personality_v1');
exception when others then
  return jsonb_build_object('proposal',jsonb_build_object('decision','neutral','dialogue',v_name||'暂时没有多说什么。','next_goal','继续当前目标','action_intent','保持谨慎','rationale','本地人格兜底异常后的最小安全响应'),'engine','server_personality_v1');
end $$;

-- ==================== AI PREPARE ====================
create or replace function public.tiandao_ai_prepare_v259(
  p_user_id uuid,p_request_kind text,p_npc_id uuid,p_action text,p_message text default '',p_encounter_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_char uuid;s public.tiandao_people_settings_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;
  e public.tiandao_encounters_v259%rowtype;c public.tiandao_companions_v259%rowtype;t public.tiandao_story_threads_v260%rowtype;i public.tiandao_inbox_v260%rowtype;ls public.tiandao_life_state_v260%rowtype;
  v_last timestamptz;v_cd int;v_context jsonb;v_mem jsonb;v_world jsonb:='[]'::jsonb;v_ai_state jsonb:='{}'::jsonb;v_req uuid:=gen_random_uuid();v_existing uuid;v_family text;v_ref uuid;
begin
  if p_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  select id into v_char from public.player_characters where user_id=p_user_id and status in('active','secluded','missing') order by created_at desc limit 1;
  if v_char is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not s.enabled then raise exception 'TIANDAO_DISABLED';end if;
  if p_request_kind not in('interaction','romance','encounter','companion') then raise exception 'TIANDAO_AI_REQUEST_KIND_INVALID';end if;
  p_action:=left(trim(coalesce(p_action,'')),60);p_message:=left(trim(coalesce(p_message,'')),300);v_family:=split_part(p_action,':',1);

  if p_request_kind='encounter' then
    if not s.encounters_enabled then raise exception 'TIANDAO_ENCOUNTERS_DISABLED';end if;
    select * into e from public.tiandao_encounters_v259 where id=p_encounter_id and character_id=v_char;
    if e.id is null then raise exception 'TIANDAO_ENCOUNTER_NOT_FOUND';end if;if e.status<>'pending' then raise exception 'TIANDAO_ENCOUNTER_ALREADY_RESOLVED';end if;if e.expires_at<=clock_timestamp() then raise exception 'TIANDAO_ENCOUNTER_EXPIRED';end if;
    if p_action not in('approach','accept','observe','leave') then raise exception 'TIANDAO_ENCOUNTER_ACTION_INVALID';end if;p_npc_id:=e.npc_id;
  elsif p_request_kind='companion' then
    if not s.companion_enabled then raise exception 'TIANDAO_COMPANION_DISABLED';end if;
    if v_family not in('message','gift','meeting') and p_action not in('joint_cultivation','protect') then raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
    if v_family='message' and p_action not in('message','message:free') then raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
    if v_family='gift' and p_action not in('gift:practical','gift:cultivation','gift:elegant','gift:rare') then raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
    if v_family='meeting' and p_action not in('meeting:market','meeting:teahouse','meeting:mountain','meeting:practice','meeting:travel') then raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
    if v_family='message' and p_action='message:free' and (not s.free_talk_enabled or length(p_message)<1) then raise exception 'TIANDAO_FREE_TALK_INVALID';end if;
    select * into c from public.tiandao_companions_v259 where character_id=v_char and status='active';if c.character_id is null then raise exception 'TIANDAO_COMPANION_NOT_FOUND';end if;
    if c.last_action_at is not null and c.last_action_at+make_interval(secs=>s.companion_action_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_COMPANION_ACTION_COOLDOWN';end if;p_npc_id:=c.npc_id;
  else
    select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
    select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=n.id;if r.npc_id is null or r.known_level='unknown' then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
    if p_request_kind='interaction' then
      if not s.interactions_enabled then raise exception 'TIANDAO_INTERACTIONS_DISABLED';end if;
      if v_family not in('talk','gift','meeting','story','inbox') then raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
      if v_family='talk' and p_action not in('talk:ask_current','talk:listen','talk:share_story','talk:tease','talk:seek_advice','talk:free') then raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
      if v_family='gift' and p_action not in('gift:practical','gift:cultivation','gift:elegant','gift:rare') then raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
      if v_family='meeting' and p_action not in('meeting:market','meeting:teahouse','meeting:mountain','meeting:practice','meeting:travel') then raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
      if p_action='talk:free' and (not s.free_talk_enabled or length(p_message)<1) then raise exception 'TIANDAO_FREE_TALK_INVALID';end if;
      if v_family in('talk','gift','meeting') then
        select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=v_char and npc_id=n.id and (action_code=v_family or action_code like v_family||':%' or action_code like 'companion_'||v_family||'%');
        v_cd:=case v_family when 'talk' then s.talk_cooldown_seconds when 'gift' then s.gift_cooldown_seconds else s.meeting_cooldown_seconds end;
        if v_last is not null and v_last+make_interval(secs=>v_cd)>clock_timestamp() then raise exception 'TIANDAO_INTERACTION_COOLDOWN';end if;
      elsif v_family='story' then
        begin v_ref:=p_message::uuid;exception when others then raise exception 'TIANDAO_STORY_REF_INVALID';end;
        select * into t from public.tiandao_story_threads_v260 where id=v_ref and character_id=v_char and npc_id=n.id and status='active' for update;
        if t.id is null then raise exception 'TIANDAO_STORY_NOT_FOUND';end if;if t.expires_at<=clock_timestamp() then raise exception 'TIANDAO_STORY_EXPIRED';end if;
        if not exists(select 1 from jsonb_array_elements(t.choices) c0 where c0->>'code'=p_action) then raise exception 'TIANDAO_STORY_CHOICE_INVALID';end if;
      else
        begin v_ref:=p_message::uuid;exception when others then raise exception 'TIANDAO_INBOX_REF_INVALID';end;
        select * into i from public.tiandao_inbox_v260 where id=v_ref and character_id=v_char and npc_id=n.id and status in('unread','read') for update;
        if i.id is null then raise exception 'TIANDAO_INBOX_NOT_FOUND';end if;if i.expires_at<=clock_timestamp() then raise exception 'TIANDAO_INBOX_EXPIRED';end if;
        if not exists(select 1 from jsonb_array_elements(i.actions) a0 where a0->>'code'=p_action) then raise exception 'TIANDAO_INBOX_ACTION_INVALID';end if;
      end if;
    else
      if not s.romance_enabled then raise exception 'TIANDAO_ROMANCE_DISABLED';end if;if p_action<>'confess' then raise exception 'TIANDAO_ROMANCE_ACTION_INVALID';end if;if length(p_message)<1 then raise exception 'TIANDAO_CONFESSION_MESSAGE_INVALID';end if;if not n.romanceable then raise exception 'TIANDAO_ROMANCE_NPC_INVALID';end if;if r.known_level not in('acquainted','familiar','close') then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
      if r.affinity<s.confess_affinity_min or r.trust<s.confess_trust_min or r.intimacy<s.confess_intimacy_min or r.romance<s.confess_romance_min or r.hatred>=25 then raise exception 'TIANDAO_CONFESSION_REQUIREMENTS';end if;
      select npc_id into v_existing from public.tiandao_companions_v259 where character_id=v_char and status='active';if v_existing is not null and v_existing<>n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';end if;
      select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=v_char and npc_id=n.id and action_code='confess';if v_last is not null and v_last+make_interval(secs=>s.confess_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_CONFESSION_COOLDOWN';end if;
    end if;
  end if;

  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
  perform public.tiandao_ensure_relation_v259(v_char,n.id,case when p_request_kind='encounter' then 'heard' else 'unknown' end);
  perform public.tiandao_refresh_person_life_v260(v_char,n.id);
  select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=n.id;
  select * into ls from public.tiandao_life_state_v260 where character_id=v_char and npc_id=n.id;
  if t.id is null then select * into t from public.tiandao_story_threads_v260 where character_id=v_char and npc_id=n.id and status='active' order by started_at desc limit 1;end if;
  if i.id is null and v_family='inbox' then begin v_ref:=p_message::uuid;select * into i from public.tiandao_inbox_v260 where id=v_ref and character_id=v_char;exception when others then null;end;end if;
  select coalesce(jsonb_agg(jsonb_build_object('type',m.memory_type,'content',m.content,'importance',m.importance,'created_at',m.created_at) order by m.importance desc,m.created_at desc),'[]'::jsonb) into v_mem from (select * from public.tiandao_memories_v259 where character_id=v_char and npc_id=n.id order by importance desc,created_at desc limit 12) m;
  if to_regclass('public.jiuxiao_world_events') is not null then begin execute 'select coalesce(jsonb_agg(jsonb_build_object(''type'',event_type,''title'',title,''content'',content,''level'',event_level,''created_at'',created_at) order by created_at desc),''[]''::jsonb) from (select event_type,title,content,event_level,created_at from public.jiuxiao_world_events order by created_at desc limit 5) x' into v_world;exception when others then v_world:='[]'::jsonb;end;end if;
  select coalesce(jsonb_build_object('next_goal',a.next_goal,'action_intent',a.action_intent,'last_dialogue',a.last_dialogue,'last_engine',a.last_engine,'updated_at',a.updated_at),'{}'::jsonb) into v_ai_state from public.tiandao_ai_state_v259 a where a.character_id=v_char and a.npc_id=n.id;v_ai_state:=coalesce(v_ai_state,'{}'::jsonb);
  v_context:=jsonb_build_object(
    'request_kind',p_request_kind,'action',p_action,'player_message',p_message,'server_time',clock_timestamp(),
    'player',jsonb_build_object('character_id',v_char,'name',(select name from public.player_characters where id=v_char)),
    'npc',jsonb_build_object('npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'gender',n.gender,'age',n.age,'realm_label',n.realm_label,'identity',n.identity,'element',n.element,'public_profile',n.public_profile,'personality',n.personality,'private_goal',n.private_goal,'ai_notes',n.ai_notes,'romance_threshold',n.romance_threshold),
    'relation',jsonb_build_object('known_level',r.known_level,'affinity',r.affinity,'gratitude',r.gratitude,'hatred',r.hatred,'fear',r.fear,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'respect',r.respect,'promise_kept',r.promise_kept,'promise_broken',r.promise_broken,'interaction_count',r.interaction_count,'current_status',r.current_status,'last_action',r.last_action),
    'life',case when ls.npc_id is null then '{}'::jsonb else jsonb_build_object('mood_code',ls.mood_code,'mood_label',ls.mood_label,'mood_detail',ls.mood_detail,'current_activity',ls.current_activity,'current_place',ls.current_place,'current_need',ls.current_need,'current_topic',ls.current_topic,'life_phase',ls.life_phase) end,
    'active_story',case when t.id is null then null else jsonb_build_object('story_id',t.id,'title',t.title,'premise',t.premise,'stage',t.stage,'branch',t.branch,'current_summary',t.current_summary,'choices',t.choices,'expires_at',t.expires_at) end,
    'inbox_message',case when i.id is null then null else jsonb_build_object('message_id',i.id,'title',i.title,'content',i.content,'context',i.context) end,
    'memories',v_mem,'previous_ai_state',v_ai_state,'world_events',v_world,
    'hard_rules',jsonb_build_object('ai_may_modify_state',false,'ai_may_change_resources',false,'ai_may_decide_combat',false,'ai_may_force_relationship',false,'server_rules_are_authoritative',true)
  );
  insert into public.tiandao_ai_requests_v259(request_id,user_id,character_id,npc_id,request_kind,action_code,player_message,encounter_id,context_snapshot)
  values(v_req,p_user_id,v_char,n.id,p_request_kind,p_action,p_message,p_encounter_id,v_context);
  return jsonb_build_object('status','prepared','request_id',v_req,'ai',jsonb_build_object('enabled',s.ai_enabled,'model',s.ai_model,'timeout_ms',s.ai_timeout_ms,'max_tokens',s.ai_max_tokens),'context',v_context);
end $$;

-- ==================== AI APPLY ====================
create or replace function public.tiandao_ai_apply_v259(
  p_user_id uuid,p_request_id uuid,p_proposal jsonb,p_engine text,p_model text,p_latency_ms integer default 0,p_failure_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  q public.tiandao_ai_requests_v259%rowtype;s public.tiandao_people_settings_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;e public.tiandao_encounters_v259%rowtype;c public.tiandao_companions_v259%rowtype;t public.tiandao_story_threads_v260%rowtype;i public.tiandao_inbox_v260%rowtype;p public.tiandao_promises_v260%rowtype;
  v_last timestamptz;v_cd int;v_existing uuid;v_player text:='某位修士';v_decision text;v_ai_decision text;v_content text;v_reason text;v_next_goal text;v_intent text;v_family text;v_sub text;v_ref uuid;
  v_score numeric;v_threshold numeric;v_jitter int;da int:=0;dg int:=0;dt int:=0;di int:=0;dr int:=0;dres int:=0;v_cost bigint:=0;v_stage text;v_applied jsonb;v_pref text;v_match boolean:=false;v_story_resolved boolean:=false;v_gift_accepted boolean:=true;
begin
  if p_user_id is null or p_request_id is null then raise exception 'AUTH_REQUIRED';end if;
  select * into q from public.tiandao_ai_requests_v259 where request_id=p_request_id for update;
  if q.request_id is null or q.user_id<>p_user_id then raise exception 'TIANDAO_AI_REQUEST_NOT_FOUND';end if;if q.status<>'prepared' then raise exception 'TIANDAO_AI_REQUEST_ALREADY_APPLIED';end if;if q.expires_at<=clock_timestamp() then update public.tiandao_ai_requests_v259 set status='expired' where request_id=q.request_id;raise exception 'TIANDAO_AI_REQUEST_EXPIRED';end if;
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  select * into n from public.tiandao_npcs_v259 where id=q.npc_id and enabled;if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
  select * into r from public.tiandao_relations_v259 where character_id=q.character_id and npc_id=n.id for update;if r.npc_id is null then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
  v_ai_decision:=lower(coalesce(p_proposal->>'decision','neutral'));if v_ai_decision not in('accept','defer','reject','neutral') then v_ai_decision:='neutral';end if;
  v_content:=left(trim(coalesce(p_proposal->>'dialogue','')),500);v_reason:=left(trim(coalesce(p_proposal->>'rationale','')),360);v_next_goal:=left(trim(coalesce(p_proposal->>'next_goal','')),240);v_intent:=left(trim(coalesce(p_proposal->>'action_intent','')),240);v_family:=split_part(q.action_code,':',1);v_sub:=split_part(q.action_code,':',2);

  if q.request_kind='interaction' then
    if not s.enabled or not s.interactions_enabled then raise exception 'TIANDAO_INTERACTIONS_DISABLED';end if;
    if v_family in('talk','gift','meeting') then
      select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=q.character_id and npc_id=n.id and (action_code=v_family or action_code like v_family||':%' or action_code like 'companion_'||v_family||'%');
      v_cd:=case v_family when 'talk' then s.talk_cooldown_seconds when 'gift' then s.gift_cooldown_seconds else s.meeting_cooldown_seconds end;if v_last is not null and v_last+make_interval(secs=>v_cd)>clock_timestamp() then raise exception 'TIANDAO_INTERACTION_COOLDOWN';end if;
    end if;

    if v_family='talk' then
      if q.action_code='talk:ask_current' then da:=2;dt:=2;di:=1;
      elsif q.action_code='talk:listen' then da:=2;dt:=3;di:=2;
      elsif q.action_code='talk:share_story' then da:=3;dt:=2;di:=2;
      elsif q.action_code='talk:tease' then da:=case when coalesce(n.personality->>'temperament','steady') in('stern','reserved','cool') then 1 else 3 end;dt:=1;di:=case when r.interaction_count>=3 then 1 else 0 end;
      elsif q.action_code='talk:seek_advice' then da:=1;dt:=2;dres:=3;
      elsif q.action_code='talk:free' then if not s.free_talk_enabled or length(q.player_message)<1 then raise exception 'TIANDAO_FREE_TALK_INVALID';end if;da:=1;dt:=2;di:=case when r.trust>=30 then 1 else 0 end;
      else raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
      if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'与你聊了一会。');end if;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,case when q.action_code='talk:free' and length(q.player_message)>=20 then 2 else 1 end,true,jsonb_build_object('player_message',case when q.action_code='talk:free' then q.player_message else null end,'ai_engine',p_engine));

    elsif v_family='gift' then
      v_pref:=public.tiandao_gift_category_v260(n.personality->>'gift_preference');
      if v_pref='none' then v_gift_accepted:=false;v_cost:=0;dres:=1;
      else
        v_cost:=case q.action_code when 'gift:practical' then greatest(200,s.gift_spirit_stone_cost*6/10) when 'gift:cultivation' then greatest(500,s.gift_spirit_stone_cost) when 'gift:elegant' then greatest(800,s.gift_spirit_stone_cost*2) when 'gift:rare' then greatest(1500,s.gift_spirit_stone_cost*5) else 0 end;
        if v_cost>0 then perform public.tianxu_inventory_adjust_v255(q.character_id,'spirit_stone',-v_cost);end if;
        v_match=(v_pref=v_sub);
        da:=case when v_match then 6 when q.action_code='gift:rare' and v_pref<>'rare' then 2 else 3 end;dg:=case when v_match then 5 else 2 end;dt:=case when v_match then 2 else 0 end;dres:=case when v_match then 2 else 0 end;dr:=case when n.romanceable and v_match then 2 when n.romanceable then 0 else 0 end;
      end if;
      if v_content='' then v_content:=case when not v_gift_accepted then n.name||'没有收下礼物，只说彼此相处不必靠这个。' when v_match then n.name||'明显看出了你是认真挑过的，收下时比平时多说了几句。' else n.name||'收下了你的心意，但这并不是TA最偏爱的那一类。' end;end if;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,2,true,jsonb_build_object('gift_category',v_sub,'preference_match',v_match,'accepted',v_gift_accepted,'spirit_stone_cost',v_cost,'ai_engine',p_engine));

    elsif v_family='meeting' then
      v_match:=case
        when q.action_code='meeting:market' and coalesce(n.personality->>'temperament','') in('shrewd','bright') then true
        when q.action_code='meeting:teahouse' and coalesce(n.personality->>'temperament','') in('calm','gentle','warm','quiet','reserved') then true
        when q.action_code='meeting:mountain' and coalesce(n.personality->>'temperament','') in('free','mysterious','bright') then true
        when q.action_code='meeting:practice' and coalesce(n.personality->>'temperament','') in('focused','stern','bold','fiery','rational') then true
        when q.action_code='meeting:travel' and coalesce(n.personality->>'value_anchor','') in('freedom','adventure','journey','wonder') then true else false end;
      da:=3+case when v_match then 2 else 0 end;dt:=2+case when v_match then 1 else 0 end;di:=3+case when v_match then 2 else 0 end;dr:=case when n.romanceable then 2+case when v_match then 1 else 0 end else 0 end;dres:=case when v_match then 1 else 0 end;
      if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'和你一起走了一段。');end if;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,3,true,jsonb_build_object('meeting',v_sub,'preference_match',v_match,'ai_engine',p_engine));

    elsif v_family='story' then
      begin v_ref:=q.player_message::uuid;exception when others then raise exception 'TIANDAO_STORY_REF_INVALID';end;
      select * into t from public.tiandao_story_threads_v260 where id=v_ref and character_id=q.character_id and npc_id=n.id and status='active' for update;if t.id is null then raise exception 'TIANDAO_STORY_NOT_FOUND';end if;if not exists(select 1 from jsonb_array_elements(t.choices) c0 where c0->>'code'=q.action_code) then raise exception 'TIANDAO_STORY_CHOICE_INVALID';end if;
      if t.stage=1 then
        if q.action_code='story:offer_help' then dt:=2;di:=1;dres:=3;t.branch:='promised';insert into public.tiandao_promises_v260(character_id,npc_id,thread_id,promise_code,title,due_at) values(q.character_id,n.id,t.id,'story_help','答应帮'||n.name||'处理“'||t.title||'”',clock_timestamp()+make_interval(hours=>s.promise_hours)) on conflict do nothing;
        elsif q.action_code='story:listen' then dt:=3;di:=2;dres:=1;t.branch:='trusted';
        else dres:=3;t.branch:='space';end if;t.stage:=2;
      elsif t.stage=2 and t.branch='promised' then
        select * into p from public.tiandao_promises_v260 where character_id=q.character_id and thread_id=t.id and status='active' order by created_at desc limit 1 for update;
        if q.action_code='story:fulfill' then if p.id is not null then update public.tiandao_promises_v260 set status='fulfilled',resolved_at=clock_timestamp() where id=p.id;end if;dt:=5;dg:=3;di:=2;dres:=5;update public.tiandao_relations_v259 set promise_kept=promise_kept+1 where character_id=q.character_id and npc_id=n.id;
        elsif q.action_code='story:be_honest' then if p.id is not null then update public.tiandao_promises_v260 set status='cancelled',resolved_at=clock_timestamp() where id=p.id;end if;dt:=2;dres:=2;
        else if p.id is not null then update public.tiandao_promises_v260 set status='broken',resolved_at=clock_timestamp() where id=p.id;end if;da:=-2;dt:=-4;dres:=-6;update public.tiandao_relations_v259 set promise_broken=promise_broken+1 where character_id=q.character_id and npc_id=n.id;end if;t.stage:=3;
      elsif t.stage=2 then
        if q.action_code='story:ask_progress' then dt:=2;di:=2;elsif q.action_code='story:encourage' then da:=2;dt:=2;dres:=2;else dres:=1;end if;t.stage:=3;
      elsif t.stage=3 then
        if q.action_code='story:stand_with' then da:=2;dt:=4;di:=3;dres:=3;elsif q.action_code='story:advise' then dt:=2;dres:=4;else dt:=3;dres:=4;end if;t.stage:=4;
      elsif t.stage=4 then
        if q.action_code='story:celebrate' then da:=4;di:=4;dr:=case when n.romanceable then 2 else 0 end;
        elsif q.action_code='story:remember' then dt:=4;di:=3;dres:=2;else dres:=2;end if;t.stage:=5;v_story_resolved:=true;
      else raise exception 'TIANDAO_STORY_CHOICE_INVALID';end if;
      if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'把你的选择记在了这段经历里。');end if;
      if v_story_resolved then
        update public.tiandao_story_threads_v260 set stage=5,branch=t.branch,current_summary=v_content,choices='[]'::jsonb,status='resolved',last_advanced_at=clock_timestamp(),resolved_at=clock_timestamp() where id=t.id;
        update public.tiandao_life_state_v260 set life_phase=least(99,life_phase+1),updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
        perform public.tiandao_add_memory_v259(q.character_id,n.id,'story_resolved','“'||t.title||'”终于走到了结果。'||v_content,5,true,jsonb_build_object('story_id',t.id,'branch',t.branch,'ai_engine',p_engine));
      else
        update public.tiandao_story_threads_v260 set stage=t.stage,branch=t.branch,current_summary=v_content,choices=public.tiandao_story_choices_v260(t.stage,t.branch),last_advanced_at=clock_timestamp(),expires_at=clock_timestamp()+make_interval(hours=>s.story_expire_hours) where id=t.id;
        perform public.tiandao_add_memory_v259(q.character_id,n.id,'story_step','在“'||t.title||'”这件事上，你作出了自己的选择。'||v_content,3,true,jsonb_build_object('story_id',t.id,'stage',t.stage,'branch',t.branch,'ai_engine',p_engine));
      end if;

    elsif v_family='inbox' then
      begin v_ref:=q.player_message::uuid;exception when others then raise exception 'TIANDAO_INBOX_REF_INVALID';end;
      select * into i from public.tiandao_inbox_v260 where id=v_ref and character_id=q.character_id and npc_id=n.id and status in('unread','read') for update;if i.id is null then raise exception 'TIANDAO_INBOX_NOT_FOUND';end if;
      if q.action_code='inbox:reply' then da:=1;dt:=2;di:=1;update public.tiandao_inbox_v260 set status='resolved',read_at=coalesce(read_at,clock_timestamp()),resolved_at=clock_timestamp() where id=i.id;
      elsif q.action_code='inbox:accept' then da:=2;dt:=2;di:=2;update public.tiandao_inbox_v260 set status='resolved',read_at=coalesce(read_at,clock_timestamp()),resolved_at=clock_timestamp() where id=i.id;
      elsif q.action_code='inbox:later' then update public.tiandao_inbox_v260 set status='read',read_at=coalesce(read_at,clock_timestamp()) where id=i.id;
      else raise exception 'TIANDAO_INBOX_ACTION_INVALID';end if;
      if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'看到了你的回应。');end if;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,case when q.action_code='inbox:accept' then 2 else 1 end,true,jsonb_build_object('message_id',i.id,'ai_engine',p_engine));
    else raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;

    update public.tiandao_relations_v259 set
      known_level=case when known_level in('unknown','heard') then 'acquainted' when known_level='acquainted' and interaction_count>=4 then 'familiar' when known_level='familiar' and interaction_count>=12 then 'close' else known_level end,
      affinity=least(100,greatest(-100,affinity+da)),gratitude=least(100,greatest(0,gratitude+dg)),trust=least(100,greatest(0,trust+dt)),intimacy=least(100,greatest(0,intimacy+di)),romance=least(100,greatest(0,romance+dr)),respect=least(100,greatest(0,respect+dres)),interaction_count=interaction_count+1,last_interaction_at=clock_timestamp(),last_action=q.action_code,latest_rumor=v_content,current_status=case when v_family='story' then '你已经卷入TA正在经历的一件事。' when v_family='inbox' then 'TA最近主动联系过你。' else '你们最近仍有来往。' end,updated_at=clock_timestamp()
    where character_id=q.character_id and npc_id=n.id returning * into r;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,q.action_code,jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'spirit_stone_cost',v_cost,'gift_accepted',v_gift_accepted,'preference_match',v_match,'story_resolved',v_story_resolved),v_content);
    v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,exists(select 1 from public.tiandao_companions_v259 where character_id=q.character_id and npc_id=n.id and status='active'));
    v_decision:='neutral';v_applied:=jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'spirit_stone_cost',v_cost,'relation_stage',v_stage,'gift_accepted',v_gift_accepted,'preference_match',v_match,'story_resolved',v_story_resolved);

  elsif q.request_kind='encounter' then
    if not s.enabled or not s.encounters_enabled then raise exception 'TIANDAO_ENCOUNTERS_DISABLED';end if;
    select * into e from public.tiandao_encounters_v259 where id=q.encounter_id and character_id=q.character_id for update;if e.id is null then raise exception 'TIANDAO_ENCOUNTER_NOT_FOUND';end if;if e.status<>'pending' then raise exception 'TIANDAO_ENCOUNTER_ALREADY_RESOLVED';end if;if e.expires_at<=clock_timestamp() then raise exception 'TIANDAO_ENCOUNTER_EXPIRED';end if;
    if q.action_code in('approach','accept') then da:=5;dt:=2;di:=1;dres:=1;dr:=case when n.romanceable then 1 else 0 end;elsif q.action_code='observe' then da:=1;dt:=1;dres:=1;elsif q.action_code<>'leave' then raise exception 'TIANDAO_ENCOUNTER_ACTION_INVALID';end if;
    if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),'这段缘遇有了新的结果。');end if;
    update public.tiandao_relations_v259 set known_level=case when q.action_code in('approach','accept') and known_level in('unknown','heard') then 'acquainted' else known_level end,affinity=least(100,greatest(-100,affinity+da)),trust=least(100,greatest(0,trust+dt)),intimacy=least(100,greatest(0,intimacy+di)),romance=least(100,greatest(0,romance+dr)),respect=least(100,greatest(0,respect+dres)),latest_rumor=v_content,current_status=case when q.action_code in('approach','accept') then '你们已经正式相识。' else current_status end,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id returning * into r;
    update public.tiandao_encounters_v259 set status='resolved',resolved_action=q.action_code,outcome=v_content,resolved_at=clock_timestamp() where id=e.id;
    if q.action_code in('approach','accept') then perform public.tiandao_add_memory_v259(q.character_id,n.id,'encounter',v_content,3,true,jsonb_build_object('encounter_id',e.id,'ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));end if;
    perform public.tiandao_refresh_person_life_v260(q.character_id,n.id);perform public.tiandao_spawn_story_v260(q.character_id,n.id,false);
    v_decision:='neutral';v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,false);v_applied:=jsonb_build_object('affinity',da,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'relation_stage',v_stage);

  elsif q.request_kind='romance' then
    if not s.enabled or not s.romance_enabled then raise exception 'TIANDAO_ROMANCE_DISABLED';end if;if q.action_code<>'confess' or length(q.player_message)<1 then raise exception 'TIANDAO_ROMANCE_ACTION_INVALID';end if;if not n.romanceable or r.known_level not in('acquainted','familiar','close') then raise exception 'TIANDAO_ROMANCE_NPC_INVALID';end if;
    if r.affinity<s.confess_affinity_min or r.trust<s.confess_trust_min or r.intimacy<s.confess_intimacy_min or r.romance<s.confess_romance_min or r.hatred>=25 then raise exception 'TIANDAO_CONFESSION_REQUIREMENTS';end if;
    select npc_id into v_existing from public.tiandao_companions_v259 where character_id=q.character_id and status='active';if v_existing is not null and v_existing<>n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';elsif v_existing=n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';end if;
    select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=q.character_id and npc_id=n.id and action_code='confess';if v_last is not null and v_last+make_interval(secs=>s.confess_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_CONFESSION_COOLDOWN';end if;
    v_jitter:=(mod(mod(hashtextextended(q.character_id::text||':'||n.id::text||':'||date_trunc('hour',clock_timestamp())::text,260),11)+11,11)::int)-5;
    v_score:=r.affinity*0.30+r.trust*0.28+r.intimacy*0.22+r.romance*0.30+r.gratitude*0.07+r.respect*0.08-r.hatred*0.55-r.fear*0.15+coalesce((n.personality->>'romance_openness')::numeric,50)*0.10+least(8,r.promise_kept*2)-least(10,r.promise_broken*3)+v_jitter;v_threshold:=n.romance_threshold;
    if v_score<v_threshold-10 then v_decision:='reject';elsif v_score<v_threshold and v_ai_decision='accept' then v_decision:='defer';elsif v_ai_decision in('accept','defer','reject') then v_decision:=v_ai_decision;elsif v_score>=v_threshold then v_decision:='defer';else v_decision:='reject';end if;
    if v_reason='' then v_reason:=case v_decision when 'accept' then 'AI提出接受，且通过服务端关系、守诺与分数规则审核。' when 'defer' then 'AI或服务端审核判断仍需更多共同经历。' else 'AI或服务端审核判断当前不接受。' end;end if;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,'confess',jsonb_build_object('score',v_score,'threshold',v_threshold,'ai_decision',v_ai_decision,'server_decision',v_decision),q.player_message);
    if v_decision='accept' then
      insert into public.tiandao_companions_v259(character_id,npc_id,status) values(q.character_id,n.id,'active') on conflict(character_id) do update set npc_id=excluded.npc_id,status='active',formed_at=clock_timestamp(),updated_at=clock_timestamp();
      if v_content='' then v_content:=n.name||'接受了你的心意。大道漫漫，你们从此以道侣之名同行。';end if;
      update public.tiandao_relations_v259 set known_level='close',affinity=greatest(affinity,80),trust=greatest(trust,70),intimacy=greatest(intimacy,70),romance=greatest(romance,85),respect=greatest(respect,60),current_status='你们已经正式结为道侣。',latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,'companion_formed',v_content,5,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));
      begin select name into v_player from public.player_characters where id=q.character_id;exception when others then v_player:='某位修士';end;perform public.tiandao_publish_world_event_v259('tiandao_companion_v260','仙缘既定',coalesce(nullif(v_player,''),'某位修士')||'与'||n.name||'因缘圆满，正式结为道侣。',3);
    elsif v_decision='defer' then if v_content='' then v_content:=n.name||'没有立刻拒绝，也没有草率答应，希望再多走一段路。';end if;update public.tiandao_relations_v259 set trust=least(100,trust+2),intimacy=least(100,intimacy+1),romance=least(100,romance+1),latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;perform public.tiandao_add_memory_v259(q.character_id,n.id,'confession_defer',v_content,4,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine));
    else if v_content='' then v_content:=n.name||'没有接受这份心意，但也没有让此前经历凭空消失。';end if;update public.tiandao_relations_v259 set romance=greatest(0,romance-5),latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;perform public.tiandao_add_memory_v259(q.character_id,n.id,'confession_reject',v_content,4,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine));end if;
    v_applied:=jsonb_build_object('ai_decision',v_ai_decision,'server_decision',v_decision,'score',v_score,'threshold',v_threshold,'companion_formed',(v_decision='accept'));

  elsif q.request_kind='companion' then
    if not s.enabled or not s.companion_enabled then raise exception 'TIANDAO_COMPANION_DISABLED';end if;select * into c from public.tiandao_companions_v259 where character_id=q.character_id and npc_id=n.id and status='active' for update;if c.character_id is null then raise exception 'TIANDAO_COMPANION_NOT_FOUND';end if;if c.last_action_at is not null and c.last_action_at+make_interval(secs=>s.companion_action_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_COMPANION_ACTION_COOLDOWN';end if;
    if q.action_code in('message','message:free') then dt:=2;di:=2;dr:=1;if q.action_code='message:free' and (not s.free_talk_enabled or length(q.player_message)<1) then raise exception 'TIANDAO_FREE_TALK_INVALID';end if;
    elsif v_family='gift' then
      if q.action_code not in('gift:practical','gift:cultivation','gift:elegant','gift:rare') then raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
      v_pref:=public.tiandao_gift_category_v260(n.personality->>'gift_preference');
      if v_pref='none' then v_gift_accepted:=false;v_cost:=0;dres:=1;
      else
        v_cost:=case q.action_code when 'gift:practical' then greatest(500,s.companion_gift_spirit_stone_cost/5) when 'gift:cultivation' then greatest(1000,s.companion_gift_spirit_stone_cost/2) when 'gift:elegant' then greatest(1500,s.companion_gift_spirit_stone_cost) when 'gift:rare' then greatest(3000,s.companion_gift_spirit_stone_cost*2) else 0 end;
        if v_cost>0 then perform public.tianxu_inventory_adjust_v255(q.character_id,'spirit_stone',-v_cost);end if;
        v_match=(v_pref=v_sub);da:=3+case when v_match then 2 else 0 end;dg:=3;di:=3;dr:=2+case when v_match then 1 else 0 end;dres:=1;
      end if;
    elsif v_family='meeting' then da:=3;dt:=3;di:=5;dr:=3;dres:=2;
    elsif q.action_code='joint_cultivation' then dt:=4;di:=5;dr:=3;dres:=2;
    elsif q.action_code='protect' then dt:=5;di:=3;dr:=2;dres:=4;
    else raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
    if v_content='' then v_content:=case when v_family='gift' and not v_gift_accepted then n.name||'没有收下礼物，只提醒你们之间不需要靠礼物证明什么。' else coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'回应了这次道侣互动。') end;end if;
    update public.tiandao_relations_v259 set affinity=least(100,affinity+da),gratitude=least(100,gratitude+dg),trust=least(100,trust+dt),intimacy=least(100,intimacy+di),romance=least(100,romance+dr),respect=least(100,respect+dres),known_level='close',current_status='你们以道侣之名继续各自修行，也彼此牵挂。',latest_rumor=v_content,last_interaction_at=clock_timestamp(),last_action='companion_'||q.action_code,interaction_count=interaction_count+1,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
    update public.tiandao_companions_v259 set last_action_at=clock_timestamp(),bond_level=least(10,bond_level+case when v_family='meeting' or q.action_code in('joint_cultivation','protect') then 1 else 0 end),updated_at=clock_timestamp() where character_id=q.character_id;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,'companion_'||q.action_code,jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'spirit_stone_cost',v_cost,'gift_accepted',v_gift_accepted,'preference_match',v_match),v_content);
    perform public.tiandao_add_memory_v259(q.character_id,n.id,'companion_'||q.action_code,v_content,case when q.action_code in('joint_cultivation','protect') or v_family='meeting' then 3 else 2 end,true,jsonb_build_object('ai_engine',p_engine,'player_message',case when q.action_code='message:free' then q.player_message else null end,'gift_accepted',v_gift_accepted,'preference_match',v_match));
    v_decision:='neutral';v_stage:='道侣';v_applied:=jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'respect',dres,'spirit_stone_cost',v_cost,'gift_accepted',v_gift_accepted,'preference_match',v_match);
  else raise exception 'TIANDAO_AI_REQUEST_KIND_INVALID';end if;

  insert into public.tiandao_ai_state_v259(character_id,npc_id,next_goal,action_intent,last_dialogue,last_engine,last_model,updated_at)
  values(q.character_id,n.id,left(coalesce(v_next_goal,''),240),left(coalesce(v_intent,''),240),left(coalesce(v_content,''),500),left(coalesce(p_engine,''),80),left(coalesce(p_model,''),160),clock_timestamp())
  on conflict(character_id,npc_id) do update set next_goal=coalesce(nullif(excluded.next_goal,''),public.tiandao_ai_state_v259.next_goal),action_intent=coalesce(nullif(excluded.action_intent,''),public.tiandao_ai_state_v259.action_intent),last_dialogue=coalesce(nullif(excluded.last_dialogue,''),public.tiandao_ai_state_v259.last_dialogue),last_engine=excluded.last_engine,last_model=excluded.last_model,updated_at=clock_timestamp();
  insert into public.tiandao_ai_decisions_v259(character_id,npc_id,request_id,decision_type,engine,model,decision,score,threshold,rationale,latency_ms,failure_reason,proposal,applied)
  values(q.character_id,n.id,q.request_id,q.request_kind||':'||q.action_code,left(coalesce(nullif(p_engine,''),'server_personality_v1'),80),left(coalesce(nullif(p_model,''),s.ai_model),160),coalesce(v_decision,'neutral'),v_score,v_threshold,left(coalesce(v_reason,''),600),greatest(0,coalesce(p_latency_ms,0)),left(coalesce(p_failure_reason,''),800),coalesce(p_proposal,'{}'::jsonb),coalesce(v_applied,'{}'::jsonb));
  update public.tiandao_ai_requests_v259 set status='applied',applied_at=clock_timestamp() where request_id=q.request_id;
  perform public.tiandao_refresh_person_life_v260(q.character_id,n.id);
  return jsonb_build_object('status','ok','content',v_content,'decision',coalesce(v_decision,'neutral'),'reason',v_reason,'relation_stage',v_stage,'spirit_stone_cost',v_cost,'engine',p_engine,'model',coalesce(nullif(p_model,''),s.ai_model),'ai_latency_ms',greatest(0,coalesce(p_latency_ms,0)),'ai_failure_reason',nullif(left(coalesce(p_failure_reason,''),800),''),'applied',v_applied);
end $$;

-- ==================== ADMIN9 ====================
create or replace function public.admin9_get_tiandao_people_v259()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_settings jsonb;v_npcs jsonb;v_rel jsonb;v_enc jsonb;v_comp jsonb;v_audit jsonb;v_ai jsonb;v_ai_runtime jsonb;v_life jsonb;v_story jsonb;v_inbox jsonb;
begin
  perform public.admin_whoami_v1();
  select to_jsonb(s) into v_settings from public.tiandao_people_settings_v259 s where singleton_id=1;
  select coalesce(jsonb_agg(to_jsonb(n) order by n.core_ai desc,n.romanceable desc,n.npc_code),'[]'::jsonb) into v_npcs from public.tiandao_npcs_v259 n;
  select coalesce(jsonb_agg(x.obj order by x.updated_at desc),'[]'::jsonb) into v_rel from(
    select r.updated_at,jsonb_build_object('character_id',r.character_id,'character_name',pc.name,'npc_id',r.npc_id,'npc_name',n.name,'known_level',r.known_level,'affinity',r.affinity,'gratitude',r.gratitude,'hatred',r.hatred,'fear',r.fear,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'respect',r.respect,'promise_kept',r.promise_kept,'promise_broken',r.promise_broken,'interaction_count',r.interaction_count,'private_goal',n.private_goal,'ai_notes',n.ai_notes,'updated_at',r.updated_at) obj
    from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id left join public.player_characters pc on pc.id=r.character_id order by r.updated_at desc limit 100
  ) x;
  select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) into v_enc from(select e.created_at,jsonb_build_object('id',e.id,'character_id',e.character_id,'character_name',pc.name,'npc_name',n.name,'title',e.title,'status',e.status,'resolved_action',e.resolved_action,'outcome',e.outcome,'created_at',e.created_at) obj from public.tiandao_encounters_v259 e join public.tiandao_npcs_v259 n on n.id=e.npc_id left join public.player_characters pc on pc.id=e.character_id order by e.created_at desc limit 100) x;
  select coalesce(jsonb_agg(jsonb_build_object('character_id',c.character_id,'character_name',pc.name,'npc_id',c.npc_id,'npc_name',n.name,'status',c.status,'bond_level',c.bond_level,'formed_at',c.formed_at) order by c.formed_at desc),'[]'::jsonb) into v_comp from public.tiandao_companions_v259 c join public.tiandao_npcs_v259 n on n.id=c.npc_id left join public.player_characters pc on pc.id=c.character_id;
  select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at desc),'[]'::jsonb) into v_audit from (select * from public.tiandao_admin_audit_v259 order by created_at desc limit 50) a;
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'request_id',d.request_id,'character_id',d.character_id,'character_name',pc.name,'npc_name',n.name,'decision_type',d.decision_type,'engine',d.engine,'model',d.model,'decision',d.decision,'latency_ms',d.latency_ms,'failure_reason',nullif(d.failure_reason,''),'rationale',d.rationale,'created_at',d.created_at) order by d.created_at desc),'[]'::jsonb) into v_ai from (select * from public.tiandao_ai_decisions_v259 order by created_at desc limit 50) d join public.tiandao_npcs_v259 n on n.id=d.npc_id left join public.player_characters pc on pc.id=d.character_id;
  select coalesce(jsonb_agg(jsonb_build_object('character_name',pc.name,'npc_name',n.name,'mood',l.mood_label,'activity',l.current_activity,'place',l.current_place,'need',l.current_need,'updated_at',l.updated_at) order by l.updated_at desc),'[]'::jsonb) into v_life from (select * from public.tiandao_life_state_v260 order by updated_at desc limit 100) l join public.tiandao_npcs_v259 n on n.id=l.npc_id left join public.player_characters pc on pc.id=l.character_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'character_name',pc.name,'npc_name',n.name,'title',t.title,'stage',t.stage,'branch',t.branch,'status',t.status,'summary',t.current_summary,'expires_at',t.expires_at,'started_at',t.started_at) order by t.last_advanced_at desc),'[]'::jsonb) into v_story from (select * from public.tiandao_story_threads_v260 order by last_advanced_at desc limit 100) t join public.tiandao_npcs_v259 n on n.id=t.npc_id left join public.player_characters pc on pc.id=t.character_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'character_name',pc.name,'npc_name',n.name,'title',i.title,'status',i.status,'created_at',i.created_at,'expires_at',i.expires_at) order by i.created_at desc),'[]'::jsonb) into v_inbox from (select * from public.tiandao_inbox_v260 order by created_at desc limit 100) i join public.tiandao_npcs_v259 n on n.id=i.npc_id left join public.player_characters pc on pc.id=i.character_id;
  select jsonb_build_object('configured',true,'enabled',s.ai_enabled,'model',s.ai_model,'fallback','server_personality_v1','last_engine',(select d.engine from public.tiandao_ai_decisions_v259 d order by d.created_at desc limit 1),'status',coalesce((select case when d.engine='cloudflare_workers_ai' then 'Cloudflare' else '本地Fallback' end from public.tiandao_ai_decisions_v259 d order by d.created_at desc limit 1),'待首次调用'),'last_latency_ms',coalesce((select d.latency_ms from public.tiandao_ai_decisions_v259 d order by d.created_at desc limit 1),0),'last_failure_reason',(select nullif(d.failure_reason,'') from public.tiandao_ai_decisions_v259 d order by d.created_at desc limit 1),'cloudflare_24h',(select count(*) from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours' and d.engine='cloudflare_workers_ai'),'fallback_24h',(select count(*) from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours' and d.engine='server_personality_v1')) into v_ai_runtime from public.tiandao_people_settings_v259 s where singleton_id=1;
  return jsonb_build_object('status','ok','sql','SQL260','settings',v_settings,'ai_runtime',v_ai_runtime,'recent_ai_decisions',v_ai,'counts',jsonb_build_object('npc_total',(select count(*) from public.tiandao_npcs_v259),'core_ai',(select count(*) from public.tiandao_npcs_v259 where core_ai),'romanceable',(select count(*) from public.tiandao_npcs_v259 where romanceable),'relations',(select count(*) from public.tiandao_relations_v259),'pending_encounters',(select count(*) from public.tiandao_encounters_v259 where status='pending' and expires_at>clock_timestamp()),'active_companions',(select count(*) from public.tiandao_companions_v259 where status='active'),'life_states',(select count(*) from public.tiandao_life_state_v260),'active_stories',(select count(*) from public.tiandao_story_threads_v260 where status='active'),'unread_inbox',(select count(*) from public.tiandao_inbox_v260 where status='unread' and expires_at>clock_timestamp()),'active_promises',(select count(*) from public.tiandao_promises_v260 where status='active')),'npcs',v_npcs,'recent_relations',v_rel,'recent_encounters',v_enc,'companions',v_comp,'recent_life',v_life,'recent_stories',v_story,'recent_inbox',v_inbox,'audit',v_audit);
end $$;

create or replace function public.admin9_update_tiandao_settings_v259(p_patch jsonb,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before jsonb;v_after jsonb;
begin
  perform public.admin_whoami_v1();if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;if length(trim(coalesce(p_reason,'')))<2 then raise exception 'ADMIN_REASON_REQUIRED';end if;
  if exists(select 1 from public.tiandao_admin_audit_v259 where request_id=p_request_id) then select after_data into v_after from public.tiandao_admin_audit_v259 where request_id=p_request_id;return coalesce(v_after,'{}'::jsonb)||jsonb_build_object('duplicate_request',true);end if;
  select to_jsonb(s) into v_before from public.tiandao_people_settings_v259 s where singleton_id=1 for update;
  update public.tiandao_people_settings_v259 set
    enabled=coalesce((p_patch->>'enabled')::boolean,enabled),encounters_enabled=coalesce((p_patch->>'encounters_enabled')::boolean,encounters_enabled),interactions_enabled=coalesce((p_patch->>'interactions_enabled')::boolean,interactions_enabled),romance_enabled=coalesce((p_patch->>'romance_enabled')::boolean,romance_enabled),companion_enabled=coalesce((p_patch->>'companion_enabled')::boolean,companion_enabled),
    living_people_enabled=coalesce((p_patch->>'living_people_enabled')::boolean,living_people_enabled),daily_life_enabled=coalesce((p_patch->>'daily_life_enabled')::boolean,daily_life_enabled),npc_initiative_enabled=coalesce((p_patch->>'npc_initiative_enabled')::boolean,npc_initiative_enabled),story_enabled=coalesce((p_patch->>'story_enabled')::boolean,story_enabled),free_talk_enabled=coalesce((p_patch->>'free_talk_enabled')::boolean,free_talk_enabled),
    encounter_interval_minutes=coalesce((p_patch->>'encounter_interval_minutes')::integer,encounter_interval_minutes),max_pending_encounters=coalesce((p_patch->>'max_pending_encounters')::integer,max_pending_encounters),daily_refresh_hours=coalesce((p_patch->>'daily_refresh_hours')::integer,daily_refresh_hours),max_active_stories=coalesce((p_patch->>'max_active_stories')::integer,max_active_stories),max_unread_inbox=coalesce((p_patch->>'max_unread_inbox')::integer,max_unread_inbox),story_expire_hours=coalesce((p_patch->>'story_expire_hours')::integer,story_expire_hours),promise_hours=coalesce((p_patch->>'promise_hours')::integer,promise_hours),memory_dedupe_hours=coalesce((p_patch->>'memory_dedupe_hours')::integer,memory_dedupe_hours),
    talk_cooldown_seconds=coalesce((p_patch->>'talk_cooldown_seconds')::integer,talk_cooldown_seconds),gift_cooldown_seconds=coalesce((p_patch->>'gift_cooldown_seconds')::integer,gift_cooldown_seconds),meeting_cooldown_seconds=coalesce((p_patch->>'meeting_cooldown_seconds')::integer,meeting_cooldown_seconds),confess_cooldown_seconds=coalesce((p_patch->>'confess_cooldown_seconds')::integer,confess_cooldown_seconds),companion_action_cooldown_seconds=coalesce((p_patch->>'companion_action_cooldown_seconds')::integer,companion_action_cooldown_seconds),
    gift_spirit_stone_cost=coalesce((p_patch->>'gift_spirit_stone_cost')::bigint,gift_spirit_stone_cost),companion_gift_spirit_stone_cost=coalesce((p_patch->>'companion_gift_spirit_stone_cost')::bigint,companion_gift_spirit_stone_cost),confess_affinity_min=coalesce((p_patch->>'confess_affinity_min')::integer,confess_affinity_min),confess_trust_min=coalesce((p_patch->>'confess_trust_min')::integer,confess_trust_min),confess_intimacy_min=coalesce((p_patch->>'confess_intimacy_min')::integer,confess_intimacy_min),confess_romance_min=coalesce((p_patch->>'confess_romance_min')::integer,confess_romance_min),ai_enabled=coalesce((p_patch->>'ai_enabled')::boolean,ai_enabled),ai_timeout_ms=coalesce((p_patch->>'ai_timeout_ms')::integer,ai_timeout_ms),ai_max_tokens=coalesce((p_patch->>'ai_max_tokens')::integer,ai_max_tokens),updated_at=clock_timestamp()
  where singleton_id=1;
  select to_jsonb(s) into v_after from public.tiandao_people_settings_v259 s where singleton_id=1;
  insert into public.tiandao_admin_audit_v259(admin_user_id,action_code,before_data,after_data,reason,request_id) values(auth.uid(),'settings_update_sql260',v_before,v_after,trim(p_reason),p_request_id);
  return jsonb_build_object('status','ok','settings',v_after);
exception when check_violation or invalid_text_representation then raise exception 'TIANDAO_SETTINGS_INVALID';end $$;

create or replace function public.admin9_check_tiandao_people_v259()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old_exposed integer;v_table_exposed integer;v_direct_actions_exposed integer;v_internal_exposed integer;v_v260_table_exposed integer;
begin
  perform public.admin_whoami_v1();
  select count(*) into v_old_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';
  select count(*) into v_table_exposed from information_schema.table_privileges where table_schema='public' and table_name like 'tiandao\_%\_v259' escape E'\\' and grantee in('anon','authenticated','PUBLIC');
  select count(*) into v_v260_table_exposed from information_schema.table_privileges where table_schema='public' and table_name like 'tiandao\_%\_v260' escape E'\\' and grantee in('anon','authenticated','PUBLIC');
  select count(*) into v_direct_actions_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('resolve_tiandao_encounter_v1','tiandao_npc_interact_v1','tiandao_romance_action_v1','tiandao_companion_action_v1') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';
  select count(*) into v_internal_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('server_personality_v1','tiandao_ai_runtime_settings_v259','tiandao_ai_prepare_v259','tiandao_ai_apply_v259','tiandao_refresh_person_life_v260','tiandao_spawn_story_v260','tiandao_maybe_initiative_v260','tiandao_refresh_world_v260') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';
  return jsonb_build_object('status',case when (select count(*) from public.tiandao_npcs_v259)=50 and (select count(*) from public.tiandao_npcs_v259 where core_ai)=20 and (select count(*) from public.tiandao_npcs_v259 where romanceable)=30 and v_old_exposed=0 and v_table_exposed=0 and v_v260_table_exposed=0 and v_direct_actions_exposed=0 and v_internal_exposed=0 and to_regclass('public.tiandao_life_state_v260') is not null and to_regclass('public.tiandao_story_threads_v260') is not null and to_regclass('public.tiandao_inbox_v260') is not null and to_regclass('public.tiandao_promises_v260') is not null and to_regprocedure('public.server_personality_v1(jsonb)') is not null and to_regprocedure('public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)') is not null and to_regprocedure('public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)') is not null then 'PASS' else 'FAIL' end,
    'sql','SQL260','npc_total',(select count(*) from public.tiandao_npcs_v259),'core_ai',(select count(*) from public.tiandao_npcs_v259 where core_ai),'romanceable',(select count(*) from public.tiandao_npcs_v259 where romanceable),'legacy_player_rpc_exposed',v_old_exposed,'v259_raw_table_privileges',v_table_exposed,'v260_raw_table_privileges',v_v260_table_exposed,'direct_action_rpc_exposed',v_direct_actions_exposed,'ai_internal_rpc_exposed',v_internal_exposed,'life_table',to_regclass('public.tiandao_life_state_v260') is not null,'story_table',to_regclass('public.tiandao_story_threads_v260') is not null,'inbox_table',to_regclass('public.tiandao_inbox_v260') is not null,'promise_table',to_regclass('public.tiandao_promises_v260') is not null,'player_read_rpc_count',(select count(*) from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname in('get_tiandao_people_hub_v1','get_tiandao_person_detail_v1','tiandao_people_mark_read_v260')),'ai_model',(select ai_model from public.tiandao_people_settings_v259 where singleton_id=1),'fallback_function','server_personality_v1');
end $$;

-- ==================== PERMISSIONS ====================
do $permissions$
declare x record;
begin
  for x in select tablename from pg_tables where schemaname='public' and (tablename like 'tiandao\_%\_v259' escape E'\\' or tablename like 'tiandao\_%\_v260' escape E'\\') loop
    execute format('alter table public.%I enable row level security',x.tablename);
    execute format('revoke all on table public.%I from anon,authenticated,public',x.tablename);
  end loop;
  for x in select format('%I.%I(%s)',ns.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) sig from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname in('get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1') loop execute format('revoke execute on function %s from anon, authenticated, public',x.sig);end loop;
end
$permissions$;

revoke all on function public.tiandao_relation_band_v260(integer,text) from public,anon,authenticated;
revoke all on function public.tiandao_gift_category_v260(text) from public,anon,authenticated;
revoke all on function public.tiandao_story_choices_v260(integer,text) from public,anon,authenticated;
revoke all on function public.tiandao_story_seed_v260(uuid,uuid) from public,anon,authenticated;
revoke all on function public.tiandao_refresh_person_life_v260(uuid,uuid) from public,anon,authenticated;
revoke all on function public.tiandao_spawn_story_v260(uuid,uuid,boolean) from public,anon,authenticated;
revoke all on function public.tiandao_maybe_initiative_v260(uuid,uuid) from public,anon,authenticated;
revoke all on function public.tiandao_refresh_world_v260(uuid) from public,anon,authenticated;
revoke all on function public.tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb) from public,anon,authenticated;
revoke all on function public.server_personality_v1(jsonb) from public,anon,authenticated;
revoke all on function public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text) from public,anon,authenticated;
revoke all on function public.get_tiandao_people_hub_v1() from public,anon,authenticated;
revoke all on function public.get_tiandao_person_detail_v1(uuid) from public,anon,authenticated;
revoke all on function public.tiandao_people_mark_read_v260(uuid) from public,anon,authenticated;
revoke all on function public.admin9_get_tiandao_people_v259() from public,anon,authenticated;
revoke all on function public.admin9_update_tiandao_settings_v259(jsonb,text,uuid) from public,anon,authenticated;
revoke all on function public.admin9_check_tiandao_people_v259() from public,anon,authenticated;

-- 旧直写动作继续保持不可由前端调用。
revoke all on function public.resolve_tiandao_encounter_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.tiandao_npc_interact_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.tiandao_romance_action_v1(uuid,text,text) from public,anon,authenticated;
revoke all on function public.tiandao_companion_action_v1(text) from public,anon,authenticated;

grant execute on function public.get_tiandao_people_hub_v1() to authenticated;
grant execute on function public.get_tiandao_person_detail_v1(uuid) to authenticated;
grant execute on function public.tiandao_people_mark_read_v260(uuid) to authenticated;
grant execute on function public.server_personality_v1(jsonb) to service_role;
grant execute on function public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid) to service_role;
grant execute on function public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text) to service_role;
grant execute on function public.admin9_get_tiandao_people_v259() to authenticated;
grant execute on function public.admin9_update_tiandao_settings_v259(jsonb,text,uuid) to authenticated;
grant execute on function public.admin9_check_tiandao_people_v259() to authenticated;

-- ==================== FINAL GATE ====================
do $gate$
declare v_old_exposed integer;v_v259_table_exposed integer;v_v260_table_exposed integer;v_internal_exposed integer;
begin
  if (select count(*) from public.tiandao_npcs_v259)<>50 then raise exception 'SQL260_GATE_NPC_TOTAL_NOT_50';end if;
  if (select count(*) from public.tiandao_npcs_v259 where core_ai)<>20 then raise exception 'SQL260_GATE_CORE_AI_NOT_20';end if;
  if (select count(*) from public.tiandao_npcs_v259 where romanceable)<>30 then raise exception 'SQL260_GATE_ROMANCEABLE_NOT_30';end if;
  if exists(select 1 from public.tiandao_npcs_v259 where age<18) then raise exception 'SQL260_GATE_UNDERAGE_NPC';end if;
  if to_regclass('public.tiandao_life_state_v260') is null or to_regclass('public.tiandao_story_threads_v260') is null or to_regclass('public.tiandao_inbox_v260') is null or to_regclass('public.tiandao_promises_v260') is null then raise exception 'SQL260_GATE_LIVING_TABLE_MISSING';end if;
  if to_regprocedure('public.tiandao_people_mark_read_v260(uuid)') is null then raise exception 'SQL260_GATE_INBOX_READ_RPC_MISSING';end if;
  if pg_get_function_result(to_regprocedure('public.tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb)'))<>'void' then raise exception 'SQL260_GATE_MEMORY_FUNCTION_ABI_CHANGED';end if;
  if to_regprocedure('public.server_personality_v1(jsonb)') is null then raise exception 'SQL260_GATE_FALLBACK_MISSING';end if;
  if to_regprocedure('public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)') is null or to_regprocedure('public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)') is null then raise exception 'SQL260_GATE_AI_INTERNAL_RPC_MISSING';end if;
  select count(*) into v_old_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1','resolve_tiandao_encounter_v1','tiandao_npc_interact_v1','tiandao_romance_action_v1','tiandao_companion_action_v1') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';if v_old_exposed<>0 then raise exception 'SQL260_GATE_OLD_OR_DIRECT_RPC_EXPOSED:%',v_old_exposed;end if;
  select count(*) into v_v259_table_exposed from information_schema.table_privileges where table_schema='public' and table_name like 'tiandao\_%\_v259' escape E'\\' and grantee in('anon','authenticated','PUBLIC');if v_v259_table_exposed<>0 then raise exception 'SQL260_GATE_V259_RAW_TABLE_EXPOSED:%',v_v259_table_exposed;end if;
  select count(*) into v_v260_table_exposed from information_schema.table_privileges where table_schema='public' and table_name like 'tiandao\_%\_v260' escape E'\\' and grantee in('anon','authenticated','PUBLIC');if v_v260_table_exposed<>0 then raise exception 'SQL260_GATE_V260_RAW_TABLE_EXPOSED:%',v_v260_table_exposed;end if;
  select count(*) into v_internal_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('server_personality_v1','tiandao_ai_prepare_v259','tiandao_ai_apply_v259','tiandao_refresh_person_life_v260','tiandao_spawn_story_v260','tiandao_maybe_initiative_v260','tiandao_refresh_world_v260') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';if v_internal_exposed<>0 then raise exception 'SQL260_GATE_INTERNAL_RPC_EXPOSED:%',v_internal_exposed;end if;
  if not has_function_privilege('authenticated','public.get_tiandao_people_hub_v1()','EXECUTE') or not has_function_privilege('authenticated','public.get_tiandao_person_detail_v1(uuid)','EXECUTE') or not has_function_privilege('authenticated','public.tiandao_people_mark_read_v260(uuid)','EXECUTE') then raise exception 'SQL260_GATE_PLAYER_READ_RPC_MISSING';end if;
  if not has_function_privilege('service_role','public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)','EXECUTE') or not has_function_privilege('service_role','public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)','EXECUTE') then raise exception 'SQL260_GATE_SERVICE_AI_EXECUTE_MISSING';end if;
end
$gate$;

commit;

select jsonb_build_object(
  'sql',260,
  'revision','R2_FUNCTION_ABI_COMPAT',
  'gate','SQL260_GATE_PASSED',
  'release','V2.2.0 CACHE131',
  'module','完整天道人物 / 每日生活 / NPC主动 / 人生事件 / 自由交谈 / 赠礼偏好 / 情境相约 / 承诺 / 记忆去重 / 关系画像',
  'npc_total',50,
  'edge','继续复用已上线 tiandao-ai；无需重新部署',
  'ai_engine','Cloudflare Workers AI 优先；失败/超时自动 server_personality_v1 fallback',
  'security','AI仅提案，服务端审核数值/经济/关系/事件推进',
  'next_sql',261
) as sql260_install_result;
