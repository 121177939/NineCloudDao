-- 九霄问道 SQL259 R2 · V2.2.0 CACHE129
-- 天道人物 / 缘遇 / 人物志 / 仙缘 / 道侣
-- 彻底替换旧红尘玩家入口；旧表仅保留历史归档，不再作为新版运行依赖。
-- 生产基线：SQL258 ONLINE；SQL259 尚未上线，本R2替代R1一次执行；成功后 NEXT SQL260。

begin;

-- ---------- PRECHECK ----------
do $precheck$
begin
  if to_regclass('public.player_characters') is null then raise exception 'SQL259_PRECHECK_PLAYER_CHARACTERS_MISSING'; end if;
  if to_regprocedure('public.tianxu_active_character_v255()') is null then raise exception 'SQL259_PRECHECK_ACTIVE_CHARACTER_HELPER_MISSING'; end if;
  if to_regprocedure('public.tianxu_inventory_adjust_v255(uuid,text,bigint)') is null then raise exception 'SQL259_PRECHECK_INVENTORY_HELPER_MISSING'; end if;
  if to_regprocedure('public.admin_whoami_v1()') is null then raise exception 'SQL259_PRECHECK_ADMIN_WHOAMI_MISSING'; end if;
end
$precheck$;

-- ---------- SETTINGS / DEFINITIONS ----------
create table if not exists public.tiandao_people_settings_v259(
  singleton_id smallint primary key default 1 check(singleton_id=1),
  enabled boolean not null default true,
  encounters_enabled boolean not null default true,
  interactions_enabled boolean not null default true,
  romance_enabled boolean not null default true,
  companion_enabled boolean not null default true,
  encounter_interval_minutes integer not null default 180 check(encounter_interval_minutes between 10 and 10080),
  max_pending_encounters integer not null default 3 check(max_pending_encounters between 1 and 20),
  talk_cooldown_seconds integer not null default 60 check(talk_cooldown_seconds between 0 and 86400),
  gift_cooldown_seconds integer not null default 300 check(gift_cooldown_seconds between 0 and 86400),
  meeting_cooldown_seconds integer not null default 900 check(meeting_cooldown_seconds between 0 and 86400),
  confess_cooldown_seconds integer not null default 1800 check(confess_cooldown_seconds between 0 and 604800),
  companion_action_cooldown_seconds integer not null default 120 check(companion_action_cooldown_seconds between 0 and 86400),
  gift_spirit_stone_cost bigint not null default 1000 check(gift_spirit_stone_cost>=0),
  companion_gift_spirit_stone_cost bigint not null default 5000 check(companion_gift_spirit_stone_cost>=0),
  confess_affinity_min integer not null default 55 check(confess_affinity_min between -100 and 100),
  confess_trust_min integer not null default 45 check(confess_trust_min between 0 and 100),
  confess_intimacy_min integer not null default 35 check(confess_intimacy_min between 0 and 100),
  confess_romance_min integer not null default 50 check(confess_romance_min between 0 and 100),
  ai_enabled boolean not null default true,
  ai_model text not null default '@cf/qwen/qwen3-30b-a3b-fp8',
  ai_timeout_ms integer not null default 8000 check(ai_timeout_ms between 1500 and 20000),
  ai_max_tokens integer not null default 420 check(ai_max_tokens between 128 and 800),
  ai_engine text not null default 'cloudflare_workers_ai',
  updated_at timestamptz not null default clock_timestamp()
);
insert into public.tiandao_people_settings_v259(singleton_id) values(1) on conflict(singleton_id) do nothing;

-- R2兼容：若SQL259 R1曾被测试执行过，CREATE TABLE IF NOT EXISTS不会补列；这里显式补齐AI字段。
alter table public.tiandao_people_settings_v259 add column if not exists ai_enabled boolean not null default true;
alter table public.tiandao_people_settings_v259 add column if not exists ai_model text not null default '@cf/qwen/qwen3-30b-a3b-fp8';
alter table public.tiandao_people_settings_v259 add column if not exists ai_timeout_ms integer not null default 8000;
alter table public.tiandao_people_settings_v259 add column if not exists ai_max_tokens integer not null default 420;
alter table public.tiandao_people_settings_v259 add column if not exists ai_engine text not null default 'cloudflare_workers_ai';
alter table public.tiandao_people_settings_v259 alter column ai_model set default '@cf/qwen/qwen3-30b-a3b-fp8';
alter table public.tiandao_people_settings_v259 alter column ai_engine set default 'cloudflare_workers_ai';
update public.tiandao_people_settings_v259
set ai_engine='cloudflare_workers_ai', ai_model='@cf/qwen/qwen3-30b-a3b-fp8', updated_at=clock_timestamp()
where singleton_id=1;

create table if not exists public.tiandao_npcs_v259(
  id uuid primary key default gen_random_uuid(),
  npc_code text not null unique,
  name text not null,
  gender text not null check(gender in('female','male')),
  age integer not null check(age>=18),
  core_ai boolean not null default false,
  romanceable boolean not null default false,
  realm_label text not null,
  identity text not null,
  element text not null default '无',
  public_profile text not null default '',
  personality jsonb not null default '{}'::jsonb,
  private_goal text not null default '',
  ai_notes text not null default '',
  romance_threshold integer not null default 80 check(romance_threshold between 50 and 120),
  enabled boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index if not exists tiandao_npcs_core_idx_v259 on public.tiandao_npcs_v259(core_ai,enabled,npc_code);
create index if not exists tiandao_npcs_romance_idx_v259 on public.tiandao_npcs_v259(romanceable,gender,enabled,npc_code);

create table if not exists public.tiandao_relations_v259(
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  known_level text not null default 'unknown' check(known_level in('unknown','heard','acquainted','familiar','close')),
  affinity integer not null default 0 check(affinity between -100 and 100),
  gratitude integer not null default 0 check(gratitude between 0 and 100),
  hatred integer not null default 0 check(hatred between 0 and 100),
  fear integer not null default 0 check(fear between 0 and 100),
  trust integer not null default 0 check(trust between 0 and 100),
  intimacy integer not null default 0 check(intimacy between 0 and 100),
  romance integer not null default 0 check(romance between 0 and 100),
  interaction_count integer not null default 0,
  current_status text not null default '各自修行，尚无深交。',
  latest_rumor text not null default '',
  last_interaction_at timestamptz,
  last_action text,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(character_id,npc_id)
);
create index if not exists tiandao_relations_npc_idx_v259 on public.tiandao_relations_v259(npc_id,updated_at desc);
create index if not exists tiandao_relations_character_idx_v259 on public.tiandao_relations_v259(character_id,updated_at desc);

create table if not exists public.tiandao_memories_v259(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  memory_type text not null,
  content text not null,
  importance integer not null default 1 check(importance between 1 and 5),
  public_to_player boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists tiandao_memories_lookup_idx_v259 on public.tiandao_memories_v259(character_id,npc_id,created_at desc);

create table if not exists public.tiandao_encounters_v259(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  title text not null,
  summary text not null,
  location_name text not null default '九霄界',
  source_label text not null default '天道缘遇',
  actions jsonb not null default '[]'::jsonb,
  status text not null default 'pending' check(status in('pending','resolved','expired')),
  expires_at timestamptz not null default (clock_timestamp()+interval '3 days'),
  resolved_action text,
  outcome text,
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz
);
create index if not exists tiandao_encounters_pending_idx_v259 on public.tiandao_encounters_v259(character_id,status,expires_at,created_at desc);

create table if not exists public.tiandao_companions_v259(
  character_id uuid primary key references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  status text not null default 'active' check(status in('active','ended')),
  bond_level integer not null default 1 check(bond_level between 1 and 10),
  formed_at timestamptz not null default clock_timestamp(),
  last_action_at timestamptz,
  updated_at timestamptz not null default clock_timestamp()
);
create index if not exists tiandao_companions_npc_idx_v259 on public.tiandao_companions_v259(npc_id,status,formed_at desc);

create table if not exists public.tiandao_interaction_log_v259(
  id bigint generated always as identity primary key,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  action_code text not null,
  deltas jsonb not null default '{}'::jsonb,
  content text not null default '',
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists tiandao_interaction_log_lookup_idx_v259 on public.tiandao_interaction_log_v259(character_id,npc_id,action_code,created_at desc);

create table if not exists public.tiandao_ai_decisions_v259(
  id bigint generated always as identity primary key,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  request_id uuid,
  decision_type text not null,
  engine text not null,
  model text not null default '@cf/qwen/qwen3-30b-a3b-fp8',
  decision text not null,
  score numeric(10,3),
  threshold numeric(10,3),
  rationale text not null default '',
  latency_ms integer not null default 0,
  failure_reason text not null default '',
  proposal jsonb not null default '{}'::jsonb,
  applied jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
-- R2兼容：补齐R1可能已创建的旧版AI决策表字段。
alter table public.tiandao_ai_decisions_v259 add column if not exists request_id uuid;
alter table public.tiandao_ai_decisions_v259 add column if not exists model text not null default '@cf/qwen/qwen3-30b-a3b-fp8';
alter table public.tiandao_ai_decisions_v259 add column if not exists latency_ms integer not null default 0;
alter table public.tiandao_ai_decisions_v259 add column if not exists failure_reason text not null default '';
alter table public.tiandao_ai_decisions_v259 add column if not exists proposal jsonb not null default '{}'::jsonb;
alter table public.tiandao_ai_decisions_v259 add column if not exists applied jsonb not null default '{}'::jsonb;
create index if not exists tiandao_ai_decision_lookup_idx_v259 on public.tiandao_ai_decisions_v259(character_id,npc_id,created_at desc);

create table if not exists public.tiandao_admin_audit_v259(
  id bigint generated always as identity primary key,
  admin_user_id uuid,
  action_code text not null,
  before_data jsonb,
  after_data jsonb,
  reason text not null,
  request_id uuid not null unique,
  created_at timestamptz not null default clock_timestamp()
);

-- ---------- 50 NPC SEED ----------
-- 20 核心AI人物：不作为本版可结缘池；30 新增可结缘人物：20女/10男，全部成年且不限制玩家性别。
insert into public.tiandao_npcs_v259
(npc_code,name,gender,age,core_ai,romanceable,realm_label,identity,element,public_profile,personality,private_goal,ai_notes,romance_threshold,enabled)
values
('core_gu_xuanwei','顾玄微','female',142,true,false,'合体期','天机阁主','水','掌天机星盘，言语极少，却常比旁人早一步看到风浪。',jsonb_build_object('temperament','calm','value_anchor','truth','romance_openness',20,'stubbornness',70,'gift_preference','古卷'),'厘清九霄近百年天机异动的真正源头。','先观察因果一致性，再判断玩家是否值得托付隐秘。',95,true),
('core_pei_guanlan','裴观澜','male',176,true,false,'渡劫期','太虚剑宗掌教','金','剑意如海，治宗严谨，最厌夸夸其谈。',jsonb_build_object('temperament','stern','value_anchor','discipline','romance_openness',10,'stubbornness',85,'gift_preference','剑谱'),'维持剑宗在九霄界的秩序与威望。','重行动轻言辞，对守诺行为给予高权重。',100,true),
('core_shen_zhaoye','沈照夜','female',128,true,false,'炼虚期','九幽巡使','暗','常年行走险地，熟悉魔息与秘境异象。',jsonb_build_object('temperament','cool','value_anchor','duty','romance_openness',15,'stubbornness',62,'gift_preference','护道物'),'追查九幽魔息扩散路线。','对危险中的选择记忆权重更高。',94,true),
('core_lu_chenzhou','陆沉舟','male',165,true,false,'合体期','散修盟主','土','出身散修，最看重公平与兑现承诺。',jsonb_build_object('temperament','steady','value_anchor','fairness','romance_openness',18,'stubbornness',58,'gift_preference','灵石'),'让散修在大宗门之外仍有立足之地。','对交易、互助与背信行为高度敏感。',92,true),
('core_su_jiangxue','苏绛雪','female',119,true,false,'炼虚期','丹霞谷主','火','丹道宗师，性情温和，却绝不容忍浪费灵药。',jsonb_build_object('temperament','warm','value_anchor','healing','romance_openness',25,'stubbornness',42,'gift_preference','灵草'),'完善一炉可护住渡劫心脉的古丹方。','救助、守护行为会显著提升评价。',90,true),
('core_jiang_wenchen','江问尘','male',151,true,false,'合体期','云游真君','风','来去无踪，常以旁观者身份卷入大事。',jsonb_build_object('temperament','free','value_anchor','freedom','romance_openness',30,'stubbornness',35,'gift_preference','奇物'),'寻找失落在各界的无名道碑。','厌恶强迫，偏好留有选择余地的互动。',88,true),
('core_ye_xinghe','叶星河','male',133,true,false,'炼虚期','星罗殿主','雷','推演战局如布星棋，少有失算。',jsonb_build_object('temperament','rational','value_anchor','strategy','romance_openness',12,'stubbornness',66,'gift_preference','阵材'),'补全星罗大阵缺失的最后一道阵眼。','会记录玩家长期策略是否前后一致。',97,true),
('core_ning_qingqiu','宁清秋','female',126,true,false,'炼虚期','清微宫主','木','处事清正，对晚辈颇有耐心。',jsonb_build_object('temperament','gentle','value_anchor','kindness','romance_openness',24,'stubbornness',40,'gift_preference','茶'),'维持清微宫与世间诸宗的平衡。','善意与守信会累积为长期信任。',90,true),
('core_xie_wujiu','谢无咎','male',188,true,false,'渡劫期','执法尊者','金','不徇私情，判事只看证据与后果。',jsonb_build_object('temperament','stern','value_anchor','law','romance_openness',8,'stubbornness',90,'gift_preference','无'),'压下九霄界各宗暗中扩大的私斗。','不接受以礼物替代责任的行为。',105,true),
('core_bai_zhaochuan','白照川','male',97,true,false,'化神期','灵宝商主','金','掌握诸多物资流向，消息比货物更值钱。',jsonb_build_object('temperament','shrewd','value_anchor','exchange','romance_openness',20,'stubbornness',45,'gift_preference','奇珍'),'建立跨宗门的稳定灵物流通网。','对公平交换、市场信誉与违约行为敏感。',89,true),
('core_hua_mianyue','花眠月','female',111,true,false,'化神期','幻月楼主','水','擅观人心，却很少直接给出答案。',jsonb_build_object('temperament','mysterious','value_anchor','emotion','romance_openness',32,'stubbornness',50,'gift_preference','花酿'),'寻找能够不受幻境影响的真实记忆。','会把玩家面对诱惑时的选择写入高重要记忆。',86,true),
('core_sikong_jin','司空烬','male',160,true,false,'合体期','赤霄城主','火','行事果决，重结果也重担当。',jsonb_build_object('temperament','bold','value_anchor','responsibility','romance_openness',16,'stubbornness',72,'gift_preference','火系材料'),'守住赤霄城外正在扩张的裂隙。','危机中的担当比日常好感更重要。',96,true),
('core_wen_ruyu','温如玉','male',105,true,false,'化神期','儒道散仙','木','温文有礼，善辩经义，也愿听不同道路。',jsonb_build_object('temperament','gentle','value_anchor','wisdom','romance_openness',28,'stubbornness',30,'gift_preference','书卷'),'编成一部记录当代诸道的九霄论集。','偏好有内容的交谈，不喜欢重复奉承。',87,true),
('core_luo_tinglan','洛听澜','female',137,true,false,'炼虚期','沧澜剑主','水','剑势绵长，待人冷静而不冷漠。',jsonb_build_object('temperament','cool','value_anchor','perseverance','romance_openness',22,'stubbornness',64,'gift_preference','剑材'),'寻找能够化解水剑两道冲突的新路。','长期坚持会显著提升信任。',91,true),
('core_wei_changsheng','魏长生','male',204,true,false,'渡劫期','药王山主','木','寿元悠长，见过太多盛衰，对生死格外平静。',jsonb_build_object('temperament','calm','value_anchor','life','romance_openness',10,'stubbornness',55,'gift_preference','古药'),'保存即将失传的灵药谱系。','更看重玩家是否珍惜资源与生命。',101,true),
('core_zhu_chiming','祝赤明','female',123,true,false,'炼虚期','红莲尊者','火','外冷内烈，对敌强硬，对恩情记得极深。',jsonb_build_object('temperament','fiery','value_anchor','loyalty','romance_openness',20,'stubbornness',78,'gift_preference','火晶'),'清算一桩多年未了的宗门旧债。','恩情和背叛都会形成高重要长期记忆。',93,true),
('core_tang_guiyuan','唐归元','male',190,true,false,'渡劫期','阵道宗师','土','沉迷阵理，常忘时日，却对阵法承诺极认真。',jsonb_build_object('temperament','focused','value_anchor','craft','romance_openness',8,'stubbornness',82,'gift_preference','阵盘'),'重构一座能稳定界壁的古阵。','对解决问题的实际能力评价很高。',104,true),
('core_chu_tianque','楚天阙','male',172,true,false,'合体期','镇魔使','雷','常年镇守边界，话不多，判断极快。',jsonb_build_object('temperament','stern','value_anchor','protection','romance_openness',12,'stubbornness',75,'gift_preference','镇魔材料'),'压制九幽吞天兽背后的魔潮源头。','战斗与护道经历权重最高。',99,true),
('core_mu_qingge','沐清歌','female',108,true,false,'化神期','天音阁主','风','以琴入道，善从细微变化判断人心。',jsonb_build_object('temperament','warm','value_anchor','harmony','romance_openness',30,'stubbornness',34,'gift_preference','乐谱'),'寻回失散的九霄古音谱。','交谈内容与反复互动会形成连续记忆。',87,true),
('core_ji_wuyue','姬无月','female',149,true,false,'合体期','月华宫主','冰','心思缜密，极少轻许承诺。',jsonb_build_object('temperament','reserved','value_anchor','promise','romance_openness',14,'stubbornness',81,'gift_preference','寒玉'),'守住月华宫传承中的一桩隐秘。','承诺一旦违背会造成显著长期负面评价。',102,true),

('romance_liu_hanyan','柳含烟','female',26,false,true,'筑基期','云游琴修','木','琴声清润，喜欢在山水间记录遇见的人。',jsonb_build_object('temperament','gentle','value_anchor','sincerity','romance_openness',72,'stubbornness',28,'gift_preference','乐谱'),'走遍九霄名山，完成自己的百景琴谱。','真诚交谈与相约加权较高。',72,true),
('romance_yun_shuying','云疏影','female',31,false,true,'金丹期','散修剑客','风','行事利落，不爱绕弯，笑起来却很随和。',jsonb_build_object('temperament','bold','value_anchor','freedom','romance_openness',64,'stubbornness',52,'gift_preference','剑材'),'找到不依附宗门也能走远的剑道。','尊重选择与并肩经历加权较高。',76,true),
('romance_qin_wanzhao','秦晚照','female',29,false,true,'筑基期','丹师','火','做事细致，常把关心藏在一炉丹火里。',jsonb_build_object('temperament','warm','value_anchor','care','romance_openness',75,'stubbornness',30,'gift_preference','灵草'),'炼成一味能治旧伤的丹药。','赠礼与互助容易形成恩情记忆。',70,true),
('romance_wen_xuejian','温雪见','female',24,false,true,'筑基期','雪岭修士','冰','初见清冷，熟悉后话反而很多。',jsonb_build_object('temperament','reserved','value_anchor','trust','romance_openness',62,'stubbornness',44,'gift_preference','寒玉'),'离开雪岭看看更大的九霄界。','信任门槛高，好感增长较慢但稳定。',78,true),
('romance_su_tingyu','苏听雨','female',27,false,true,'筑基期','灵植师','水','喜雨爱茶，对草木与人的情绪都很敏锐。',jsonb_build_object('temperament','gentle','value_anchor','patience','romance_openness',78,'stubbornness',24,'gift_preference','灵草'),'培育一株只在雷雨中开花的灵植。','连续相处比单次高额赠礼更重要。',69,true),
('romance_shen_qingluo','沈青萝','female',34,false,true,'金丹期','阵修','土','推阵认真，生活里却有些迷糊。',jsonb_build_object('temperament','focused','value_anchor','craft','romance_openness',66,'stubbornness',48,'gift_preference','阵材'),'修复祖上传下的残阵。','一起解决问题会快速提升亲密。',75,true),
('romance_ye_zhiqiu','叶知秋','female',36,false,true,'金丹期','医修','木','见惯伤病，因此比旁人更珍惜平静日常。',jsonb_build_object('temperament','calm','value_anchor','life','romance_openness',70,'stubbornness',36,'gift_preference','药材'),'建一处不问出身的医庐。','护道、关怀与守信权重较高。',73,true),
('romance_luo_weichen','洛微尘','female',28,false,true,'筑基期','符修','雷','笔锋凌厉，性格却并不强势。',jsonb_build_object('temperament','bright','value_anchor','curiosity','romance_openness',74,'stubbornness',32,'gift_preference','符纸'),'画出能稳定雷灵力的全新符式。','新鲜经历会显著增加好感。',71,true),
('romance_gu_qingci','顾清辞','female',42,false,true,'金丹期','书阁执事','金','记性极好，常能准确说出你很久以前提过的小事。',jsonb_build_object('temperament','calm','value_anchor','memory','romance_openness',60,'stubbornness',40,'gift_preference','古卷'),'整理一批即将散佚的修行手札。','会高权重保留关键承诺与对话。',80,true),
('romance_jiang_yuebai','江月白','female',25,false,true,'筑基期','舟修','水','常年往返云海渡口，最爱听远方故事。',jsonb_build_object('temperament','free','value_anchor','adventure','romance_openness',82,'stubbornness',18,'gift_preference','奇物'),'攒够灵石造一艘自己的云舟。','相约与新地点缘遇加权最高。',67,true),
('romance_ning_shuanghua','宁霜华','female',45,false,true,'元婴期','冰宫客卿','冰','处事成熟，很少因一时情绪改变判断。',jsonb_build_object('temperament','reserved','value_anchor','stability','romance_openness',52,'stubbornness',58,'gift_preference','寒玉'),'完成一段未尽的护送约定。','长期稳定互动优先于短期好感。',84,true),
('romance_hua_zhaolu','花朝露','female',23,false,true,'炼气期','灵酿师','木','喜欢热闹，也能一个人守着酒坛看日出。',jsonb_build_object('temperament','bright','value_anchor','joy','romance_openness',85,'stubbornness',20,'gift_preference','灵果'),'酿出属于自己的第一坛名酒。','轻松交谈与礼物反馈更积极。',65,true),
('romance_xie_lingxi','谢灵犀','female',32,false,true,'金丹期','驭兽师','土','对灵兽很有耐心，对人反而更谨慎。',jsonb_build_object('temperament','cautious','value_anchor','trust','romance_openness',58,'stubbornness',46,'gift_preference','灵兽材料'),'寻找走失多年的灵兽伙伴。','信任与恩情比单纯好感更重要。',81,true),
('romance_chu_zhaoning','楚昭宁','female',39,false,true,'金丹期','守城修士','火','待人爽朗，遇事先做再说。',jsonb_build_object('temperament','bold','value_anchor','responsibility','romance_openness',68,'stubbornness',50,'gift_preference','护具'),'守住自己负责的边城与同伴。','护道、共同承担风险有额外加权。',74,true),
('romance_bai_ruoli','白若离','female',30,false,true,'筑基期','商旅修士','金','算盘打得快，却不喜欢占朋友便宜。',jsonb_build_object('temperament','shrewd','value_anchor','fairness','romance_openness',65,'stubbornness',37,'gift_preference','奇珍'),'走通一条安全的新商路。','公平交换与守诺能快速累积信任。',76,true),
('romance_tang_wanqing','唐绾青','female',37,false,true,'金丹期','阵法学士','土','理性克制，对真正感兴趣的事会谈很久。',jsonb_build_object('temperament','rational','value_anchor','wisdom','romance_openness',57,'stubbornness',49,'gift_preference','阵图'),'完成一部简化阵法入门。','高质量交谈比礼物更有效。',82,true),
('romance_ji_xingwan','姬星晚','female',28,false,true,'筑基期','观星修士','雷','常在夜里观星，喜欢记录偶然的天象。',jsonb_build_object('temperament','mysterious','value_anchor','wonder','romance_openness',73,'stubbornness',29,'gift_preference','星石'),'等待一场古籍记载的星落。','缘遇和相约事件权重较高。',71,true),
('romance_pei_qingge','裴清歌','female',33,false,true,'金丹期','乐修','风','言辞温柔，做决定却很坚定。',jsonb_build_object('temperament','warm','value_anchor','promise','romance_openness',69,'stubbornness',55,'gift_preference','乐谱'),'把一首未完成的曲子写完。','承诺与共同经历都记得很久。',75,true),
('romance_sikong_wantang','司空晚棠','female',41,false,true,'元婴期','散修炼器师','火','炼器时脾气急，离开炉火反而很好说话。',jsonb_build_object('temperament','fiery','value_anchor','craft','romance_openness',55,'stubbornness',63,'gift_preference','矿石'),'炼出一件真正满意的本命器。','帮助解决材料与炼器问题加权高。',83,true),
('romance_mu_nanzhi','沐南枝','female',35,false,true,'金丹期','药谷行者','木','喜欢独行，却从不拒绝真正需要帮助的人。',jsonb_build_object('temperament','quiet','value_anchor','kindness','romance_openness',63,'stubbornness',41,'gift_preference','药材'),'寻找失传灵药的最后一处产地。','善意行为与长期陪伴会提升情缘。',78,true),

('romance_lu_qingxuan','陆青玄','male',27,false,true,'筑基期','散修刀客','金','笑得随意，出刀却从不含糊。',jsonb_build_object('temperament','bold','value_anchor','freedom','romance_openness',76,'stubbornness',43,'gift_preference','刀材'),'走遍九霄，与真正的高手交手。','共同冒险与坦率表达加权较高。',70,true),
('romance_shen_yanci','沈砚辞','male',34,false,true,'金丹期','符阵修士','土','寡言但细心，常替别人把遗漏的事补上。',jsonb_build_object('temperament','quiet','value_anchor','care','romance_openness',61,'stubbornness',38,'gift_preference','阵材'),'完成师门留下的护城阵图。','细小但持续的互动更容易积累亲密。',79,true),
('romance_su_changfeng','苏长风','male',30,false,true,'筑基期','云游剑客','风','性格开朗，最怕被束缚。',jsonb_build_object('temperament','free','value_anchor','adventure','romance_openness',80,'stubbornness',33,'gift_preference','奇物'),'找一条没人走过的远行路线。','相约和给彼此空间都会加分。',68,true),
('romance_jiang_linyuan','江临渊','male',43,false,true,'元婴期','守渊修士','水','沉稳可靠，很少轻易评价别人。',jsonb_build_object('temperament','steady','value_anchor','responsibility','romance_openness',52,'stubbornness',57,'gift_preference','护道物'),'完成镇守水渊的十年约。','信任与共同承担风险是核心指标。',85,true),
('romance_gu_xingzhou','顾行舟','male',29,false,true,'筑基期','云舟修士','木','擅修云舟，也愿意听别人讲一路见闻。',jsonb_build_object('temperament','warm','value_anchor','journey','romance_openness',78,'stubbornness',25,'gift_preference','木材'),'造一艘能穿过风暴云海的轻舟。','相约和故事型交谈反馈更好。',69,true),
('romance_ning_wuya','宁无涯','male',48,false,true,'元婴期','散修枪修','雷','经历不少生死，因此很少把关系说得太轻。',jsonb_build_object('temperament','reserved','value_anchor','loyalty','romance_openness',48,'stubbornness',67,'gift_preference','枪材'),'了结一场多年未决的旧战。','护道与守诺远高于礼物权重。',88,true),
('romance_pei_zhaochuan','裴照川','male',36,false,true,'金丹期','炼器师','火','直爽健谈，喜欢把复杂事情说简单。',jsonb_build_object('temperament','bright','value_anchor','craft','romance_openness',70,'stubbornness',39,'gift_preference','矿石'),'开一间属于自己的小炼器坊。','礼物和共同完成目标都有正向加成。',74,true),
('romance_luo_qianshan','洛千山','male',40,false,true,'金丹期','山门客卿','土','性格稳重，习惯先做足准备再行动。',jsonb_build_object('temperament','steady','value_anchor','stability','romance_openness',58,'stubbornness',53,'gift_preference','阵材'),'寻找适合建立洞府的山脉。','持续可靠的互动比突发热情更重要。',82,true),
('romance_chu_huaizhen','楚怀真','male',32,false,true,'金丹期','儒修','木','爱读旧书，也愿意为现实问题放下书卷。',jsonb_build_object('temperament','gentle','value_anchor','wisdom','romance_openness',67,'stubbornness',31,'gift_preference','古卷'),'将所学真正用于世间，而非只留在纸上。','交谈、互助和价值观一致性权重较高。',76,true),
('romance_xie_yunshen','谢云深','male',38,false,true,'金丹期','秘境行者','水','熟悉险路，习惯把最坏情况先算清楚。',jsonb_build_object('temperament','cautious','value_anchor','trust','romance_openness',60,'stubbornness',45,'gift_preference','护道物'),'绘出一份可靠的秘境危险图谱。','共同经历险境会显著提升信任与亲密。',80,true)
on conflict(npc_code) do update set
 name=excluded.name,gender=excluded.gender,age=excluded.age,core_ai=excluded.core_ai,romanceable=excluded.romanceable,
 realm_label=excluded.realm_label,identity=excluded.identity,element=excluded.element,public_profile=excluded.public_profile,
 personality=excluded.personality,private_goal=excluded.private_goal,ai_notes=excluded.ai_notes,romance_threshold=excluded.romance_threshold,
 enabled=excluded.enabled,updated_at=clock_timestamp();

-- ---------- INTERNAL HELPERS ----------
create or replace function public.tiandao_relation_stage_v259(
  p_affinity integer,p_trust integer,p_intimacy integer,p_romance integer,p_hatred integer,p_is_companion boolean default false)
returns text language sql immutable set search_path='' as $$
select case
 when p_is_companion then '道侣'
 when coalesce(p_hatred,0)>=60 then '敌视'
 when coalesce(p_romance,0)>=70 and coalesce(p_intimacy,0)>=55 then '倾心'
 when coalesce(p_romance,0)>=45 then '心有情愫'
 when coalesce(p_trust,0)>=60 and coalesce(p_affinity,0)>=60 then '知己'
 when coalesce(p_affinity,0)>=35 then '熟识'
 when coalesce(p_affinity,0)>=10 then '相识'
 else '陌生' end $$;

create or replace function public.tiandao_public_attitude_v259(p_stage text)
returns text language sql immutable set search_path='' as $$
select case p_stage
 when '道侣' then '与你并肩同行，许多话无需再绕弯。'
 when '倾心' then '与你相处时，目光中已很难掩饰情意。'
 when '心有情愫' then '似乎越来越在意你的言行。'
 when '知己' then '对你已少有戒备，愿意谈及心中之事。'
 when '熟识' then '与你相处得还算自在。'
 when '相识' then '已经记住了你，但彼此仍需更多了解。'
 when '敌视' then '对你的敌意并未消退。'
 else '你们尚未真正熟悉。' end $$;

create or replace function public.tiandao_ensure_relation_v259(p_character_id uuid,p_npc_id uuid,p_known_level text default 'heard')
returns void language plpgsql security definer set search_path='' as $$
begin
  insert into public.tiandao_relations_v259(character_id,npc_id,known_level)
  values(p_character_id,p_npc_id,case when p_known_level in('unknown','heard','acquainted','familiar','close') then p_known_level else 'heard' end)
  on conflict(character_id,npc_id) do update set
    known_level=case
      when public.tiandao_relations_v259.known_level='unknown' and excluded.known_level<>'unknown' then excluded.known_level
      else public.tiandao_relations_v259.known_level end,
    updated_at=clock_timestamp();
end $$;

create or replace function public.tiandao_add_memory_v259(
  p_character_id uuid,p_npc_id uuid,p_type text,p_content text,p_importance integer default 1,p_public boolean default true,p_metadata jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
  insert into public.tiandao_memories_v259(character_id,npc_id,memory_type,content,importance,public_to_player,metadata)
  values(p_character_id,p_npc_id,coalesce(nullif(p_type,''),'event'),left(coalesce(p_content,''),600),least(5,greatest(1,coalesce(p_importance,1))),coalesce(p_public,true),coalesce(p_metadata,'{}'::jsonb));
  -- 控制普通记忆增长：每组人物关系最多保留50条低重要记忆；重要度4/5永久保留。
  delete from public.tiandao_memories_v259 m
  where m.id in(
    select x.id from public.tiandao_memories_v259 x
    where x.character_id=p_character_id and x.npc_id=p_npc_id and x.importance<=3
    order by x.created_at desc offset 50
  );
end $$;

create or replace function public.tiandao_publish_world_event_v259(p_event_type text,p_title text,p_content text,p_level integer default 2)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if to_regclass('public.jiuxiao_world_events') is null then return false; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='event_type')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='title')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='content')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='event_level')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='is_pinned')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='created_at') then return false;end if;
  begin
    execute 'insert into public.jiuxiao_world_events(event_type,title,content,event_level,is_pinned,created_at) values($1,$2,$3,$4,false,clock_timestamp())'
      using left(coalesce(p_event_type,'tiandao_people_v259'),80),left(coalesce(p_title,'九霄人物'),120),left(coalesce(p_content,''),1200),least(5,greatest(1,coalesce(p_level,2)));
    return true;
  exception when others then return false;end;
end $$;

create or replace function public.tiandao_seed_visibility_v259(p_character_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
  insert into public.tiandao_relations_v259(character_id,npc_id,known_level,current_status)
  select p_character_id,n.id,'heard','你只从九霄界闻与旁人口中听过此人。'
  from public.tiandao_npcs_v259 n
  where n.enabled and n.core_ai
  order by n.npc_code
  limit 8
  on conflict(character_id,npc_id) do nothing;
end $$;

create or replace function public.tiandao_maybe_spawn_encounter_v259(p_character_id uuid,p_source text default '天道缘遇')
returns uuid language plpgsql security definer set search_path='' as $$
declare s public.tiandao_people_settings_v259%rowtype;v_pending integer;v_last timestamptz;v_npc public.tiandao_npcs_v259%rowtype;v_id uuid;v_actions jsonb;
begin
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not coalesce(s.enabled,false) or not coalesce(s.encounters_enabled,false) then return null;end if;
  update public.tiandao_encounters_v259 set status='expired' where character_id=p_character_id and status='pending' and expires_at<=clock_timestamp();
  select count(*) into v_pending from public.tiandao_encounters_v259 where character_id=p_character_id and status='pending' and expires_at>clock_timestamp();
  if v_pending>=s.max_pending_encounters then return null;end if;
  select max(created_at) into v_last from public.tiandao_encounters_v259 where character_id=p_character_id;
  if v_last is not null and v_last>clock_timestamp()-make_interval(mins=>s.encounter_interval_minutes) then return null;end if;
  select n.* into v_npc
  from public.tiandao_npcs_v259 n
  where n.enabled
    and not exists(select 1 from public.tiandao_companions_v259 c where c.character_id=p_character_id and c.npc_id=n.id and c.status='active')
    and not exists(select 1 from public.tiandao_encounters_v259 e where e.character_id=p_character_id and e.npc_id=n.id and e.status='pending')
  order by case when n.romanceable then 0 else 1 end,random()
  limit 1;
  if v_npc.id is null then return null;end if;
  perform public.tiandao_ensure_relation_v259(p_character_id,v_npc.id,'heard');
  v_actions:=jsonb_build_array(
    jsonb_build_object('code','approach','label',case when v_npc.romanceable then '上前相识' else '上前见礼' end),
    jsonb_build_object('code','observe','label','静观其变'),
    jsonb_build_object('code','leave','label','暂且离去')
  );
  insert into public.tiandao_encounters_v259(character_id,npc_id,title,summary,location_name,source_label,actions)
  values(p_character_id,v_npc.id,'与'||v_npc.name||'的一线因果',coalesce(nullif(v_npc.public_profile,''),'一位九霄修士与你的因果线短暂交会。'),'九霄界',left(coalesce(nullif(p_source,''),'天道缘遇'),80),v_actions)
  returning id into v_id;
  return v_id;
end $$;

-- ---------- PLAYER RPC: HUB ----------
create or replace function public.get_tiandao_people_hub_v1()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();v_people jsonb;v_enc jsonb;v_rom jsonb;v_comp jsonb;v_counts jsonb;
begin
  if not (select enabled from public.tiandao_people_settings_v259 where singleton_id=1) then return jsonb_build_object('status','disabled','people','[]'::jsonb,'encounters','[]'::jsonb,'romance','[]'::jsonb,'companion',null,'counts','{}'::jsonb);end if;
  perform public.tiandao_seed_visibility_v259(v_char);
  perform public.tiandao_maybe_spawn_encounter_v259(v_char,'天道缘遇');
  update public.tiandao_encounters_v259 set status='expired' where character_id=v_char and status='pending' and expires_at<=clock_timestamp();

  select coalesce(jsonb_agg(x.obj order by x.sort_key,x.name),'[]'::jsonb) into v_people from(
    select n.name,case r.known_level when 'close' then 0 when 'familiar' then 1 when 'acquainted' then 2 else 3 end sort_key,
      jsonb_build_object(
        'npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'gender',n.gender,'realm_label',n.realm_label,'identity',n.identity,'element',n.element,
        'known_level',r.known_level,'relation_stage',public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,c.character_id is not null),
        'affinity',r.affinity,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,
        'current_status',r.current_status,'latest_rumor',r.latest_rumor,
        'is_companion',(c.character_id is not null),
        'can_confess',(n.romanceable and c.character_id is null and r.affinity>=(select confess_affinity_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.trust>=(select confess_trust_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.intimacy>=(select confess_intimacy_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.romance>=(select confess_romance_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.hatred<25)
      ) obj
    from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id
    left join public.tiandao_companions_v259 c on c.character_id=v_char and c.npc_id=n.id and c.status='active'
    where r.character_id=v_char and r.known_level<>'unknown' and n.enabled
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'encounter_id',e.id,'npc_id',e.npc_id,'npc_name',n.name,'title',e.title,'summary',e.summary,'location_name',e.location_name,'source_label',e.source_label,
    'actions',e.actions,'action_code',coalesce(e.actions->0->>'code','approach'),'action_label',coalesce(e.actions->0->>'label','回应'),'expires_at',e.expires_at
  ) order by e.created_at desc),'[]'::jsonb) into v_enc
  from public.tiandao_encounters_v259 e join public.tiandao_npcs_v259 n on n.id=e.npc_id
  where e.character_id=v_char and e.status='pending' and e.expires_at>clock_timestamp();

  select coalesce(jsonb_agg(jsonb_build_object(
    'npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'realm_label',n.realm_label,'identity',n.identity,
    'known_level',r.known_level,'relation_stage',public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,c.character_id is not null),
    'affinity',r.affinity,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,
    'current_status',r.current_status,'latest_rumor',r.latest_rumor,'is_companion',(c.character_id is not null),
    'can_confess',(c.character_id is null and r.affinity>=(select confess_affinity_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.trust>=(select confess_trust_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.intimacy>=(select confess_intimacy_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.romance>=(select confess_romance_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.hatred<25)
  ) order by r.romance desc,r.intimacy desc,r.affinity desc),'[]'::jsonb) into v_rom
  from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id and n.romanceable and n.enabled
  left join public.tiandao_companions_v259 c on c.character_id=v_char and c.npc_id=n.id and c.status='active'
  where r.character_id=v_char and r.known_level<>'unknown' and (r.affinity>=10 or r.romance>0 or c.character_id is not null);

  select jsonb_build_object(
    'npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'realm_label',n.realm_label,'identity',n.identity,
    'relation_stage','道侣','is_companion',true,'current_status',r.current_status,'latest_rumor',r.latest_rumor,
    'affinity',r.affinity,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'bond_level',c.bond_level,'formed_at',c.formed_at
  ) into v_comp
  from public.tiandao_companions_v259 c join public.tiandao_npcs_v259 n on n.id=c.npc_id join public.tiandao_relations_v259 r on r.character_id=c.character_id and r.npc_id=c.npc_id
  where c.character_id=v_char and c.status='active';

  select jsonb_build_object(
    'known',(select count(*) from public.tiandao_relations_v259 where character_id=v_char and known_level in('acquainted','familiar','close')),
    'heard',(select count(*) from public.tiandao_relations_v259 where character_id=v_char and known_level='heard'),
    'encounters',(select count(*) from public.tiandao_encounters_v259 where character_id=v_char and status='pending' and expires_at>clock_timestamp()),
    'romance',(select count(*) from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id where r.character_id=v_char and n.romanceable and (r.affinity>=10 or r.romance>0))
  ) into v_counts;
  return jsonb_build_object('status','ok','people',v_people,'encounters',v_enc,'romance',v_rom,'companion',v_comp,'counts',v_counts,'build','TIANDAO_PEOPLE_V259');
end $$;

create or replace function public.get_tiandao_person_detail_v1(p_npc_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;v_comp boolean;v_mem jsonb;v_stage text;v_can boolean;
begin
  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;
  if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
  select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=n.id;
  if r.npc_id is null or r.known_level='unknown' then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
  select exists(select 1 from public.tiandao_companions_v259 where character_id=v_char and npc_id=n.id and status='active') into v_comp;
  v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,v_comp);
  v_can:=n.romanceable and not v_comp and r.affinity>=(select confess_affinity_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.trust>=(select confess_trust_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.intimacy>=(select confess_intimacy_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.romance>=(select confess_romance_min from public.tiandao_people_settings_v259 where singleton_id=1) and r.hatred<25;
  select coalesce(jsonb_agg(jsonb_build_object('content',m.content,'memory_type',m.memory_type,'created_at',m.created_at) order by m.created_at desc),'[]'::jsonb) into v_mem
  from (select * from public.tiandao_memories_v259 where character_id=v_char and npc_id=n.id and public_to_player order by created_at desc limit 8) m;
  return jsonb_build_object('npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'gender',n.gender,'realm_label',n.realm_label,'identity',n.identity,'element',n.element,
    'public_profile',n.public_profile,'known_level',r.known_level,'relation_stage',v_stage,'affinity',r.affinity,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,
    'attitude_text',public.tiandao_public_attitude_v259(v_stage),'current_status',r.current_status,'latest_rumor',r.latest_rumor,'public_memories',v_mem,'is_companion',v_comp,'can_confess',v_can);
end $$;

create or replace function public.resolve_tiandao_encounter_v1(p_encounter_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();e public.tiandao_encounters_v259%rowtype;r public.tiandao_relations_v259%rowtype;n public.tiandao_npcs_v259%rowtype;v_content text;da int:=0;dt int:=0;di int:=0;dr int:=0;
begin
  select * into e from public.tiandao_encounters_v259 where id=p_encounter_id and character_id=v_char for update;
  if e.id is null then raise exception 'TIANDAO_ENCOUNTER_NOT_FOUND';end if;
  if e.status<>'pending' then raise exception 'TIANDAO_ENCOUNTER_ALREADY_RESOLVED';end if;
  if e.expires_at<=clock_timestamp() then update public.tiandao_encounters_v259 set status='expired' where id=e.id;raise exception 'TIANDAO_ENCOUNTER_EXPIRED';end if;
  if coalesce(p_action,'') not in('approach','accept','observe','leave') then raise exception 'TIANDAO_ENCOUNTER_ACTION_INVALID';end if;
  select * into n from public.tiandao_npcs_v259 where id=e.npc_id;
  perform public.tiandao_ensure_relation_v259(v_char,e.npc_id,'heard');
  select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=e.npc_id for update;
  if p_action in('approach','accept') then da:=5;dt:=2;di:=1;dr:=case when n.romanceable then 1 else 0 end;v_content:='你顺着这线因果上前，与'||n.name||'真正有了第一次交集。';
  elsif p_action='observe' then da:=1;dt:=1;v_content:='你没有贸然上前，只把'||n.name||'的身影与这次缘遇记在心里。';
  else v_content:='你暂且没有追上这段因果，缘分仍留有余地。';end if;
  update public.tiandao_relations_v259 set
    known_level=case when p_action in('approach','accept') and known_level in('unknown','heard') then 'acquainted' else known_level end,
    affinity=least(100,greatest(-100,affinity+da)),trust=least(100,greatest(0,trust+dt)),intimacy=least(100,greatest(0,intimacy+di)),romance=least(100,greatest(0,romance+dr)),
    latest_rumor=v_content,current_status=case when p_action in('approach','accept') then '你们已经正式相识。' else current_status end,updated_at=clock_timestamp()
  where character_id=v_char and npc_id=e.npc_id returning * into r;
  update public.tiandao_encounters_v259 set status='resolved',resolved_action=p_action,outcome=v_content,resolved_at=clock_timestamp() where id=e.id;
  if p_action in('approach','accept') then perform public.tiandao_add_memory_v259(v_char,e.npc_id,'encounter',v_content,3,true,jsonb_build_object('encounter_id',e.id));end if;
  return jsonb_build_object('status','ok','content',v_content,'relation_stage',public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,false));
end $$;

create or replace function public.tiandao_npc_interact_v1(p_npc_id uuid,p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();s public.tiandao_people_settings_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;v_last timestamptz;v_cd int;v_temp text;v_pref text;da int:=0;dg int:=0;dt int:=0;di int:=0;dr int:=0;v_cost bigint:=0;v_content text;v_stage text;
begin
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not s.enabled or not s.interactions_enabled then raise exception 'TIANDAO_INTERACTIONS_DISABLED';end if;
  if coalesce(p_action,'') not in('talk','gift','meeting') then raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
  select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=n.id for update;
  if r.npc_id is null or r.known_level='unknown' then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
  select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=v_char and npc_id=n.id and action_code=p_action;
  v_cd:=case p_action when 'talk' then s.talk_cooldown_seconds when 'gift' then s.gift_cooldown_seconds else s.meeting_cooldown_seconds end;
  if v_last is not null and v_last+make_interval(secs=>v_cd)>clock_timestamp() then raise exception 'TIANDAO_INTERACTION_COOLDOWN';end if;
  v_temp:=coalesce(n.personality->>'temperament','steady');v_pref:=coalesce(n.personality->>'gift_preference','');
  if p_action='talk' then
    da:=case v_temp when 'warm' then 3 when 'bright' then 3 when 'reserved' then 1 when 'stern' then 1 else 2 end;dt:=case when v_temp in('calm','steady','gentle') then 2 else 1 end;di:=case when r.interaction_count>=3 then 1 else 0 end;
    v_content:=n.name||case v_temp when 'reserved' then '听完后只轻轻点头，但没有回避你的话。' when 'warm' then '认真听完，也与你多谈了几句。' when 'bold' then '笑着接过话头，回应得很直接。' else '与你谈了片刻，对你的印象又清晰了一些。' end;
  elsif p_action='gift' then
    v_cost:=s.gift_spirit_stone_cost;if v_cost>0 then perform public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',-v_cost);end if;
    da:=5;dg:=4;dt:=1;dr:=case when n.romanceable then 1 else 0 end;if v_pref not in('','无') then da:=da+1;dg:=dg+1;end if;
    v_content:=n.name||'收下了你的心意。礼物本身并不能替代经历，但这份善意被记住了。';
  else
    da:=4;dt:=3;di:=4;dr:=case when n.romanceable then 3 else 0 end;
    v_content:='你与'||n.name||'相约同行了一段路，共同经历让彼此更加熟悉。';
  end if;
  update public.tiandao_relations_v259 set
    known_level=case when known_level in('unknown','heard') then 'acquainted' when known_level='acquainted' and interaction_count>=4 then 'familiar' when known_level='familiar' and interaction_count>=12 then 'close' else known_level end,
    affinity=least(100,greatest(-100,affinity+da)),gratitude=least(100,greatest(0,gratitude+dg)),trust=least(100,greatest(0,trust+dt)),intimacy=least(100,greatest(0,intimacy+di)),romance=least(100,greatest(0,romance+dr)),
    interaction_count=interaction_count+1,last_interaction_at=clock_timestamp(),last_action=p_action,latest_rumor=v_content,current_status='你们最近仍有来往。',updated_at=clock_timestamp()
  where character_id=v_char and npc_id=n.id returning * into r;
  insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(v_char,n.id,p_action,jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'spirit_stone_cost',v_cost),v_content);
  perform public.tiandao_add_memory_v259(v_char,n.id,p_action,v_content,case when p_action='meeting' then 2 else 1 end,true,jsonb_build_object('action',p_action));
  v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,exists(select 1 from public.tiandao_companions_v259 where character_id=v_char and npc_id=n.id and status='active'));
  return jsonb_build_object('status','ok','content',v_content,'relation_stage',v_stage,'spirit_stone_cost',v_cost);
end $$;

create or replace function public.tiandao_romance_action_v1(p_npc_id uuid,p_action text,p_message text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();s public.tiandao_people_settings_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;v_last timestamptz;v_score numeric;v_threshold numeric;v_jitter int;v_decision text;v_reason text;v_content text;v_player text:='某位修士';v_existing uuid;
begin
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not s.enabled or not s.romance_enabled then raise exception 'TIANDAO_ROMANCE_DISABLED';end if;
  if coalesce(p_action,'')<>'confess' then raise exception 'TIANDAO_ROMANCE_ACTION_INVALID';end if;
  if length(trim(coalesce(p_message,'')))<1 or length(trim(coalesce(p_message,'')))>300 then raise exception 'TIANDAO_CONFESSION_MESSAGE_INVALID';end if;
  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled and romanceable;if n.id is null then raise exception 'TIANDAO_ROMANCE_NPC_INVALID';end if;
  select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=n.id for update;
  if r.npc_id is null or r.known_level not in('acquainted','familiar','close') then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
  if r.affinity<s.confess_affinity_min or r.trust<s.confess_trust_min or r.intimacy<s.confess_intimacy_min or r.romance<s.confess_romance_min or r.hatred>=25 then raise exception 'TIANDAO_CONFESSION_REQUIREMENTS';end if;
  select npc_id into v_existing from public.tiandao_companions_v259 where character_id=v_char and status='active';if v_existing is not null and v_existing<>n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';elsif v_existing=n.id then return jsonb_build_object('status','ok','decision','accept','content','你们已经是正式道侣。');end if;
  select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=v_char and npc_id=n.id and action_code='confess';
  if v_last is not null and v_last+make_interval(secs=>s.confess_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_CONFESSION_COOLDOWN';end if;
  v_jitter:=(mod(mod(hashtextextended(v_char::text||':'||n.id::text||':'||date_trunc('hour',clock_timestamp())::text,259),11)+11,11)::int)-5;
  v_score:=r.affinity*0.32+r.trust*0.30+r.intimacy*0.24+r.romance*0.32+r.gratitude*0.08-r.hatred*0.55-r.fear*0.15+coalesce((n.personality->>'romance_openness')::numeric,50)*0.10+v_jitter;
  v_threshold:=n.romance_threshold;
  if v_score>=v_threshold then v_decision:='accept';v_reason:='彼此经历与信任已经足以让TA作出肯定决定。';
  elsif v_score>=v_threshold-10 then v_decision:='defer';v_reason:='TA并非没有心意，但仍需要更多共同经历确认这份选择。';
  else v_decision:='reject';v_reason:='此刻的关系与TA自己的判断还不足以接受这份心意。';end if;
  insert into public.tiandao_ai_decisions_v259(character_id,npc_id,decision_type,engine,decision,score,threshold,rationale)
  values(v_char,n.id,'confession',s.ai_engine,v_decision,v_score,v_threshold,v_reason);
  insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(v_char,n.id,'confess',jsonb_build_object('score',v_score,'threshold',v_threshold,'decision',v_decision),left(trim(p_message),300));
  if v_decision='accept' then
    insert into public.tiandao_companions_v259(character_id,npc_id,status) values(v_char,n.id,'active') on conflict(character_id) do update set npc_id=excluded.npc_id,status='active',formed_at=clock_timestamp(),updated_at=clock_timestamp();
    update public.tiandao_relations_v259 set known_level='close',affinity=greatest(affinity,80),trust=greatest(trust,70),intimacy=greatest(intimacy,70),romance=greatest(romance,85),current_status='你们已经正式结为道侣。',latest_rumor=n.name||'接受了你的心意，与你结为道侣。',updated_at=clock_timestamp() where character_id=v_char and npc_id=n.id;
    v_content:=n.name||'沉默片刻后接受了你的心意。大道漫漫，你们从此以道侣之名同行。';
    perform public.tiandao_add_memory_v259(v_char,n.id,'companion_formed',v_content,5,true,jsonb_build_object('message',left(trim(p_message),300)));
    begin select name into v_player from public.player_characters where id=v_char;exception when others then v_player:='某位修士';end;
    perform public.tiandao_publish_world_event_v259('tiandao_companion_v259','仙缘既定',coalesce(nullif(v_player,''),'某位修士')||'与'||n.name||'因缘圆满，正式结为道侣。',3);
  elsif v_decision='defer' then
    update public.tiandao_relations_v259 set trust=least(100,trust+2),intimacy=least(100,intimacy+1),romance=least(100,romance+1),latest_rumor=n.name||'认真听完你的心意，却希望再多走一段路。',updated_at=clock_timestamp() where character_id=v_char and npc_id=n.id;
    v_content:=n.name||'没有立刻拒绝，也没有草率答应。'||v_reason;
    perform public.tiandao_add_memory_v259(v_char,n.id,'confession_defer',v_content,4,true,jsonb_build_object('message',left(trim(p_message),300)));
  else
    update public.tiandao_relations_v259 set romance=greatest(0,romance-5),latest_rumor=n.name||'没有接受这次表白，但关系并未被强行清零。',updated_at=clock_timestamp() where character_id=v_char and npc_id=n.id;
    v_content:=n.name||'没有接受这份心意。'||v_reason;
    perform public.tiandao_add_memory_v259(v_char,n.id,'confession_reject',v_content,4,true,jsonb_build_object('message',left(trim(p_message),300)));
  end if;
  return jsonb_build_object('status','ok','decision',v_decision,'content',v_content,'reason',v_reason,'engine',s.ai_engine);
end $$;

create or replace function public.tiandao_companion_action_v1(p_action text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();s public.tiandao_people_settings_v259%rowtype;c public.tiandao_companions_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;v_last timestamptz;da int:=0;dg int:=0;dt int:=0;di int:=0;dr int:=0;v_cost bigint:=0;v_content text;
begin
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;if not s.enabled or not s.companion_enabled then raise exception 'TIANDAO_COMPANION_DISABLED';end if;
  if coalesce(p_action,'') not in('message','gift','meeting','joint_cultivation','protect') then raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
  select * into c from public.tiandao_companions_v259 where character_id=v_char and status='active' for update;if c.character_id is null then raise exception 'TIANDAO_COMPANION_NOT_FOUND';end if;
  if c.last_action_at is not null and c.last_action_at+make_interval(secs=>s.companion_action_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_COMPANION_ACTION_COOLDOWN';end if;
  select * into n from public.tiandao_npcs_v259 where id=c.npc_id;select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=c.npc_id for update;
  if p_action='message' then dt:=2;di:=2;dr:=1;v_content:='你向'||n.name||'传去一封讯息，短短几句话也让彼此的牵挂更清晰。';
  elsif p_action='gift' then v_cost:=s.companion_gift_spirit_stone_cost;if v_cost>0 then perform public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',-v_cost);end if;da:=3;dg:=4;di:=2;dr:=2;v_content:='你为'||n.name||'准备了一份礼物。心意被收下，也被记在你们共同的往事里。';
  elsif p_action='meeting' then da:=3;dt:=3;di:=4;dr:=3;v_content:='你与'||n.name||'相约同行，暂时把修行之外的喧嚣放在身后。';
  elsif p_action='joint_cultivation' then dt:=4;di:=5;dr:=3;v_content:='你与'||n.name||'共同修炼、互证所得。这次同修主要沉淀为关系经历，不直接凭空生成修为。';
  else dt:=5;di:=3;dr:=2;v_content:='你与'||n.name||'约定在彼此需要时互为护道。这样的承诺会被长期记住。';end if;
  update public.tiandao_relations_v259 set affinity=least(100,affinity+da),gratitude=least(100,gratitude+dg),trust=least(100,trust+dt),intimacy=least(100,intimacy+di),romance=least(100,romance+dr),known_level='close',current_status='你们以道侣之名继续各自修行，也彼此牵挂。',latest_rumor=v_content,last_interaction_at=clock_timestamp(),last_action='companion_'||p_action,interaction_count=interaction_count+1,updated_at=clock_timestamp() where character_id=v_char and npc_id=c.npc_id;
  update public.tiandao_companions_v259 set last_action_at=clock_timestamp(),bond_level=least(10,bond_level+case when p_action in('meeting','joint_cultivation','protect') then 1 else 0 end),updated_at=clock_timestamp() where character_id=v_char;
  insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(v_char,c.npc_id,'companion_'||p_action,jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'spirit_stone_cost',v_cost),v_content);
  perform public.tiandao_add_memory_v259(v_char,c.npc_id,'companion_'||p_action,v_content,case when p_action in('joint_cultivation','protect') then 3 else 2 end,true,'{}'::jsonb);
  return jsonb_build_object('status','ok','content',v_content,'spirit_stone_cost',v_cost);
end $$;

-- ---------- CLOUDFLARE WORKERS AI GATEWAY / SERVER FALLBACK ----------
-- Edge Function only may call the internal functions below with service_role.
-- AI proposals never write state directly; tiandao_ai_apply_v259 revalidates and applies fixed server rules.
create table if not exists public.tiandao_ai_requests_v259(
  request_id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  request_kind text not null check(request_kind in('interaction','romance','encounter','companion')),
  action_code text not null,
  player_message text not null default '',
  encounter_id uuid references public.tiandao_encounters_v259(id) on delete set null,
  context_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'prepared' check(status in('prepared','applied','expired')),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp()+interval '2 minutes'),
  applied_at timestamptz
);
create index if not exists tiandao_ai_requests_user_idx_v259 on public.tiandao_ai_requests_v259(user_id,created_at desc);

-- AI只可提出“下一目标/行动意图”；服务端将这两个白名单叙事字段单独持久化，供下一次人格判断参考。
-- 此表不存任何资产、境界、战斗或道侣权威状态。
create table if not exists public.tiandao_ai_state_v259(
  character_id uuid not null references public.player_characters(id) on delete cascade,
  npc_id uuid not null references public.tiandao_npcs_v259(id) on delete cascade,
  next_goal text not null default '',
  action_intent text not null default '',
  last_dialogue text not null default '',
  last_engine text not null default '',
  last_model text not null default '',
  updated_at timestamptz not null default clock_timestamp(),
  primary key(character_id,npc_id)
);

create or replace function public.server_personality_v1(p_context jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_kind text:=coalesce(p_context->>'request_kind','interaction');
  v_action text:=coalesce(p_context->>'action','talk');
  v_name text:=coalesce(p_context#>>'{npc,name}','这位修士');
  v_temp text:=coalesce(p_context#>>'{npc,personality,temperament}','steady');
  v_aff int:=coalesce((p_context#>>'{relation,affinity}')::int,0);
  v_trust int:=coalesce((p_context#>>'{relation,trust}')::int,0);
  v_int int:=coalesce((p_context#>>'{relation,intimacy}')::int,0);
  v_rom int:=coalesce((p_context#>>'{relation,romance}')::int,0);
  v_grat int:=coalesce((p_context#>>'{relation,gratitude}')::int,0);
  v_hat int:=coalesce((p_context#>>'{relation,hatred}')::int,0);
  v_fear int:=coalesce((p_context#>>'{relation,fear}')::int,0);
  v_open numeric:=coalesce((p_context#>>'{npc,personality,romance_openness}')::numeric,50);
  v_threshold numeric:=coalesce((p_context#>>'{npc,romance_threshold}')::numeric,80);
  v_score numeric;v_decision text:='neutral';v_dialogue text;v_goal text;v_intent text;v_reason text;
begin
  if v_kind='romance' and v_action='confess' then
    v_score:=v_aff*0.32+v_trust*0.30+v_int*0.24+v_rom*0.32+v_grat*0.08-v_hat*0.55-v_fear*0.15+v_open*0.10;
    if v_score>=v_threshold then v_decision:='accept';v_dialogue:=v_name||'认真看着你，最终愿意与你把这段因果继续走下去。';v_reason:='本地人格规则判断关系积累已达到接受阈值。';
    elsif v_score>=v_threshold-10 then v_decision:='defer';v_dialogue:=v_name||'没有回避你的心意，却希望再多一些共同经历后再作决定。';v_reason:='本地人格规则判断接近阈值，但仍需更多关系积累。';
    else v_decision:='reject';v_dialogue:=v_name||'坦然回应了你的心意，但此刻还无法接受这份关系。';v_reason:='本地人格规则判断当前关系不足以接受。';end if;
    v_goal:='继续根据既有经历观察彼此是否真正适合同行';v_intent:='保持符合当前关系阶段的往来';
  elsif v_kind='companion' then
    v_dialogue:=case v_action when 'message' then v_name||'收到了你的传音，也回了一句只有你们彼此明白的话。' when 'gift' then v_name||'收下了你的心意，并把这份礼物记进共同往事。' when 'meeting' then v_name||'与你相约同行，愿意暂时放下各自忙碌。' when 'joint_cultivation' then v_name||'与你共同修炼、互证所得。' else v_name||'记住了你愿意彼此护道的承诺。' end;
    v_goal:='维持道侣之间各自独立又彼此支持的关系';v_intent:='回应当前道侣互动';v_reason:='Cloudflare不可用，使用确定性的本地道侣人格规则。';
  elsif v_kind='encounter' then
    v_dialogue:=case v_action when 'approach' then v_name||'注意到了你的靠近，并没有立刻离去。' when 'accept' then v_name||'接受了这次相遇，让原本短暂的因果真正接续起来。' when 'observe' then v_name||'似乎察觉到远处的目光，却仍按自己的道路前行。' else '这段相遇暂时擦肩而过。' end;
    v_goal:='按自己的身份与目标继续行动';v_intent:='回应本次缘遇中的玩家选择';v_reason:='Cloudflare不可用，使用确定性的本地缘遇人格规则。';
  else
    v_dialogue:=case v_action when 'talk' then v_name||case v_temp when 'reserved' then '听完后只轻轻点头，但没有回避你的话。' when 'warm' then '认真听完，也与你多谈了几句。' when 'bold' then '笑着接过话头，回应得很直接。' else '与你谈了片刻，对你的印象又清晰了一些。' end when 'gift' then v_name||'收下了你的心意。礼物不会替代经历，但善意会被记住。' else '你与'||v_name||'同行了一段路，彼此有了新的共同经历。' end;
    v_goal:=coalesce(nullif(p_context#>>'{npc,private_goal}',''),'继续自己的修行与人生目标');v_intent:='根据当前关系保持自然往来';v_reason:='Cloudflare不可用，使用确定性的 server_personality_v1。';
  end if;
  return jsonb_build_object('proposal',jsonb_build_object('decision',v_decision,'dialogue',left(v_dialogue,500),'next_goal',left(v_goal,240),'action_intent',left(v_intent,240),'rationale',left(v_reason,360)),'engine','server_personality_v1');
exception when others then
  return jsonb_build_object('proposal',jsonb_build_object('decision','neutral','dialogue',v_name||'暂时没有多说什么。','next_goal','继续当前目标','action_intent','保持谨慎','rationale','本地人格兜底异常后的最小安全响应'),'engine','server_personality_v1');
end $$;

create or replace function public.tiandao_ai_runtime_settings_v259()
returns jsonb language sql stable security definer set search_path='' as $$
select jsonb_build_object('enabled',s.ai_enabled,'model',s.ai_model,'timeout_ms',s.ai_timeout_ms,'max_tokens',s.ai_max_tokens,'fallback','server_personality_v1')
from public.tiandao_people_settings_v259 s where s.singleton_id=1
$$;

create or replace function public.tiandao_ai_prepare_v259(
  p_user_id uuid,p_request_kind text,p_npc_id uuid,p_action text,p_message text default '',p_encounter_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_char uuid;s public.tiandao_people_settings_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;
  e public.tiandao_encounters_v259%rowtype;c public.tiandao_companions_v259%rowtype;v_last timestamptz;v_cd int;v_context jsonb;v_mem jsonb;v_world jsonb:='[]'::jsonb;v_ai_state jsonb:='{}'::jsonb;v_req uuid:=gen_random_uuid();v_existing uuid;
begin
  if p_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  select id into v_char from public.player_characters where user_id=p_user_id and status in('active','secluded','missing') order by created_at desc limit 1;
  if v_char is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  if not s.enabled then raise exception 'TIANDAO_DISABLED';end if;
  if p_request_kind not in('interaction','romance','encounter','companion') then raise exception 'TIANDAO_AI_REQUEST_KIND_INVALID';end if;
  p_action:=left(trim(coalesce(p_action,'')),60);p_message:=left(trim(coalesce(p_message,'')),300);

  if p_request_kind='encounter' then
    if not s.encounters_enabled then raise exception 'TIANDAO_ENCOUNTERS_DISABLED';end if;
    select * into e from public.tiandao_encounters_v259 where id=p_encounter_id and character_id=v_char;
    if e.id is null then raise exception 'TIANDAO_ENCOUNTER_NOT_FOUND';end if;
    if e.status<>'pending' then raise exception 'TIANDAO_ENCOUNTER_ALREADY_RESOLVED';end if;
    if e.expires_at<=clock_timestamp() then raise exception 'TIANDAO_ENCOUNTER_EXPIRED';end if;
    if p_action not in('approach','accept','observe','leave') then raise exception 'TIANDAO_ENCOUNTER_ACTION_INVALID';end if;
    p_npc_id:=e.npc_id;
  elsif p_request_kind='companion' then
    if not s.companion_enabled then raise exception 'TIANDAO_COMPANION_DISABLED';end if;
    if p_action not in('message','gift','meeting','joint_cultivation','protect') then raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
    select * into c from public.tiandao_companions_v259 where character_id=v_char and status='active';
    if c.character_id is null then raise exception 'TIANDAO_COMPANION_NOT_FOUND';end if;
    if c.last_action_at is not null and c.last_action_at+make_interval(secs=>s.companion_action_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_COMPANION_ACTION_COOLDOWN';end if;
    p_npc_id:=c.npc_id;
  else
    select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;
    if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
    select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=n.id;
    if r.npc_id is null or r.known_level='unknown' then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
    if p_request_kind='interaction' then
      if not s.interactions_enabled then raise exception 'TIANDAO_INTERACTIONS_DISABLED';end if;
      if p_action not in('talk','gift','meeting') then raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
      select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=v_char and npc_id=n.id and action_code=p_action;
      v_cd:=case p_action when 'talk' then s.talk_cooldown_seconds when 'gift' then s.gift_cooldown_seconds else s.meeting_cooldown_seconds end;
      if v_last is not null and v_last+make_interval(secs=>v_cd)>clock_timestamp() then raise exception 'TIANDAO_INTERACTION_COOLDOWN';end if;
    else
      if not s.romance_enabled then raise exception 'TIANDAO_ROMANCE_DISABLED';end if;
      if p_action<>'confess' then raise exception 'TIANDAO_ROMANCE_ACTION_INVALID';end if;
      if length(p_message)<1 then raise exception 'TIANDAO_CONFESSION_MESSAGE_INVALID';end if;
      if not n.romanceable then raise exception 'TIANDAO_ROMANCE_NPC_INVALID';end if;
      if r.known_level not in('acquainted','familiar','close') then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
      if r.affinity<s.confess_affinity_min or r.trust<s.confess_trust_min or r.intimacy<s.confess_intimacy_min or r.romance<s.confess_romance_min or r.hatred>=25 then raise exception 'TIANDAO_CONFESSION_REQUIREMENTS';end if;
      select npc_id into v_existing from public.tiandao_companions_v259 where character_id=v_char and status='active';
      if v_existing is not null and v_existing<>n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';end if;
      select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=v_char and npc_id=n.id and action_code='confess';
      if v_last is not null and v_last+make_interval(secs=>s.confess_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_CONFESSION_COOLDOWN';end if;
    end if;
  end if;

  select * into n from public.tiandao_npcs_v259 where id=p_npc_id and enabled;if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
  perform public.tiandao_ensure_relation_v259(v_char,n.id,case when p_request_kind='encounter' then 'heard' else 'unknown' end);
  select * into r from public.tiandao_relations_v259 where character_id=v_char and npc_id=n.id;
  select coalesce(jsonb_agg(jsonb_build_object('type',m.memory_type,'content',m.content,'importance',m.importance,'created_at',m.created_at) order by m.created_at desc),'[]'::jsonb) into v_mem
  from (select * from public.tiandao_memories_v259 where character_id=v_char and npc_id=n.id order by importance desc,created_at desc limit 12) m;
  if to_regclass('public.jiuxiao_world_events') is not null then
    begin execute 'select coalesce(jsonb_agg(jsonb_build_object(''type'',event_type,''title'',title,''content'',content,''level'',event_level,''created_at'',created_at) order by created_at desc),''[]''::jsonb) from (select event_type,title,content,event_level,created_at from public.jiuxiao_world_events order by created_at desc limit 5) x' into v_world;exception when others then v_world:='[]'::jsonb;end;
  end if;
  select coalesce(jsonb_build_object('next_goal',a.next_goal,'action_intent',a.action_intent,'last_dialogue',a.last_dialogue,'last_engine',a.last_engine,'updated_at',a.updated_at),'{}'::jsonb) into v_ai_state
  from public.tiandao_ai_state_v259 a where a.character_id=v_char and a.npc_id=n.id;
  v_ai_state:=coalesce(v_ai_state,'{}'::jsonb);
  v_context:=jsonb_build_object(
    'request_kind',p_request_kind,'action',p_action,'player_message',p_message,'server_time',clock_timestamp(),
    'player',jsonb_build_object('character_id',v_char,'name',(select name from public.player_characters where id=v_char)),
    'npc',jsonb_build_object('npc_id',n.id,'npc_code',n.npc_code,'name',n.name,'gender',n.gender,'age',n.age,'realm_label',n.realm_label,'identity',n.identity,'element',n.element,'public_profile',n.public_profile,'personality',n.personality,'private_goal',n.private_goal,'ai_notes',n.ai_notes,'romance_threshold',n.romance_threshold),
    'relation',jsonb_build_object('known_level',r.known_level,'affinity',r.affinity,'gratitude',r.gratitude,'hatred',r.hatred,'fear',r.fear,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'interaction_count',r.interaction_count,'current_status',r.current_status,'last_action',r.last_action),
    'memories',v_mem,'previous_ai_state',v_ai_state,'world_events',v_world,
    'hard_rules',jsonb_build_object('ai_may_modify_state',false,'ai_may_change_resources',false,'ai_may_decide_combat',false,'server_rules_are_authoritative',true)
  );
  insert into public.tiandao_ai_requests_v259(request_id,user_id,character_id,npc_id,request_kind,action_code,player_message,encounter_id,context_snapshot)
  values(v_req,p_user_id,v_char,n.id,p_request_kind,p_action,p_message,p_encounter_id,v_context);
  return jsonb_build_object('status','prepared','request_id',v_req,'ai',jsonb_build_object('enabled',s.ai_enabled,'model',s.ai_model,'timeout_ms',s.ai_timeout_ms,'max_tokens',s.ai_max_tokens),'context',v_context);
end $$;

create or replace function public.tiandao_ai_apply_v259(
  p_user_id uuid,p_request_id uuid,p_proposal jsonb,p_engine text,p_model text,p_latency_ms integer default 0,p_failure_reason text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  q public.tiandao_ai_requests_v259%rowtype;s public.tiandao_people_settings_v259%rowtype;n public.tiandao_npcs_v259%rowtype;r public.tiandao_relations_v259%rowtype;e public.tiandao_encounters_v259%rowtype;c public.tiandao_companions_v259%rowtype;
  v_last timestamptz;v_cd int;v_existing uuid;v_player text:='某位修士';v_decision text;v_ai_decision text;v_content text;v_reason text;v_next_goal text;v_intent text;
  v_score numeric;v_threshold numeric;v_jitter int;da int:=0;dg int:=0;dt int:=0;di int:=0;dr int:=0;v_cost bigint:=0;v_stage text;v_applied jsonb;
begin
  if p_user_id is null or p_request_id is null then raise exception 'AUTH_REQUIRED';end if;
  select * into q from public.tiandao_ai_requests_v259 where request_id=p_request_id for update;
  if q.request_id is null or q.user_id<>p_user_id then raise exception 'TIANDAO_AI_REQUEST_NOT_FOUND';end if;
  if q.status<>'prepared' then raise exception 'TIANDAO_AI_REQUEST_ALREADY_APPLIED';end if;
  if q.expires_at<=clock_timestamp() then update public.tiandao_ai_requests_v259 set status='expired' where request_id=q.request_id;raise exception 'TIANDAO_AI_REQUEST_EXPIRED';end if;
  select * into s from public.tiandao_people_settings_v259 where singleton_id=1;
  select * into n from public.tiandao_npcs_v259 where id=q.npc_id and enabled;if n.id is null then raise exception 'TIANDAO_NPC_NOT_FOUND';end if;
  select * into r from public.tiandao_relations_v259 where character_id=q.character_id and npc_id=n.id for update;
  if r.npc_id is null then raise exception 'TIANDAO_PERSON_NOT_KNOWN';end if;
  v_ai_decision:=lower(coalesce(p_proposal->>'decision','neutral'));if v_ai_decision not in('accept','defer','reject','neutral') then v_ai_decision:='neutral';end if;
  v_content:=left(trim(coalesce(p_proposal->>'dialogue','')),500);v_reason:=left(trim(coalesce(p_proposal->>'rationale','')),360);v_next_goal:=left(trim(coalesce(p_proposal->>'next_goal','')),240);v_intent:=left(trim(coalesce(p_proposal->>'action_intent','')),240);

  if q.request_kind='interaction' then
    if not s.enabled or not s.interactions_enabled then raise exception 'TIANDAO_INTERACTIONS_DISABLED';end if;
    select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=q.character_id and npc_id=n.id and action_code=q.action_code;
    v_cd:=case q.action_code when 'talk' then s.talk_cooldown_seconds when 'gift' then s.gift_cooldown_seconds else s.meeting_cooldown_seconds end;
    if v_last is not null and v_last+make_interval(secs=>v_cd)>clock_timestamp() then raise exception 'TIANDAO_INTERACTION_COOLDOWN';end if;
    if q.action_code='talk' then da:=case coalesce(n.personality->>'temperament','steady') when 'warm' then 3 when 'bright' then 3 when 'reserved' then 1 when 'stern' then 1 else 2 end;dt:=case when coalesce(n.personality->>'temperament','steady') in('calm','steady','gentle') then 2 else 1 end;di:=case when r.interaction_count>=3 then 1 else 0 end;
    elsif q.action_code='gift' then v_cost:=s.gift_spirit_stone_cost;if v_cost>0 then perform public.tianxu_inventory_adjust_v255(q.character_id,'spirit_stone',-v_cost);end if;da:=5;dg:=4;dt:=1;dr:=case when n.romanceable then 1 else 0 end;if coalesce(n.personality->>'gift_preference','') not in('','无') then da:=da+1;dg:=dg+1;end if;
    elsif q.action_code='meeting' then da:=4;dt:=3;di:=4;dr:=case when n.romanceable then 3 else 0 end;else raise exception 'TIANDAO_INTERACTION_ACTION_INVALID';end if;
    if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'与你有了一次新的互动。');end if;
    update public.tiandao_relations_v259 set known_level=case when known_level in('unknown','heard') then 'acquainted' when known_level='acquainted' and interaction_count>=4 then 'familiar' when known_level='familiar' and interaction_count>=12 then 'close' else known_level end,
      affinity=least(100,greatest(-100,affinity+da)),gratitude=least(100,greatest(0,gratitude+dg)),trust=least(100,greatest(0,trust+dt)),intimacy=least(100,greatest(0,intimacy+di)),romance=least(100,greatest(0,romance+dr)),interaction_count=interaction_count+1,last_interaction_at=clock_timestamp(),last_action=q.action_code,latest_rumor=v_content,current_status='你们最近仍有来往。',updated_at=clock_timestamp()
    where character_id=q.character_id and npc_id=n.id returning * into r;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,q.action_code,jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'spirit_stone_cost',v_cost),v_content);
    perform public.tiandao_add_memory_v259(q.character_id,n.id,q.action_code,v_content,case when q.action_code='meeting' then 2 else 1 end,true,jsonb_build_object('ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));
    v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,exists(select 1 from public.tiandao_companions_v259 where character_id=q.character_id and npc_id=n.id and status='active'));
    v_decision:='neutral';v_applied:=jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'spirit_stone_cost',v_cost,'relation_stage',v_stage);

  elsif q.request_kind='encounter' then
    if not s.enabled or not s.encounters_enabled then raise exception 'TIANDAO_ENCOUNTERS_DISABLED';end if;
    select * into e from public.tiandao_encounters_v259 where id=q.encounter_id and character_id=q.character_id for update;
    if e.id is null then raise exception 'TIANDAO_ENCOUNTER_NOT_FOUND';end if;if e.status<>'pending' then raise exception 'TIANDAO_ENCOUNTER_ALREADY_RESOLVED';end if;if e.expires_at<=clock_timestamp() then raise exception 'TIANDAO_ENCOUNTER_EXPIRED';end if;
    if q.action_code in('approach','accept') then da:=5;dt:=2;di:=1;dr:=case when n.romanceable then 1 else 0 end;elsif q.action_code='observe' then da:=1;dt:=1;elsif q.action_code<>'leave' then raise exception 'TIANDAO_ENCOUNTER_ACTION_INVALID';end if;
    if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),'这段缘遇有了新的结果。');end if;
    update public.tiandao_relations_v259 set known_level=case when q.action_code in('approach','accept') and known_level in('unknown','heard') then 'acquainted' else known_level end,affinity=least(100,greatest(-100,affinity+da)),trust=least(100,greatest(0,trust+dt)),intimacy=least(100,greatest(0,intimacy+di)),romance=least(100,greatest(0,romance+dr)),latest_rumor=v_content,current_status=case when q.action_code in('approach','accept') then '你们已经正式相识。' else current_status end,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id returning * into r;
    update public.tiandao_encounters_v259 set status='resolved',resolved_action=q.action_code,outcome=v_content,resolved_at=clock_timestamp() where id=e.id;
    if q.action_code in('approach','accept') then perform public.tiandao_add_memory_v259(q.character_id,n.id,'encounter',v_content,3,true,jsonb_build_object('encounter_id',e.id,'ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));end if;
    v_decision:='neutral';v_stage:=public.tiandao_relation_stage_v259(r.affinity,r.trust,r.intimacy,r.romance,r.hatred,false);v_applied:=jsonb_build_object('affinity',da,'trust',dt,'intimacy',di,'romance',dr,'relation_stage',v_stage);

  elsif q.request_kind='romance' then
    if not s.enabled or not s.romance_enabled then raise exception 'TIANDAO_ROMANCE_DISABLED';end if;
    if q.action_code<>'confess' or length(q.player_message)<1 then raise exception 'TIANDAO_ROMANCE_ACTION_INVALID';end if;
    if not n.romanceable or r.known_level not in('acquainted','familiar','close') then raise exception 'TIANDAO_ROMANCE_NPC_INVALID';end if;
    if r.affinity<s.confess_affinity_min or r.trust<s.confess_trust_min or r.intimacy<s.confess_intimacy_min or r.romance<s.confess_romance_min or r.hatred>=25 then raise exception 'TIANDAO_CONFESSION_REQUIREMENTS';end if;
    select npc_id into v_existing from public.tiandao_companions_v259 where character_id=q.character_id and status='active';if v_existing is not null and v_existing<>n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';elsif v_existing=n.id then raise exception 'TIANDAO_COMPANION_ALREADY_EXISTS';end if;
    select max(created_at) into v_last from public.tiandao_interaction_log_v259 where character_id=q.character_id and npc_id=n.id and action_code='confess';if v_last is not null and v_last+make_interval(secs=>s.confess_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_CONFESSION_COOLDOWN';end if;
    v_jitter:=(mod(mod(hashtextextended(q.character_id::text||':'||n.id::text||':'||date_trunc('hour',clock_timestamp())::text,259),11)+11,11)::int)-5;
    v_score:=r.affinity*0.32+r.trust*0.30+r.intimacy*0.24+r.romance*0.32+r.gratitude*0.08-r.hatred*0.55-r.fear*0.15+coalesce((n.personality->>'romance_openness')::numeric,50)*0.10+v_jitter;v_threshold:=n.romance_threshold;
    -- 服务端审核AI决策：未达到安全分段时不能靠AI越过规则强行accept。
    if v_score<v_threshold-10 then v_decision:='reject';elsif v_score<v_threshold and v_ai_decision='accept' then v_decision:='defer';elsif v_ai_decision in('accept','defer','reject') then v_decision:=v_ai_decision;elsif v_score>=v_threshold then v_decision:='defer';else v_decision:='reject';end if;
    if v_reason='' then v_reason:=case v_decision when 'accept' then 'AI提出接受，且通过服务端关系与分数规则审核。' when 'defer' then 'AI或服务端审核判断仍需更多共同经历。' else 'AI或服务端审核判断当前不接受。' end;end if;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,'confess',jsonb_build_object('score',v_score,'threshold',v_threshold,'ai_decision',v_ai_decision,'server_decision',v_decision),q.player_message);
    if v_decision='accept' then
      insert into public.tiandao_companions_v259(character_id,npc_id,status) values(q.character_id,n.id,'active') on conflict(character_id) do update set npc_id=excluded.npc_id,status='active',formed_at=clock_timestamp(),updated_at=clock_timestamp();
      if v_content='' then v_content:=n.name||'接受了你的心意。大道漫漫，你们从此以道侣之名同行。';end if;
      update public.tiandao_relations_v259 set known_level='close',affinity=greatest(affinity,80),trust=greatest(trust,70),intimacy=greatest(intimacy,70),romance=greatest(romance,85),current_status='你们已经正式结为道侣。',latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,'companion_formed',v_content,5,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));
      begin select name into v_player from public.player_characters where id=q.character_id;exception when others then v_player:='某位修士';end;
      perform public.tiandao_publish_world_event_v259('tiandao_companion_v259','仙缘既定',coalesce(nullif(v_player,''),'某位修士')||'与'||n.name||'因缘圆满，正式结为道侣。',3);
    elsif v_decision='defer' then
      if v_content='' then v_content:=n.name||'没有立刻拒绝，也没有草率答应，希望再多走一段路。';end if;
      update public.tiandao_relations_v259 set trust=least(100,trust+2),intimacy=least(100,intimacy+1),romance=least(100,romance+1),latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,'confession_defer',v_content,4,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));
    else
      if v_content='' then v_content:=n.name||'没有接受这份心意，但也没有让此前经历凭空消失。';end if;
      update public.tiandao_relations_v259 set romance=greatest(0,romance-5),latest_rumor=v_content,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
      perform public.tiandao_add_memory_v259(q.character_id,n.id,'confession_reject',v_content,4,true,jsonb_build_object('message',q.player_message,'ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));
    end if;
    v_applied:=jsonb_build_object('ai_decision',v_ai_decision,'server_decision',v_decision,'score',v_score,'threshold',v_threshold,'companion_formed',(v_decision='accept'));

  elsif q.request_kind='companion' then
    if not s.enabled or not s.companion_enabled then raise exception 'TIANDAO_COMPANION_DISABLED';end if;
    select * into c from public.tiandao_companions_v259 where character_id=q.character_id and npc_id=n.id and status='active' for update;if c.character_id is null then raise exception 'TIANDAO_COMPANION_NOT_FOUND';end if;
    if c.last_action_at is not null and c.last_action_at+make_interval(secs=>s.companion_action_cooldown_seconds)>clock_timestamp() then raise exception 'TIANDAO_COMPANION_ACTION_COOLDOWN';end if;
    if q.action_code='message' then dt:=2;di:=2;dr:=1;elsif q.action_code='gift' then v_cost:=s.companion_gift_spirit_stone_cost;if v_cost>0 then perform public.tianxu_inventory_adjust_v255(q.character_id,'spirit_stone',-v_cost);end if;da:=3;dg:=4;di:=2;dr:=2;elsif q.action_code='meeting' then da:=3;dt:=3;di:=4;dr:=3;elsif q.action_code='joint_cultivation' then dt:=4;di:=5;dr:=3;elsif q.action_code='protect' then dt:=5;di:=3;dr:=2;else raise exception 'TIANDAO_COMPANION_ACTION_INVALID';end if;
    if v_content='' then v_content:=coalesce((public.server_personality_v1(q.context_snapshot)->'proposal'->>'dialogue'),n.name||'回应了这次道侣互动。');end if;
    update public.tiandao_relations_v259 set affinity=least(100,affinity+da),gratitude=least(100,gratitude+dg),trust=least(100,trust+dt),intimacy=least(100,intimacy+di),romance=least(100,romance+dr),known_level='close',current_status='你们以道侣之名继续各自修行，也彼此牵挂。',latest_rumor=v_content,last_interaction_at=clock_timestamp(),last_action='companion_'||q.action_code,interaction_count=interaction_count+1,updated_at=clock_timestamp() where character_id=q.character_id and npc_id=n.id;
    update public.tiandao_companions_v259 set last_action_at=clock_timestamp(),bond_level=least(10,bond_level+case when q.action_code in('meeting','joint_cultivation','protect') then 1 else 0 end),updated_at=clock_timestamp() where character_id=q.character_id;
    insert into public.tiandao_interaction_log_v259(character_id,npc_id,action_code,deltas,content) values(q.character_id,n.id,'companion_'||q.action_code,jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'spirit_stone_cost',v_cost),v_content);
    perform public.tiandao_add_memory_v259(q.character_id,n.id,'companion_'||q.action_code,v_content,case when q.action_code in('joint_cultivation','protect') then 3 else 2 end,true,jsonb_build_object('ai_engine',p_engine,'next_goal',v_next_goal,'action_intent',v_intent));
    v_decision:='neutral';v_applied:=jsonb_build_object('affinity',da,'gratitude',dg,'trust',dt,'intimacy',di,'romance',dr,'spirit_stone_cost',v_cost);
  else raise exception 'TIANDAO_AI_REQUEST_KIND_INVALID';end if;

  insert into public.tiandao_ai_state_v259(character_id,npc_id,next_goal,action_intent,last_dialogue,last_engine,last_model,updated_at)
  values(q.character_id,n.id,left(coalesce(v_next_goal,''),240),left(coalesce(v_intent,''),240),left(coalesce(v_content,''),500),left(coalesce(p_engine,''),80),left(coalesce(p_model,''),160),clock_timestamp())
  on conflict(character_id,npc_id) do update set
    next_goal=coalesce(nullif(excluded.next_goal,''),public.tiandao_ai_state_v259.next_goal),
    action_intent=coalesce(nullif(excluded.action_intent,''),public.tiandao_ai_state_v259.action_intent),
    last_dialogue=coalesce(nullif(excluded.last_dialogue,''),public.tiandao_ai_state_v259.last_dialogue),
    last_engine=excluded.last_engine,last_model=excluded.last_model,updated_at=clock_timestamp();

  insert into public.tiandao_ai_decisions_v259(character_id,npc_id,request_id,decision_type,engine,model,decision,score,threshold,rationale,latency_ms,failure_reason,proposal,applied)
  values(q.character_id,n.id,q.request_id,q.request_kind||':'||q.action_code,left(coalesce(nullif(p_engine,''),'server_personality_v1'),80),left(coalesce(nullif(p_model,''),s.ai_model),160),coalesce(v_decision,'neutral'),v_score,v_threshold,left(coalesce(v_reason,''),600),greatest(0,coalesce(p_latency_ms,0)),left(coalesce(p_failure_reason,''),800),coalesce(p_proposal,'{}'::jsonb),coalesce(v_applied,'{}'::jsonb));
  update public.tiandao_ai_requests_v259 set status='applied',applied_at=clock_timestamp() where request_id=q.request_id;
  return jsonb_build_object('status','ok','content',v_content,'decision',coalesce(v_decision,'neutral'),'reason',v_reason,'relation_stage',v_stage,'spirit_stone_cost',v_cost,'engine',p_engine,'model',coalesce(nullif(p_model,''),s.ai_model),'ai_latency_ms',greatest(0,coalesce(p_latency_ms,0)),'ai_failure_reason',nullif(left(coalesce(p_failure_reason,''),800),''));
end $$;

-- ---------- ADMIN9 RPC ----------
create or replace function public.admin9_get_tiandao_people_v259()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_settings jsonb;v_npcs jsonb;v_rel jsonb;v_enc jsonb;v_comp jsonb;v_audit jsonb;v_ai jsonb;v_ai_runtime jsonb;
begin
  perform public.admin_whoami_v1();
  select to_jsonb(s) into v_settings from public.tiandao_people_settings_v259 s where singleton_id=1;
  select coalesce(jsonb_agg(to_jsonb(n) order by n.core_ai desc,n.romanceable desc,n.npc_code),'[]'::jsonb) into v_npcs from public.tiandao_npcs_v259 n;
  select coalesce(jsonb_agg(x.obj order by x.updated_at desc),'[]'::jsonb) into v_rel from(
    select r.updated_at,jsonb_build_object('character_id',r.character_id,'character_name',pc.name,'npc_id',r.npc_id,'npc_name',n.name,'known_level',r.known_level,'affinity',r.affinity,'gratitude',r.gratitude,'hatred',r.hatred,'fear',r.fear,'trust',r.trust,'intimacy',r.intimacy,'romance',r.romance,'interaction_count',r.interaction_count,'private_goal',n.private_goal,'ai_notes',n.ai_notes,'updated_at',r.updated_at) obj
    from public.tiandao_relations_v259 r join public.tiandao_npcs_v259 n on n.id=r.npc_id left join public.player_characters pc on pc.id=r.character_id order by r.updated_at desc limit 100
  ) x;
  select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) into v_enc from(
    select e.created_at,jsonb_build_object('id',e.id,'character_id',e.character_id,'character_name',pc.name,'npc_name',n.name,'title',e.title,'status',e.status,'resolved_action',e.resolved_action,'outcome',e.outcome,'created_at',e.created_at) obj
    from public.tiandao_encounters_v259 e join public.tiandao_npcs_v259 n on n.id=e.npc_id left join public.player_characters pc on pc.id=e.character_id order by e.created_at desc limit 100
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('character_id',c.character_id,'character_name',pc.name,'npc_id',c.npc_id,'npc_name',n.name,'status',c.status,'bond_level',c.bond_level,'formed_at',c.formed_at) order by c.formed_at desc),'[]'::jsonb) into v_comp
  from public.tiandao_companions_v259 c join public.tiandao_npcs_v259 n on n.id=c.npc_id left join public.player_characters pc on pc.id=c.character_id;
  select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at desc),'[]'::jsonb) into v_audit from (select * from public.tiandao_admin_audit_v259 order by created_at desc limit 50) a;
  select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'request_id',d.request_id,'character_id',d.character_id,'character_name',pc.name,'npc_name',n.name,'decision_type',d.decision_type,'engine',d.engine,'model',d.model,'decision',d.decision,'latency_ms',d.latency_ms,'failure_reason',nullif(d.failure_reason,''),'rationale',d.rationale,'created_at',d.created_at) order by d.created_at desc),'[]'::jsonb) into v_ai
  from (select * from public.tiandao_ai_decisions_v259 order by created_at desc limit 50) d join public.tiandao_npcs_v259 n on n.id=d.npc_id left join public.player_characters pc on pc.id=d.character_id;
  select jsonb_build_object(
    'configured',true,'enabled',s.ai_enabled,'model',s.ai_model,'fallback','server_personality_v1',
    'last_engine',(select d.engine from public.tiandao_ai_decisions_v259 d order by d.created_at desc limit 1),
    'status',coalesce((select case when d.engine='cloudflare_workers_ai' then 'Cloudflare' else '本地Fallback' end from public.tiandao_ai_decisions_v259 d order by d.created_at desc limit 1),'待首次调用'),
    'last_latency_ms',coalesce((select d.latency_ms from public.tiandao_ai_decisions_v259 d order by d.created_at desc limit 1),0),
    'last_failure_reason',(select nullif(d.failure_reason,'') from public.tiandao_ai_decisions_v259 d order by d.created_at desc limit 1),
    'cloudflare_24h',(select count(*) from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours' and d.engine='cloudflare_workers_ai'),
    'fallback_24h',(select count(*) from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours' and d.engine='server_personality_v1')
  ) into v_ai_runtime from public.tiandao_people_settings_v259 s where singleton_id=1;
  return jsonb_build_object('status','ok','settings',v_settings,'ai_runtime',v_ai_runtime,'recent_ai_decisions',v_ai,'counts',jsonb_build_object('npc_total',(select count(*) from public.tiandao_npcs_v259),'core_ai',(select count(*) from public.tiandao_npcs_v259 where core_ai),'romanceable',(select count(*) from public.tiandao_npcs_v259 where romanceable),'relations',(select count(*) from public.tiandao_relations_v259),'pending_encounters',(select count(*) from public.tiandao_encounters_v259 where status='pending' and expires_at>clock_timestamp()),'active_companions',(select count(*) from public.tiandao_companions_v259 where status='active')),'npcs',v_npcs,'recent_relations',v_rel,'recent_encounters',v_enc,'companions',v_comp,'audit',v_audit);
end $$;

create or replace function public.admin9_update_tiandao_settings_v259(p_patch jsonb,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before jsonb;v_after jsonb;
begin
  perform public.admin_whoami_v1();
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
  if length(trim(coalesce(p_reason,'')))<2 then raise exception 'ADMIN_REASON_REQUIRED';end if;
  if exists(select 1 from public.tiandao_admin_audit_v259 where request_id=p_request_id) then select after_data into v_after from public.tiandao_admin_audit_v259 where request_id=p_request_id;return coalesce(v_after,'{}'::jsonb)||jsonb_build_object('duplicate_request',true);end if;
  select to_jsonb(s) into v_before from public.tiandao_people_settings_v259 s where singleton_id=1 for update;
  update public.tiandao_people_settings_v259 set
    enabled=coalesce((p_patch->>'enabled')::boolean,enabled),encounters_enabled=coalesce((p_patch->>'encounters_enabled')::boolean,encounters_enabled),interactions_enabled=coalesce((p_patch->>'interactions_enabled')::boolean,interactions_enabled),romance_enabled=coalesce((p_patch->>'romance_enabled')::boolean,romance_enabled),companion_enabled=coalesce((p_patch->>'companion_enabled')::boolean,companion_enabled),
    encounter_interval_minutes=coalesce((p_patch->>'encounter_interval_minutes')::integer,encounter_interval_minutes),max_pending_encounters=coalesce((p_patch->>'max_pending_encounters')::integer,max_pending_encounters),
    talk_cooldown_seconds=coalesce((p_patch->>'talk_cooldown_seconds')::integer,talk_cooldown_seconds),gift_cooldown_seconds=coalesce((p_patch->>'gift_cooldown_seconds')::integer,gift_cooldown_seconds),meeting_cooldown_seconds=coalesce((p_patch->>'meeting_cooldown_seconds')::integer,meeting_cooldown_seconds),confess_cooldown_seconds=coalesce((p_patch->>'confess_cooldown_seconds')::integer,confess_cooldown_seconds),companion_action_cooldown_seconds=coalesce((p_patch->>'companion_action_cooldown_seconds')::integer,companion_action_cooldown_seconds),
    gift_spirit_stone_cost=coalesce((p_patch->>'gift_spirit_stone_cost')::bigint,gift_spirit_stone_cost),companion_gift_spirit_stone_cost=coalesce((p_patch->>'companion_gift_spirit_stone_cost')::bigint,companion_gift_spirit_stone_cost),
    confess_affinity_min=coalesce((p_patch->>'confess_affinity_min')::integer,confess_affinity_min),confess_trust_min=coalesce((p_patch->>'confess_trust_min')::integer,confess_trust_min),confess_intimacy_min=coalesce((p_patch->>'confess_intimacy_min')::integer,confess_intimacy_min),confess_romance_min=coalesce((p_patch->>'confess_romance_min')::integer,confess_romance_min),ai_enabled=coalesce((p_patch->>'ai_enabled')::boolean,ai_enabled),ai_timeout_ms=coalesce((p_patch->>'ai_timeout_ms')::integer,ai_timeout_ms),ai_max_tokens=coalesce((p_patch->>'ai_max_tokens')::integer,ai_max_tokens),updated_at=clock_timestamp()
  where singleton_id=1;
  select to_jsonb(s) into v_after from public.tiandao_people_settings_v259 s where singleton_id=1;
  insert into public.tiandao_admin_audit_v259(admin_user_id,action_code,before_data,after_data,reason,request_id) values(auth.uid(),'settings_update',v_before,v_after,trim(p_reason),p_request_id);
  return jsonb_build_object('status','ok','settings',v_after);
exception when check_violation or invalid_text_representation then raise exception 'TIANDAO_SETTINGS_INVALID';end $$;

create or replace function public.admin9_check_tiandao_people_v259()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old_exposed integer;v_table_exposed integer;v_direct_actions_exposed integer;v_internal_exposed integer;
begin
  perform public.admin_whoami_v1();
  select count(*) into v_old_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';
  select count(*) into v_table_exposed from information_schema.table_privileges where table_schema='public' and table_name like 'tiandao\_%\_v259' escape E'\\' and grantee in('anon','authenticated','PUBLIC');
  select count(*) into v_direct_actions_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('resolve_tiandao_encounter_v1','tiandao_npc_interact_v1','tiandao_romance_action_v1','tiandao_companion_action_v1') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';
  select count(*) into v_internal_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('server_personality_v1','tiandao_ai_runtime_settings_v259','tiandao_ai_prepare_v259','tiandao_ai_apply_v259') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';
  return jsonb_build_object('status',case when (select count(*) from public.tiandao_npcs_v259)=50 and (select count(*) from public.tiandao_npcs_v259 where core_ai)=20 and (select count(*) from public.tiandao_npcs_v259 where romanceable)=30 and v_old_exposed=0 and v_table_exposed=0 and v_direct_actions_exposed=0 and v_internal_exposed=0 and to_regprocedure('public.server_personality_v1(jsonb)') is not null and to_regprocedure('public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)') is not null and to_regprocedure('public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)') is not null then 'PASS' else 'FAIL' end,
    'npc_total',(select count(*) from public.tiandao_npcs_v259),'core_ai',(select count(*) from public.tiandao_npcs_v259 where core_ai),'romanceable',(select count(*) from public.tiandao_npcs_v259 where romanceable),'romance_female',(select count(*) from public.tiandao_npcs_v259 where romanceable and gender='female'),'romance_male',(select count(*) from public.tiandao_npcs_v259 where romanceable and gender='male'),'underage',(select count(*) from public.tiandao_npcs_v259 where age<18),'legacy_player_rpc_exposed',v_old_exposed,'raw_table_privileges',v_table_exposed,'direct_action_rpc_exposed',v_direct_actions_exposed,'ai_internal_rpc_exposed',v_internal_exposed,
    'player_read_rpc_count',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in('get_tiandao_people_hub_v1','get_tiandao_person_detail_v1')),
    'ai_model',(select ai_model from public.tiandao_people_settings_v259 where singleton_id=1),'fallback_function','server_personality_v1');
end $$;

-- ---------- PERMISSIONS ----------
-- 新天道表禁止前端直接SELECT/INSERT/UPDATE/DELETE；玩家只可调用经过审计的RPC，避免读取NPC隐藏目标、仇恨精确值和AI内部备注。
do $permissions$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname='public' and tablename like 'tiandao\_%\_v259' escape E'\\' loop
    execute format('alter table public.%I enable row level security',r.tablename);
    execute format('revoke all on table public.%I from anon,authenticated,public',r.tablename);
  end loop;
  -- 旧红尘RPC保留历史实现，但玩家端执行权限彻底撤销；新版客户端也不再调用。
  for r in
    select format('%I.%I(%s)',n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)) sig
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in('get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1')
  loop
    execute format('revoke execute on function %s from anon, authenticated, public',r.sig);
  end loop;
end
$permissions$;

revoke all on function public.tiandao_relation_stage_v259(integer,integer,integer,integer,integer,boolean) from public,anon,authenticated;
revoke all on function public.tiandao_public_attitude_v259(text) from public,anon,authenticated;
revoke all on function public.tiandao_ensure_relation_v259(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb) from public,anon,authenticated;
revoke all on function public.tiandao_publish_world_event_v259(text,text,text,integer) from public,anon,authenticated;
revoke all on function public.tiandao_seed_visibility_v259(uuid) from public,anon,authenticated;
revoke all on function public.tiandao_maybe_spawn_encounter_v259(uuid,text) from public,anon,authenticated;
revoke all on function public.server_personality_v1(jsonb) from public,anon,authenticated;
revoke all on function public.tiandao_ai_runtime_settings_v259() from public,anon,authenticated;
revoke all on function public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text) from public,anon,authenticated;

-- PostgreSQL 新建函数默认可能向 PUBLIC 授予 EXECUTE；先显式撤权，再只开放给 authenticated。
revoke all on function public.get_tiandao_people_hub_v1() from public,anon,authenticated;
revoke all on function public.get_tiandao_person_detail_v1(uuid) from public,anon,authenticated;
revoke all on function public.resolve_tiandao_encounter_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.tiandao_npc_interact_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.tiandao_romance_action_v1(uuid,text,text) from public,anon,authenticated;
revoke all on function public.tiandao_companion_action_v1(text) from public,anon,authenticated;
revoke all on function public.admin9_get_tiandao_people_v259() from public,anon,authenticated;
revoke all on function public.admin9_update_tiandao_settings_v259(jsonb,text,uuid) from public,anon,authenticated;
revoke all on function public.admin9_check_tiandao_people_v259() from public,anon,authenticated;

grant execute on function public.get_tiandao_people_hub_v1() to authenticated;
grant execute on function public.get_tiandao_person_detail_v1(uuid) to authenticated;

grant execute on function public.server_personality_v1(jsonb) to service_role;
grant execute on function public.tiandao_ai_runtime_settings_v259() to service_role;
grant execute on function public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid) to service_role;
grant execute on function public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text) to service_role;

grant execute on function public.admin9_get_tiandao_people_v259() to authenticated;
grant execute on function public.admin9_update_tiandao_settings_v259(jsonb,text,uuid) to authenticated;
grant execute on function public.admin9_check_tiandao_people_v259() to authenticated;

-- ---------- FINAL GATE ----------
do $gate$
declare v_old_exposed integer;v_table_exposed integer;v_direct_actions_exposed integer;v_internal_exposed integer;
begin
  if (select count(*) from public.tiandao_npcs_v259)<>50 then raise exception 'SQL259_GATE_NPC_TOTAL_NOT_50';end if;
  if (select count(*) from public.tiandao_npcs_v259 where core_ai)<>20 then raise exception 'SQL259_GATE_CORE_AI_NOT_20';end if;
  if (select count(*) from public.tiandao_npcs_v259 where romanceable)<>30 then raise exception 'SQL259_GATE_ROMANCEABLE_NOT_30';end if;
  if (select count(*) from public.tiandao_npcs_v259 where romanceable and gender='female')<>20 then raise exception 'SQL259_GATE_ROMANCE_FEMALE_NOT_20';end if;
  if (select count(*) from public.tiandao_npcs_v259 where romanceable and gender='male')<>10 then raise exception 'SQL259_GATE_ROMANCE_MALE_NOT_10';end if;
  if exists(select 1 from public.tiandao_npcs_v259 where age<18) then raise exception 'SQL259_GATE_UNDERAGE_NPC';end if;
  if (select ai_model from public.tiandao_people_settings_v259 where singleton_id=1)<>'@cf/qwen/qwen3-30b-a3b-fp8' then raise exception 'SQL259_GATE_AI_MODEL_MISMATCH';end if;
  if to_regprocedure('public.server_personality_v1(jsonb)') is null then raise exception 'SQL259_GATE_FALLBACK_MISSING';end if;
  if to_regprocedure('public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)') is null or to_regprocedure('public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)') is null then raise exception 'SQL259_GATE_AI_INTERNAL_RPC_MISSING';end if;
  select count(*) into v_old_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';if v_old_exposed<>0 then raise exception 'SQL259_GATE_LEGACY_SOCIAL_RPC_STILL_EXPOSED:%',v_old_exposed;end if;
  select count(*) into v_table_exposed from information_schema.table_privileges where table_schema='public' and table_name like 'tiandao\_%\_v259' escape E'\\' and grantee in('anon','authenticated','PUBLIC');if v_table_exposed<>0 then raise exception 'SQL259_GATE_RAW_TABLE_PRIVILEGE_EXPOSED:%',v_table_exposed;end if;
  select count(*) into v_direct_actions_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('resolve_tiandao_encounter_v1','tiandao_npc_interact_v1','tiandao_romance_action_v1','tiandao_companion_action_v1') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';if v_direct_actions_exposed<>0 then raise exception 'SQL259_GATE_DIRECT_ACTION_RPC_EXPOSED:%',v_direct_actions_exposed;end if;
  select count(*) into v_internal_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name in('server_personality_v1','tiandao_ai_runtime_settings_v259','tiandao_ai_prepare_v259','tiandao_ai_apply_v259') and grantee in('anon','authenticated','PUBLIC') and privilege_type='EXECUTE';if v_internal_exposed<>0 then raise exception 'SQL259_GATE_AI_INTERNAL_RPC_EXPOSED:%',v_internal_exposed;end if;
  if not has_function_privilege('authenticated','public.get_tiandao_people_hub_v1()','EXECUTE') or not has_function_privilege('authenticated','public.get_tiandao_person_detail_v1(uuid)','EXECUTE') then raise exception 'SQL259_GATE_PLAYER_READ_RPC_MISSING';end if;
  if has_function_privilege('authenticated','public.tiandao_romance_action_v1(uuid,text,text)','EXECUTE') then raise exception 'SQL259_GATE_DIRECT_ROMANCE_BYPASS';end if;
  if not has_function_privilege('service_role','public.tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)','EXECUTE') or not has_function_privilege('service_role','public.tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)','EXECUTE') then raise exception 'SQL259_GATE_SERVICE_AI_EXECUTE_MISSING';end if;
  if to_regprocedure('public.admin9_check_tiandao_people_v259()') is null then raise exception 'SQL259_GATE_ADMIN_CHECK_MISSING';end if;
end
$gate$;

commit;

select jsonb_build_object(
  'sql',259,
  'gate','SQL259_GATE_PASSED',
  'release','V2.2.0 CACHE129',
  'module','天道人物 / 缘遇 / 人物志 / 仙缘 / 道侣',
  'npc_total',50,
  'core_ai',20,
  'romanceable','30（女20 / 男10 / 全部成年）',
  'legacy_social','旧红尘玩家RPC已撤权；历史数据保留归档',
  'ai_engine','Cloudflare Workers AI 优先；失败/超时自动 server_personality_v1 fallback',
  'model','@cf/qwen/qwen3-30b-a3b-fp8',
  'edge_function','tiandao-ai',
  'next_sql',260
) as sql259_install_result;
