-- 九霄问道 B线候选模块：机缘V4动态内容、在线离线统一5分钟、离线汇总
-- 基线：V0.14.4_AB2 / Web Alpha V0.14.4 CACHE8
-- 状态：ready_for_integration；由A线审核、执行、合并与定版。
begin;

create extension if not exists pgcrypto;

-- 内容池：触发文案与结果模板分离。
create table if not exists public.opportunity_v4_story_pool(
  code text primary key,
  grade text not null check(grade in('黄品','玄品','地品','天品','仙品','专属')),
  polarity text not null check(polarity in('auspicious','risk')),
  sequence integer not null,
  title text not null,
  story text not null,
  weight numeric not null default 1 check(weight>0),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(grade,polarity,sequence)
);

create table if not exists public.opportunity_v4_result_pool(
  code text primary key,
  grade text not null check(grade in('黄品','玄品','地品','天品','仙品','专属')),
  polarity text not null check(polarity in('auspicious','risk')),
  sequence integer not null,
  title text not null,
  narrative text not null,
  effect_spec jsonb not null default '{}'::jsonb,
  weight numeric not null default 1 check(weight>0),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(grade,polarity,sequence)
);

-- 一次离线结算只生成一个汇总批次；弹窗确认只做已读，不重复发奖。
create table if not exists public.opportunity_v4_settlement_batches(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  period_started_at timestamptz not null,
  period_ended_at timestamptz not null,
  event_count integer not null default 0,
  is_offline boolean not null default false,
  capped_event_count integer not null default 0,
  grade_counts jsonb not null default '{}'::jsonb,
  polarity_counts jsonb not null default '{}'::jsonb,
  gains jsonb not null default '{}'::jsonb,
  losses jsonb not null default '{}'::jsonb,
  net_result jsonb not null default '{}'::jsonb,
  remaining_effects jsonb not null default '[]'::jsonb,
  cultivation_claim jsonb,
  shown_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_opportunity_v4_batches_unshown
  on public.opportunity_v4_settlement_batches(character_id,created_at desc)
  where shown_at is null;

alter table public.opportunity_v3_results add column if not exists settlement_batch_id uuid references public.opportunity_v4_settlement_batches(id) on delete set null;
alter table public.opportunity_v3_results add column if not exists scheduled_at timestamptz;

-- 统一5分钟；最多补算72小时=864次，避免长期离线造成无限循环。
update public.opportunity_v3_settings
set online_interval_seconds=300,
    offline_interval_seconds=300,
    offline_catchup_limit=864,
    first_interval_seconds=300,
    updated_at=now()
where world_code='jiuxiao_world_1';

-- 内容种子：普通五品各20触发+20结果，专属亦为20触发+20结果。
insert into public.opportunity_v4_story_pool(code,grade,polarity,sequence,title,story,weight)
select x.code,x.grade,x.polarity,x.sequence,x.title,x.story,x.weight
from jsonb_to_recordset('[{"code":"yellow_auspicious_01","grade":"黄品","polarity":"auspicious","sequence":1,"title":"灵露凝叶","story":"你沿山间小径而行，忽见路旁草叶上凝着几滴久久不散的灵露。","weight":1},{"code":"yellow_auspicious_02","grade":"黄品","polarity":"auspicious","sequence":2,"title":"灵鱼逆流","story":"你在溪边歇息时，发现几尾灵鱼逆流而上，游动间隐约暗合吐纳之法。","weight":1},{"code":"yellow_auspicious_03","grade":"黄品","polarity":"auspicious","sequence":3,"title":"落叶成图","story":"一阵清风掠过林间，几片落叶在你面前盘旋成一个古怪的图案。","weight":1},{"code":"yellow_auspicious_04","grade":"黄品","polarity":"auspicious","sequence":4,"title":"荒亭残棋","story":"你经过一座荒废小亭，亭中石桌上留着一盘尚未下完的残棋。","weight":1},{"code":"yellow_auspicious_05","grade":"黄品","polarity":"auspicious","sequence":5,"title":"古旧铜钱","story":"你在整理行囊时，发现一枚不知何时混入其中的古旧铜钱。","weight":1},{"code":"yellow_auspicious_06","grade":"黄品","polarity":"auspicious","sequence":6,"title":"雨后灵光","story":"山雨过后，一道微弱灵光从湿润的石缝中透出。","weight":1},{"code":"yellow_auspicious_07","grade":"黄品","polarity":"auspicious","sequence":7,"title":"散修点拨","story":"一名过路散修与你短暂交谈，临别时随口点出了你修炼中的一处疑惑。","weight":1},{"code":"yellow_auspicious_08","grade":"黄品","polarity":"auspicious","sequence":8,"title":"梦闻道音","story":"你夜宿山脚，半梦半醒间听见远处传来若有若无的诵经声。","weight":1},{"code":"yellow_auspicious_09","grade":"黄品","polarity":"auspicious","sequence":9,"title":"白兽引路","story":"一只通体雪白的小兽在远处注视你片刻，随后消失在林间。","weight":1},{"code":"yellow_auspicious_10","grade":"黄品","polarity":"auspicious","sequence":10,"title":"温润石片","story":"你在河滩拾起一块温润石片，握在手中时心神竟逐渐平静下来。","weight":1},{"code":"yellow_risk_01","grade":"黄品","polarity":"risk","sequence":1,"title":"荒草异动","story":"你踏入一片荒草地时，脚下忽然传来细微震动。","weight":1},{"code":"yellow_risk_02","grade":"黄品","polarity":"risk","sequence":2,"title":"林中兽吼","story":"林中传来低沉兽吼，附近鸟雀顷刻间四散而逃。","weight":1},{"code":"yellow_risk_03","grade":"黄品","polarity":"risk","sequence":3,"title":"破庙自开","story":"你经过一座破庙，庙门却在无风时自行缓缓打开。","weight":1},{"code":"yellow_risk_04","grade":"黄品","polarity":"risk","sequence":4,"title":"枯井灰雾","story":"一缕灰黑雾气从路旁枯井中升起，久久不散。","weight":1},{"code":"yellow_risk_05","grade":"黄品","polarity":"risk","sequence":5,"title":"染血修士","story":"你发现路边倒着一名气息微弱的修士，但他的衣襟上沾着陌生血迹。","weight":1},{"code":"yellow_risk_06","grade":"黄品","polarity":"risk","sequence":6,"title":"水中倒影","story":"你在溪流中洗手时，水面忽然倒映出一个并不存在的人影。","weight":1},{"code":"yellow_risk_07","grade":"黄品","polarity":"risk","sequence":7,"title":"阴风凝气","story":"一阵阴冷山风吹过，你体内灵力出现了短暂凝滞。","weight":1},{"code":"yellow_risk_08","grade":"黄品","polarity":"risk","sequence":8,"title":"残阵误触","story":"你误触一块隐藏在泥土中的残破阵盘，四周灵气顿时紊乱。","weight":1},{"code":"yellow_risk_09","grade":"黄品","polarity":"risk","sequence":9,"title":"伤兽警戒","story":"一只受伤妖兽倒在岩石旁，却仍警惕地盯着你的方向。","weight":1},{"code":"yellow_risk_10","grade":"黄品","polarity":"risk","sequence":10,"title":"夜影尾随","story":"夜色中，一道模糊身影始终与你保持着不远不近的距离。","weight":1},{"code":"mystic_auspicious_01","grade":"玄品","polarity":"auspicious","sequence":1,"title":"洞府残碑","story":"你在一处废弃洞府中发现半面残碑，其上仍残留着前人悟道的气息。","weight":1},{"code":"mystic_auspicious_02","grade":"玄品","polarity":"auspicious","sequence":2,"title":"悬崖灵药","story":"一株散发淡蓝微光的灵药生长在悬崖石缝之间。","weight":1},{"code":"mystic_auspicious_03","grade":"玄品","polarity":"auspicious","sequence":3,"title":"道人论道","story":"你偶遇一名云游道人，对方在与你论道后留下了一句意味深长的话。","weight":1},{"code":"mystic_auspicious_04","grade":"玄品","polarity":"auspicious","sequence":4,"title":"残阵引路","story":"一道破损阵纹在你经过时突然复苏，似乎在引导你前往某处。","weight":1},{"code":"mystic_auspicious_05","grade":"玄品","polarity":"auspicious","sequence":5,"title":"山洞灵泉","story":"你在山洞深处发现了一口尚未完全干涸的灵泉。","weight":1},{"code":"mystic_auspicious_06","grade":"玄品","polarity":"auspicious","sequence":6,"title":"灵兽赠玉","story":"一只低阶灵兽主动靠近，将一块沾有灵气的碎玉放在你面前。","weight":1},{"code":"mystic_auspicious_07","grade":"玄品","polarity":"auspicious","sequence":7,"title":"古树札记","story":"你在古树树洞中发现了一卷字迹模糊的修炼札记。","weight":1},{"code":"mystic_auspicious_08","grade":"玄品","polarity":"auspicious","sequence":8,"title":"流星坠谷","story":"夜空中一颗流星坠落在附近山谷，落点处灵气久久不散。","weight":1},{"code":"mystic_auspicious_09","grade":"玄品","polarity":"auspicious","sequence":9,"title":"遗址钟鸣","story":"一阵钟声从废弃宗门遗址深处传出，却没有任何人影出现。","weight":1},{"code":"mystic_auspicious_10","grade":"玄品","polarity":"auspicious","sequence":10,"title":"石壁行功图","story":"你在石壁上发现一幅残缺行功图，其中部分路线与你当前功法隐约相合。","weight":1},{"code":"mystic_risk_01","grade":"玄品","polarity":"risk","sequence":1,"title":"密林求救","story":"一道微弱求救声从密林深处传来，四周却安静得异常。","weight":1},{"code":"mystic_risk_02","grade":"玄品","polarity":"risk","sequence":2,"title":"石门封闭","story":"你刚进入废弃洞府，身后的石门便轰然关闭。","weight":1},{"code":"mystic_risk_03","grade":"玄品","polarity":"risk","sequence":3,"title":"妖兽守药","story":"一只盘踞在灵药附近的妖兽突然睁开双眼。","weight":1},{"code":"mystic_risk_04","grade":"玄品","polarity":"risk","sequence":4,"title":"残碑神念","story":"你触碰残碑时，其中封存的混乱神念猛然涌入识海。","weight":1},{"code":"mystic_risk_05","grade":"玄品","polarity":"risk","sequence":5,"title":"浑浊灵泉","story":"地下灵泉忽然变得浑浊，一股腥甜气味随之弥漫。","weight":1},{"code":"mystic_risk_06","grade":"玄品","polarity":"risk","sequence":6,"title":"阵中幻景","story":"你在阵法遗迹中踏错一步，四周景象瞬间发生变化。","weight":1},{"code":"mystic_risk_07","grade":"玄品","polarity":"risk","sequence":7,"title":"陌生同行","story":"一名陌生修士主动邀请你同行，但其言行中始终透着古怪。","weight":1},{"code":"mystic_risk_08","grade":"玄品","polarity":"risk","sequence":8,"title":"玉简呢喃","story":"你拾起一枚破碎玉简，其中却传出低沉而急促的呢喃。","weight":1},{"code":"mystic_risk_09","grade":"玄品","polarity":"risk","sequence":9,"title":"山谷灵溃","story":"山谷深处灵气骤然聚集，随后又以极快速度向外溃散。","weight":1},{"code":"mystic_risk_10","grade":"玄品","polarity":"risk","sequence":10,"title":"灰雾脚步","story":"一阵灰白雾气封住去路，雾中不时传来沉重脚步声。","weight":1},{"code":"earth_auspicious_01","grade":"地品","polarity":"auspicious","sequence":1,"title":"藤封石门","story":"你在荒山深处发现一座被藤蔓覆盖的石门，门上阵纹在你靠近时自行亮起。","weight":1},{"code":"earth_auspicious_02","grade":"地品","polarity":"auspicious","sequence":2,"title":"雷雨剑冢","story":"一座残破剑冢在雷雨后显露出来，断剑之间仍有剑意流转。","weight":1},{"code":"earth_auspicious_03","grade":"地品","polarity":"auspicious","sequence":3,"title":"古老丹炉","story":"你在地下洞窟中发现一尊尚未完全熄灭的古老丹炉。","weight":1},{"code":"earth_auspicious_04","grade":"地品","polarity":"auspicious","sequence":4,"title":"前辈玉符","story":"一名重伤前辈在临终前将一块传承玉符交到你手中。","weight":1},{"code":"earth_auspicious_05","grade":"地品","polarity":"auspicious","sequence":5,"title":"灵脉苏醒","story":"灵脉深处传来规律震动，仿佛有什么沉睡之物正在苏醒。","weight":1},{"code":"earth_auspicious_06","grade":"地品","polarity":"auspicious","sequence":6,"title":"阵隔山谷","story":"你进入一片被阵法隔绝的山谷，其中草木历经多年却仍保持旺盛生机。","weight":1},{"code":"earth_auspicious_07","grade":"地品","polarity":"auspicious","sequence":7,"title":"遗址石像","story":"宗门遗迹中的石像在你经过时缓缓睁开双眼。","weight":1},{"code":"earth_auspicious_08","grade":"地品","polarity":"auspicious","sequence":8,"title":"古井密室","story":"你在古井底部发现了一间保存完整的密室。","weight":1},{"code":"earth_auspicious_09","grade":"地品","polarity":"auspicious","sequence":9,"title":"残魂苏醒","story":"一道沉睡多年的残魂短暂苏醒，并主动与你交谈。","weight":1},{"code":"earth_auspicious_10","grade":"地品","polarity":"auspicious","sequence":10,"title":"符文巨碑","story":"你在悬崖之下发现一块刻满古老符文的巨大石碑。","weight":1},{"code":"earth_risk_01","grade":"地品","polarity":"risk","sequence":1,"title":"尸骨古剑","story":"一柄锈迹斑斑的古剑斜插在尸骨之间，你刚靠近，四周剑意便同时指向你。","weight":1},{"code":"earth_risk_02","grade":"地品","polarity":"risk","sequence":2,"title":"丹炉撞响","story":"地下丹炉突然自行燃起，炉中传来沉闷撞击声。","weight":1},{"code":"earth_risk_03","grade":"地品","polarity":"risk","sequence":3,"title":"洞府封裂","story":"你进入古修洞府后，发现其中封印早已出现裂痕。","weight":1},{"code":"earth_risk_04","grade":"地品","polarity":"risk","sequence":4,"title":"高阶妖兽","story":"一头高阶妖兽守在灵脉入口，气息已牢牢锁定你。","weight":1},{"code":"earth_risk_05","grade":"地品","polarity":"risk","sequence":5,"title":"玉符夺识","story":"传承玉符中残留的意志试图强行进入你的识海。","weight":1},{"code":"earth_risk_06","grade":"地品","polarity":"risk","sequence":6,"title":"杀阵复苏","story":"一座沉寂多年的杀阵因你的到来重新运转。","weight":1},{"code":"earth_risk_07","grade":"地品","polarity":"risk","sequence":7,"title":"尸骨朝外","story":"你在遗迹深处发现大量尸骨，而所有尸骨都保持着面朝出口的姿势。","weight":1},{"code":"earth_risk_08","grade":"地品","polarity":"risk","sequence":8,"title":"功法逆侵","story":"一股陌生力量沿着你运转的功法反向侵入经脉。","weight":1},{"code":"earth_risk_09","grade":"地品","polarity":"risk","sequence":9,"title":"灵脉暴动","story":"灵脉骤然暴动，整个洞窟开始剧烈坍塌。","weight":1},{"code":"earth_risk_10","grade":"地品","polarity":"risk","sequence":10,"title":"门后呼吸","story":"一道古老石门缓缓开启，门后却传来令人心悸的呼吸声。","weight":1},{"code":"heaven_auspicious_01","grade":"天品","polarity":"auspicious","sequence":1,"title":"星辰偏移","story":"夜空星辰忽然偏移，一道只有你能够看见的星光穿透云层，落入识海。","weight":1},{"code":"heaven_auspicious_02","grade":"天品","polarity":"auspicious","sequence":2,"title":"上古宗门","story":"一座只存在于古籍中的上古宗门遗址在你面前短暂显现。","weight":1},{"code":"heaven_auspicious_03","grade":"天品","polarity":"auspicious","sequence":3,"title":"灵气漩涡","story":"天地灵气汇聚成巨大漩涡，而漩涡中心恰好位于你的闭关之地。","weight":1},{"code":"heaven_auspicious_04","grade":"天品","polarity":"auspicious","sequence":4,"title":"大能残魂","story":"一位大能残魂从沉睡中苏醒，称你与其昔日故人有几分相似。","weight":1},{"code":"heaven_auspicious_05","grade":"天品","polarity":"auspicious","sequence":5,"title":"大道符文","story":"你在秘境核心发现一枚仍在跳动的大道符文。","weight":1},{"code":"heaven_auspicious_06","grade":"天品","polarity":"auspicious","sequence":6,"title":"雷中灵宝","story":"一株只在传说中出现的天材地宝于雷霆中缓缓成熟。","weight":1},{"code":"heaven_auspicious_07","grade":"天品","polarity":"auspicious","sequence":7,"title":"九天钟鸣","story":"九天之上传来悠远钟鸣，你体内灵力随之自行运转。","weight":1},{"code":"heaven_auspicious_08","grade":"天品","polarity":"auspicious","sequence":8,"title":"失落记忆","story":"一段被天地抹去的古老记忆突然在你识海中显现。","weight":1},{"code":"heaven_auspicious_09","grade":"天品","polarity":"auspicious","sequence":9,"title":"时间异域","story":"你进入一处时间流速异常的空间，外界一瞬，内部却似经历数日。","weight":1},{"code":"heaven_auspicious_10","grade":"天品","polarity":"auspicious","sequence":10,"title":"法宝残影","story":"一柄无主法宝残影横贯天穹，最终停留在你的神识之中。","weight":1},{"code":"heaven_risk_01","grade":"天品","polarity":"risk","sequence":1,"title":"虚空注视","story":"天地灵气骤然逆流，一道不属于此世的目光隔着虚空落在你身上。","weight":1},{"code":"heaven_risk_02","grade":"天品","polarity":"risk","sequence":2,"title":"群修逼近","story":"上古遗址开启的同时，数道强大气息从远方迅速逼近。","weight":1},{"code":"heaven_risk_03","grade":"天品","polarity":"risk","sequence":3,"title":"残魂夺舍","story":"大能残魂并未消散，而是试图借你的身躯重返世间。","weight":1},{"code":"heaven_risk_04","grade":"天品","polarity":"risk","sequence":4,"title":"符文入识","story":"一枚大道符文强行融入识海，引发剧烈冲突。","weight":1},{"code":"heaven_risk_05","grade":"天品","polarity":"risk","sequence":5,"title":"古兽苏醒","story":"天材地宝成熟之时，守护其多年的古兽也从沉睡中苏醒。","weight":1},{"code":"heaven_risk_06","grade":"天品","polarity":"risk","sequence":6,"title":"秘境崩溃","story":"秘境核心开始崩溃，而出口正在以肉眼可见的速度消失。","weight":1},{"code":"heaven_risk_07","grade":"天品","polarity":"risk","sequence":7,"title":"天雷锁气","story":"一道天雷毫无征兆地锁定了你的气机。","weight":1},{"code":"heaven_risk_08","grade":"天品","polarity":"risk","sequence":8,"title":"上古禁秘","story":"你窥见了一段不应被后世知晓的上古真相。","weight":1},{"code":"heaven_risk_09","grade":"天品","polarity":"risk","sequence":9,"title":"残宝认主","story":"一件残缺法宝主动认主，却同时带来难以承受的力量。","weight":1},{"code":"heaven_risk_10","grade":"天品","polarity":"risk","sequence":10,"title":"神魂剥离","story":"你踏入一片静止空间，发现自己的神魂正被缓慢剥离。","weight":1},{"code":"immortal_auspicious_01","grade":"仙品","polarity":"auspicious","sequence":1,"title":"识海仙宫","story":"你闭目修行时，识海中忽然浮现一座从未见过的仙宫。","weight":1},{"code":"immortal_auspicious_02","grade":"仙品","polarity":"auspicious","sequence":2,"title":"大道碎片","story":"一块大道碎片穿越虚空，停留在你的丹田上方。","weight":1},{"code":"immortal_auspicious_03","grade":"仙品","polarity":"auspicious","sequence":3,"title":"仙域梦门","story":"已经毁灭的古老仙域在梦境中向你短暂敞开门户。","weight":1},{"code":"immortal_auspicious_04","grade":"仙品","polarity":"auspicious","sequence":4,"title":"仙影回首","story":"一道仙人残影自岁月长河中回首，目光与你相接。","weight":1},{"code":"immortal_auspicious_05","grade":"仙品","polarity":"auspicious","sequence":5,"title":"法则显纹","story":"天地法则在你周围显化成肉眼可见的金色纹路。","weight":1},{"code":"immortal_auspicious_06","grade":"仙品","polarity":"auspicious","sequence":6,"title":"仙器共鸣","story":"一件失落仙器的残影跨越无数岁月，主动与你产生共鸣。","weight":1},{"code":"immortal_auspicious_07","grade":"仙品","polarity":"auspicious","sequence":7,"title":"前世残忆","story":"你在静坐中看见了自身前世修行的一段残缺记忆。","weight":1},{"code":"immortal_auspicious_08","grade":"仙品","polarity":"auspicious","sequence":8,"title":"云海仙门","story":"一座远古仙门遗址自云海之上浮现，仅存在片刻。","weight":1},{"code":"immortal_auspicious_09","grade":"仙品","polarity":"auspicious","sequence":9,"title":"仙光落身","story":"九天雷云忽然散去，一束纯净仙光落在你的身上。","weight":1},{"code":"immortal_auspicious_10","grade":"仙品","polarity":"auspicious","sequence":10,"title":"无边道海","story":"你的神魂进入一片无边道海，无数法则在其中生灭轮转。","weight":1},{"code":"immortal_risk_01","grade":"仙品","polarity":"risk","sequence":1,"title":"毁灭仙域","story":"天穹无声裂开，缝隙之后是一片已经毁灭的古老仙域。","weight":1},{"code":"immortal_risk_02","grade":"仙品","polarity":"risk","sequence":2,"title":"碎片失控","story":"大道碎片进入识海后突然失控，开始撕裂你的神魂。","weight":1},{"code":"immortal_risk_03","grade":"仙品","polarity":"risk","sequence":3,"title":"仙念杀意","story":"仙人残念误将你认作昔日仇敌，一缕杀意跨越岁月而来。","weight":1},{"code":"immortal_risk_04","grade":"仙品","polarity":"risk","sequence":4,"title":"仙器索灵","story":"一件残损仙器试图以你的灵力修复自身。","weight":1},{"code":"immortal_risk_05","grade":"仙品","polarity":"risk","sequence":5,"title":"法则反噬","story":"你窥见天地法则真容的瞬间，天道反噬随之降临。","weight":1},{"code":"immortal_risk_06","grade":"仙品","polarity":"risk","sequence":6,"title":"前世覆今","story":"前世记忆并未消散，而是试图覆盖你今生的意识。","weight":1},{"code":"immortal_risk_07","grade":"仙品","polarity":"risk","sequence":7,"title":"仙门坠落","story":"远古仙门遗址开始坠落，毁灭力量封锁了所有退路。","weight":1},{"code":"immortal_risk_08","grade":"仙品","polarity":"risk","sequence":8,"title":"仙血冲根","story":"一滴仙血融入体内，却与现有根基产生剧烈冲突。","weight":1},{"code":"immortal_risk_09","grade":"仙品","polarity":"risk","sequence":9,"title":"道海翻覆","story":"无边道海突然翻覆，亿万法则化作浪潮向你压来。","weight":1},{"code":"immortal_risk_10","grade":"仙品","polarity":"risk","sequence":10,"title":"仙人视野","story":"你获得了一瞬间的仙人视野，却同时看见了不可承受的真相。","weight":1},{"code":"exclusive_auspicious_01","grade":"专属","polarity":"auspicious","sequence":1,"title":"本命气机","story":"你运转周天时，本命气机忽然脱离原有轨迹，一篇陌生经文自行浮现在识海。","weight":1},{"code":"exclusive_auspicious_02","grade":"专属","polarity":"auspicious","sequence":2,"title":"命格共鸣","story":"命格深处传来一阵隐晦共鸣，一卷道法虚影自无尽虚空缓缓垂落。","weight":1},{"code":"exclusive_auspicious_03","grade":"专属","polarity":"auspicious","sequence":3,"title":"梦入道宫","story":"你在梦中踏入一座无名道宫，宫中只悬浮着五卷散发不同气息的经书。","weight":1},{"code":"exclusive_auspicious_04","grade":"专属","polarity":"auspicious","sequence":4,"title":"星列命象","story":"夜空星辰突然排列成命格之象，一道传承光辉随之降临。","weight":1},{"code":"exclusive_auspicious_05","grade":"专属","polarity":"auspicious","sequence":5,"title":"前世修忆","story":"一段不属于今生的修行记忆在识海深处逐渐苏醒。","weight":1},{"code":"exclusive_auspicious_06","grade":"专属","polarity":"auspicious","sequence":6,"title":"血魂同振","story":"你的血脉与神魂同时震动，仿佛有某种古老传承正在寻找归宿。","weight":1},{"code":"exclusive_auspicious_07","grade":"专属","polarity":"auspicious","sequence":7,"title":"无字天书","story":"一卷无字天书在灵台之中展开，五道不同道意依次显现。","weight":1},{"code":"exclusive_auspicious_08","grade":"专属","polarity":"auspicious","sequence":8,"title":"本命贯天","story":"本命气机贯通天地，一道专属于命格的功法气息正在靠近。","weight":1},{"code":"exclusive_auspicious_09","grade":"专属","polarity":"auspicious","sequence":9,"title":"闭关闻道","story":"你闭关时忽闻大道之音，字字皆似从命格最深处传来。","weight":1},{"code":"exclusive_auspicious_10","grade":"专属","polarity":"auspicious","sequence":10,"title":"五法同现","story":"天道垂下一缕特殊机缘，五道功法虚影同时出现在你的识海。","weight":1},{"code":"exclusive_risk_01","grade":"专属","polarity":"risk","sequence":1,"title":"天机逆转","story":"专属天机即将落下时突然逆转，一道紊乱道音冲入识海。","weight":1},{"code":"exclusive_risk_02","grade":"专属","polarity":"risk","sequence":2,"title":"五法撕裂","story":"五道功法虚影刚刚显现，便同时被一股未知力量撕裂。","weight":1},{"code":"exclusive_risk_03","grade":"专属","polarity":"risk","sequence":3,"title":"乱力锁命","story":"你的本命气机试图接引传承，却反被虚空中的混乱力量锁定。","weight":1},{"code":"exclusive_risk_04","grade":"专属","polarity":"risk","sequence":4,"title":"道法崩解","story":"一卷专属道法已靠近识海，却在最后一刻发生剧烈崩解。","weight":1},{"code":"exclusive_risk_05","grade":"专属","polarity":"risk","sequence":5,"title":"命格失衡","story":"命格与天地短暂共鸣后突然失衡，周身灵力随之逆转。","weight":1},{"code":"exclusive_risk_06","grade":"专属","polarity":"risk","sequence":6,"title":"天书乱文","story":"无字天书刚刚展开，其中经文便化作大量混乱符号。","weight":1},{"code":"exclusive_risk_07","grade":"专属","polarity":"risk","sequence":7,"title":"古意介入","story":"天道垂下专属机缘时，另一股古老意志强行介入其中。","weight":1},{"code":"exclusive_risk_08","grade":"专属","polarity":"risk","sequence":8,"title":"五法冲识","story":"五道功法气息在识海中彼此冲突，引发剧烈神魂震荡。","weight":1},{"code":"exclusive_risk_09","grade":"专属","polarity":"risk","sequence":9,"title":"乱流击法","story":"一道本应属于你的传承被虚空乱流击中，残余力量反向涌入经脉。","weight":1},{"code":"exclusive_risk_10","grade":"专属","polarity":"risk","sequence":10,"title":"道音尖啸","story":"命格深处传来的大道之音突然变得尖锐，仿佛有无数声音同时在神魂中回响。","weight":1}]'::jsonb)
  as x(code text,grade text,polarity text,sequence integer,title text,story text,weight numeric)
on conflict(code) do update set grade=excluded.grade,polarity=excluded.polarity,sequence=excluded.sequence,title=excluded.title,story=excluded.story,weight=excluded.weight,is_active=true,updated_at=now();

insert into public.opportunity_v4_result_pool(code,grade,polarity,sequence,title,narrative,effect_spec,weight)
select x.code,x.grade,x.polarity,x.sequence,x.title,x.narrative,x.effect_spec,x.weight
from jsonb_to_recordset('[{"code":"yellow_auspicious_result_01","grade":"黄品","polarity":"auspicious","sequence":1,"title":"微有所得","narrative":"你从细微灵机中获得了一点感悟，原本滞涩的修行稍有进展。","effect_spec":{"cultivation_gain_pct":0.004},"weight":1},{"code":"yellow_auspicious_result_02","grade":"黄品","polarity":"auspicious","sequence":2,"title":"吐纳顺畅","narrative":"你顺势调整吐纳节奏，周身灵气运转得更加顺畅。","effect_spec":{"cultivation_gain_pct":0.006},"weight":1},{"code":"yellow_auspicious_result_03","grade":"黄品","polarity":"auspicious","sequence":3,"title":"一瞬明悟","narrative":"一瞬间的明悟在心中绽开，让你省去了数日苦修。","effect_spec":{"cultivation_gain_pct":0.008},"weight":1},{"code":"yellow_auspicious_result_04","grade":"黄品","polarity":"auspicious","sequence":4,"title":"灵材换石","narrative":"你在附近找到一些尚有价值的灵材，将其换成了灵石。","effect_spec":{"spirit_gain_mult":1.0},"weight":1},{"code":"yellow_auspicious_result_05","grade":"黄品","polarity":"auspicious","sequence":5,"title":"资源感悟","narrative":"你不仅得到少量资源，也从此次经历中有所领悟。","effect_spec":{"cultivation_gain_pct":0.003,"spirit_gain_mult":0.7},"weight":1},{"code":"yellow_auspicious_result_06","grade":"黄品","polarity":"auspicious","sequence":6,"title":"清灵绕脉","narrative":"清灵之气萦绕经脉，接下来一段时间内修炼更加轻松。","effect_spec":{"speed_bonus":0.05,"duration_minutes":15},"weight":1},{"code":"yellow_auspicious_result_07","grade":"黄品","polarity":"auspicious","sequence":7,"title":"心神澄明","narrative":"你心神澄明，短时间内对灵气的感应明显增强。","effect_spec":{"speed_bonus":0.08,"duration_minutes":15},"weight":1},{"code":"yellow_auspicious_result_08","grade":"黄品","polarity":"auspicious","sequence":8,"title":"印证功法","narrative":"此番经历印证了当前功法中的一处细节。","effect_spec":{"cultivation_gain_pct":0.0035,"speed_bonus":0.03,"duration_minutes":15},"weight":1},{"code":"yellow_auspicious_result_09","grade":"黄品","polarity":"auspicious","sequence":9,"title":"根基略固","narrative":"你将所得感悟融入修行，根基略有稳固。","effect_spec":{"cultivation_gain_pct":0.005,"spirit_gain_mult":0.3},"weight":1},{"code":"yellow_auspicious_result_10","grade":"黄品","polarity":"auspicious","sequence":10,"title":"小机缘圆满","narrative":"一缕微弱机缘被你完整把握，短期收益颇为圆满。","effect_spec":{"cultivation_gain_pct":0.0045,"speed_bonus":0.05,"duration_minutes":15},"weight":1},{"code":"yellow_risk_result_01","grade":"黄品","polarity":"risk","sequence":1,"title":"灵气散失","narrative":"你虽及时脱身，仍因灵气紊乱损失了少量修为。","effect_spec":{"cultivation_loss_current_pct":0.01,"cultivation_loss_stage_cap_pct":0.0015},"weight":1},{"code":"yellow_risk_result_02","grade":"黄品","polarity":"risk","sequence":2,"title":"异力冲脉","narrative":"一股异力冲击经脉，使你刚刚积累的修为有所散失。","effect_spec":{"cultivation_loss_current_pct":0.02,"cultivation_loss_stage_cap_pct":0.003},"weight":1},{"code":"yellow_risk_result_03","grade":"黄品","polarity":"risk","sequence":3,"title":"破局耗石","narrative":"你为摆脱麻烦耗费了一些灵石。","effect_spec":{"spirit_loss_balance_pct":0.005,"spirit_loss_base_mult":1.0},"weight":1},{"code":"yellow_risk_result_04","grade":"黄品","polarity":"risk","sequence":4,"title":"遗落资源","narrative":"你匆忙离开险地，遗落了一部分随身资源。","effect_spec":{"spirit_loss_balance_pct":0.01,"spirit_loss_base_mult":1.5},"weight":1},{"code":"yellow_risk_result_05","grade":"黄品","polarity":"risk","sequence":5,"title":"阴气滞脉","narrative":"残留阴气影响了灵力运转。","effect_spec":{"speed_bonus":-0.05,"duration_minutes":15},"weight":1},{"code":"yellow_risk_result_06","grade":"黄品","polarity":"risk","sequence":6,"title":"经脉滞涩","narrative":"经脉出现轻微滞涩，需要一段时间自行恢复。","effect_spec":{"speed_bonus":-0.08,"duration_minutes":30},"weight":1},{"code":"yellow_risk_result_07","grade":"黄品","polarity":"risk","sequence":7,"title":"强行抵御","narrative":"你强行抵御异力，虽然成功脱身，却消耗了不少精力。","effect_spec":{"cultivation_loss_current_pct":0.01,"cultivation_loss_stage_cap_pct":0.0015,"speed_bonus":-0.03,"duration_minutes":15},"weight":1},{"code":"yellow_risk_result_08","grade":"黄品","polarity":"risk","sequence":8,"title":"护阵脱险","narrative":"你以灵石布下简易护阵，才避开进一步危险。","effect_spec":{"spirit_loss_balance_pct":0.005,"spirit_loss_base_mult":1.0,"speed_bonus":-0.03,"duration_minutes":15},"weight":1},{"code":"yellow_risk_result_09","grade":"黄品","polarity":"risk","sequence":9,"title":"险中窥机","narrative":"你在危险中也窥见了一丝灵机，只是代价并不算小。","effect_spec":{"cultivation_gain_pct":0.002,"speed_bonus":-0.05,"duration_minutes":15},"weight":1},{"code":"yellow_risk_result_10","grade":"黄品","polarity":"risk","sequence":10,"title":"受创带回","narrative":"你虽受到轻微波及，却从现场带走了一些残留资源。","effect_spec":{"cultivation_loss_current_pct":0.01,"cultivation_loss_stage_cap_pct":0.0015,"spirit_gain_mult":0.5},"weight":1},{"code":"mystic_auspicious_result_01","grade":"玄品","polarity":"auspicious","sequence":1,"title":"残意入心","narrative":"你参透了一部分残留道意，修为明显精进。","effect_spec":{"cultivation_gain_pct":0.008},"weight":1},{"code":"mystic_auspicious_result_02","grade":"玄品","polarity":"auspicious","sequence":2,"title":"补足缺漏","narrative":"前人遗留的感悟补足了你修行中的一处缺漏。","effect_spec":{"cultivation_gain_pct":0.011},"weight":1},{"code":"mystic_auspicious_result_03","grade":"玄品","polarity":"auspicious","sequence":3,"title":"深层悟道","narrative":"你借此机会完成了一次难得的深层悟道。","effect_spec":{"cultivation_gain_pct":0.015},"weight":1},{"code":"mystic_auspicious_result_04","grade":"玄品","polarity":"auspicious","sequence":4,"title":"遗迹资源","narrative":"你从遗迹中带出一批尚有价值的修炼资源。","effect_spec":{"spirit_gain_mult":2.5},"weight":1},{"code":"mystic_auspicious_result_05","grade":"玄品","polarity":"auspicious","sequence":5,"title":"不虚此行","narrative":"你同时收获资源与感悟，此行可谓不虚。","effect_spec":{"cultivation_gain_pct":0.007,"spirit_gain_mult":1.5},"weight":1},{"code":"mystic_auspicious_result_06","grade":"玄品","polarity":"auspicious","sequence":6,"title":"灵泉洗脉","narrative":"灵泉之气洗涤经脉，使修行效率短期提高。","effect_spec":{"speed_bonus":0.08,"duration_minutes":30},"weight":1},{"code":"mystic_auspicious_result_07","grade":"玄品","polarity":"auspicious","sequence":7,"title":"灵气敏锐","narrative":"你对周围灵气的掌控变得更加敏锐。","effect_spec":{"speed_bonus":0.12,"duration_minutes":30},"weight":1},{"code":"mystic_auspicious_result_08","grade":"玄品","polarity":"auspicious","sequence":8,"title":"道意共鸣","narrative":"残留道意与你当前功法产生共鸣。","effect_spec":{"cultivation_gain_pct":0.007,"speed_bonus":0.05,"duration_minutes":30},"weight":1},{"code":"mystic_auspicious_result_09","grade":"玄品","polarity":"auspicious","sequence":9,"title":"稳妥行功","narrative":"你从古修札记中寻得一条更稳妥的行功路线。","effect_spec":{"cultivation_gain_pct":0.009,"spirit_gain_mult":0.8},"weight":1},{"code":"mystic_auspicious_result_10","grade":"玄品","polarity":"auspicious","sequence":10,"title":"多项收获","narrative":"此番机缘令你的修为与资源均有所增长。","effect_spec":{"cultivation_gain_pct":0.006,"spirit_gain_mult":1.2,"speed_bonus":0.05,"duration_minutes":30},"weight":1},{"code":"mystic_risk_result_01","grade":"玄品","polarity":"risk","sequence":1,"title":"灵气冲丹","narrative":"混乱灵气冲击丹田，使部分修为暂时散失。","effect_spec":{"cultivation_loss_current_pct":0.03,"cultivation_loss_stage_cap_pct":0.004},"weight":1},{"code":"mystic_risk_result_02","grade":"玄品","polarity":"risk","sequence":2,"title":"神念反噬","narrative":"你遭到残留神念反噬，根基受到轻微震荡。","effect_spec":{"cultivation_loss_current_pct":0.05,"cultivation_loss_stage_cap_pct":0.008},"weight":1},{"code":"mystic_risk_result_03","grade":"玄品","polarity":"risk","sequence":3,"title":"破阵耗石","narrative":"你为破除困局消耗了不少灵石。","effect_spec":{"spirit_loss_balance_pct":0.01,"spirit_loss_base_mult":2.5},"weight":1},{"code":"mystic_risk_result_04","grade":"玄品","polarity":"risk","sequence":4,"title":"资源损毁","narrative":"你虽成功离开，却损毁了一批随身资源。","effect_spec":{"spirit_loss_balance_pct":0.02,"spirit_loss_base_mult":4.0},"weight":1},{"code":"mystic_risk_result_05","grade":"玄品","polarity":"risk","sequence":5,"title":"阴煞残留","narrative":"阴煞之气残留体内，灵力运转受到影响。","effect_spec":{"speed_bonus":-0.08,"duration_minutes":30},"weight":1},{"code":"mystic_risk_result_06","grade":"玄品","polarity":"risk","sequence":6,"title":"阵冲经脉","narrative":"经脉受到阵法冲击，需要较长时间调息。","effect_spec":{"speed_bonus":-0.12,"duration_minutes":60},"weight":1},{"code":"mystic_risk_result_07","grade":"玄品","polarity":"risk","sequence":7,"title":"冲破幻境","narrative":"你强行冲破幻境，神识与经脉同时受到损耗。","effect_spec":{"cultivation_loss_current_pct":0.03,"cultivation_loss_stage_cap_pct":0.004,"speed_bonus":-0.05,"duration_minutes":30},"weight":1},{"code":"mystic_risk_result_08","grade":"玄品","polarity":"risk","sequence":8,"title":"稳阵脱困","narrative":"你用灵石强行稳定阵法，才没有陷入更深处。","effect_spec":{"spirit_loss_balance_pct":0.01,"spirit_loss_base_mult":2.5,"speed_bonus":-0.05,"duration_minutes":30},"weight":1},{"code":"mystic_risk_result_09","grade":"玄品","polarity":"risk","sequence":9,"title":"反噬截意","narrative":"你在反噬中截取了一丝残留道意。","effect_spec":{"cultivation_gain_pct":0.004,"speed_bonus":-0.1,"duration_minutes":30},"weight":1},{"code":"mystic_risk_result_10","grade":"玄品","polarity":"risk","sequence":10,"title":"失财得悟","narrative":"你虽然失去部分资源，却从险地带回了有用之物。","effect_spec":{"spirit_loss_balance_pct":0.01,"spirit_loss_base_mult":2.0,"cultivation_gain_pct":0.004},"weight":1},{"code":"earth_auspicious_result_01","grade":"地品","polarity":"auspicious","sequence":1,"title":"古修道意","narrative":"你参悟古修遗留的道意，修为获得显著增长。","effect_spec":{"cultivation_gain_pct":0.015},"weight":1},{"code":"earth_auspicious_result_02","grade":"地品","polarity":"auspicious","sequence":2,"title":"传承关键","narrative":"传承中的关键感悟令你对当前境界理解更深。","effect_spec":{"cultivation_gain_pct":0.022},"weight":1},{"code":"earth_auspicious_result_03","grade":"地品","polarity":"auspicious","sequence":3,"title":"难得顿悟","narrative":"你完成了一次难得的深层悟道，省去大量苦修。","effect_spec":{"cultivation_gain_pct":0.03},"weight":1},{"code":"earth_auspicious_result_04","grade":"地品","polarity":"auspicious","sequence":4,"title":"古修宝藏","narrative":"你从古修遗迹中带回大量可用资源。","effect_spec":{"spirit_gain_mult":6.0},"weight":1},{"code":"earth_auspicious_result_05","grade":"地品","polarity":"auspicious","sequence":5,"title":"传承资源","narrative":"你同时得到传承感悟与珍贵修炼资源。","effect_spec":{"cultivation_gain_pct":0.013,"spirit_gain_mult":4.0},"weight":1},{"code":"earth_auspicious_result_06","grade":"地品","polarity":"auspicious","sequence":6,"title":"灵脉洗身","narrative":"灵脉之力洗涤全身，使修炼速度明显提高。","effect_spec":{"speed_bonus":0.12,"duration_minutes":60},"weight":1},{"code":"earth_auspicious_result_07","grade":"地品","polarity":"auspicious","sequence":7,"title":"深层共鸣","narrative":"古修传承与你当前修行产生深层共鸣。","effect_spec":{"speed_bonus":0.18,"duration_minutes":60},"weight":1},{"code":"earth_auspicious_result_08","grade":"地品","polarity":"auspicious","sequence":8,"title":"融入体系","narrative":"你将遗迹中的道意融入自身修炼体系。","effect_spec":{"cultivation_gain_pct":0.012,"speed_bonus":0.1,"duration_minutes":60},"weight":1},{"code":"earth_auspicious_result_09","grade":"地品","polarity":"auspicious","sequence":9,"title":"炼化药力","narrative":"丹炉残留药力被你成功炼化。","effect_spec":{"cultivation_gain_pct":0.015,"spirit_gain_mult":2.0},"weight":1},{"code":"earth_auspicious_result_10","grade":"地品","polarity":"auspicious","sequence":10,"title":"三益并得","narrative":"此次机缘令你在修为、资源与效率上同时受益。","effect_spec":{"cultivation_gain_pct":0.01,"spirit_gain_mult":3.0,"speed_bonus":0.08,"duration_minutes":60},"weight":1},{"code":"earth_risk_result_01","grade":"地品","polarity":"risk","sequence":1,"title":"杀阵贯脉","narrative":"杀阵余威贯穿经脉，部分修为因此散失。","effect_spec":{"cultivation_loss_current_pct":0.06,"cultivation_loss_stage_cap_pct":0.008},"weight":1},{"code":"earth_risk_result_02","grade":"地品","polarity":"risk","sequence":2,"title":"古意冲识","narrative":"古老意志冲击识海，使你的境界进度受到明显影响。","effect_spec":{"cultivation_loss_current_pct":0.1,"cultivation_loss_stage_cap_pct":0.015},"weight":1},{"code":"earth_risk_result_03","grade":"地品","polarity":"risk","sequence":3,"title":"镇灵耗石","narrative":"你为镇压失控灵气消耗了大量灵石。","effect_spec":{"spirit_loss_balance_pct":0.02,"spirit_loss_base_mult":6.0},"weight":1},{"code":"earth_risk_result_04","grade":"地品","polarity":"risk","sequence":4,"title":"洞塌毁资","narrative":"洞府坍塌使你损毁了不少随身资源。","effect_spec":{"spirit_loss_balance_pct":0.03,"spirit_loss_base_mult":10.0},"weight":1},{"code":"earth_risk_result_05","grade":"地品","polarity":"risk","sequence":5,"title":"剑意压制","narrative":"剑意残留体内，灵力运转持续受到压制。","effect_spec":{"speed_bonus":-0.12,"duration_minutes":60},"weight":1},{"code":"earth_risk_result_06","grade":"地品","polarity":"risk","sequence":6,"title":"神识受创","narrative":"神识与经脉均受到冲击，需要较长时间恢复。","effect_spec":{"speed_bonus":-0.18,"duration_minutes":120},"weight":1},{"code":"earth_risk_result_07","grade":"地品","polarity":"risk","sequence":7,"title":"夺传反噬","narrative":"你强行夺取传承，虽然成功，却承受了严重反噬。","effect_spec":{"cultivation_loss_current_pct":0.06,"cultivation_loss_stage_cap_pct":0.008,"speed_bonus":-0.1,"duration_minutes":60},"weight":1},{"code":"earth_risk_result_08","grade":"地品","polarity":"risk","sequence":8,"title":"稳脉脱险","narrative":"你用大量灵石稳定灵脉，才避免了更大的灾祸。","effect_spec":{"spirit_loss_balance_pct":0.02,"spirit_loss_base_mult":6.0,"speed_bonus":-0.08,"duration_minutes":60},"weight":1},{"code":"earth_risk_result_09","grade":"地品","polarity":"risk","sequence":9,"title":"失控截悟","narrative":"你从失控传承中强行截取了一部分感悟。","effect_spec":{"cultivation_gain_pct":0.008,"speed_bonus":-0.15,"duration_minutes":60},"weight":1},{"code":"earth_risk_result_10","grade":"地品","polarity":"risk","sequence":10,"title":"受创携宝","narrative":"你虽在险境中受创，却带回了一部分遗迹资源。","effect_spec":{"cultivation_loss_current_pct":0.05,"cultivation_loss_stage_cap_pct":0.007,"spirit_gain_mult":3.0},"weight":1},{"code":"heaven_auspicious_result_01","grade":"天品","polarity":"auspicious","sequence":1,"title":"星辰入识","narrative":"星辰道意融入识海，使你的修为大幅增长。","effect_spec":{"cultivation_gain_pct":0.03},"weight":1},{"code":"heaven_auspicious_result_02","grade":"天品","polarity":"auspicious","sequence":2,"title":"大能补道","narrative":"大能残留感悟补全了你对当前境界的理解。","effect_spec":{"cultivation_gain_pct":0.045},"weight":1},{"code":"heaven_auspicious_result_03","grade":"天品","polarity":"auspicious","sequence":3,"title":"天地顿悟","narrative":"你把握住了一次真正的天地顿悟。","effect_spec":{"cultivation_gain_pct":0.06},"weight":1},{"code":"heaven_auspicious_result_04","grade":"天品","polarity":"auspicious","sequence":4,"title":"上古珍藏","narrative":"你从上古遗址中得到了一批极为珍贵的资源。","effect_spec":{"spirit_gain_mult":15.0},"weight":1},{"code":"heaven_auspicious_result_05","grade":"天品","polarity":"auspicious","sequence":5,"title":"天地馈赠","narrative":"天地馈赠同时化作修为与资源归入你手中。","effect_spec":{"cultivation_gain_pct":0.025,"spirit_gain_mult":10.0},"weight":1},{"code":"heaven_auspicious_result_06","grade":"天品","polarity":"auspicious","sequence":6,"title":"大道环身","narrative":"大道灵机持续环绕周身，修炼速度大幅提升。","effect_spec":{"speed_bonus":0.18,"duration_minutes":120},"weight":1},{"code":"heaven_auspicious_result_07","grade":"天品","polarity":"auspicious","sequence":7,"title":"天地共鸣","narrative":"你与天地灵气产生罕见共鸣。","effect_spec":{"speed_bonus":0.25,"duration_minutes":120},"weight":1},{"code":"heaven_auspicious_result_08","grade":"天品","polarity":"auspicious","sequence":8,"title":"吸收真意","narrative":"上古传承中的部分真意被你成功吸收。","effect_spec":{"cultivation_gain_pct":0.025,"speed_bonus":0.15,"duration_minutes":120},"weight":1},{"code":"heaven_auspicious_result_09","grade":"天品","polarity":"auspicious","sequence":9,"title":"时间馈赠","narrative":"时间异常为你带来了远超寻常闭关的收获。","effect_spec":{"cultivation_gain_pct":0.035,"spirit_gain_mult":5.0},"weight":1},{"code":"heaven_auspicious_result_10","grade":"天品","polarity":"auspicious","sequence":10,"title":"天机全益","narrative":"此次天品机缘从多个方面推动了你的修行。","effect_spec":{"cultivation_gain_pct":0.02,"spirit_gain_mult":8.0,"speed_bonus":0.12,"duration_minutes":120},"weight":1},{"code":"heaven_risk_result_01","grade":"天品","polarity":"risk","sequence":1,"title":"天威撼基","narrative":"天道威压冲击根基，使大量修为暂时散失。","effect_spec":{"cultivation_loss_current_pct":0.1,"cultivation_loss_stage_cap_pct":0.018},"weight":1},{"code":"heaven_risk_result_02","grade":"天品","polarity":"risk","sequence":2,"title":"神魂冲突","narrative":"上古意志与神魂激烈冲突，境界进度受到重创。","effect_spec":{"cultivation_loss_current_pct":0.18,"cultivation_loss_stage_cap_pct":0.03},"weight":1},{"code":"heaven_risk_result_03","grade":"天品","polarity":"risk","sequence":3,"title":"御雷耗石","narrative":"你为抵御天雷耗费了极为庞大的灵石资源。","effect_spec":{"spirit_loss_balance_pct":0.03,"spirit_loss_base_mult":15.0},"weight":1},{"code":"heaven_risk_result_04","grade":"天品","polarity":"risk","sequence":4,"title":"秘境毁资","narrative":"秘境崩塌摧毁了你携带的大量资源。","effect_spec":{"spirit_loss_balance_pct":0.05,"spirit_loss_base_mult":25.0},"weight":1},{"code":"heaven_risk_result_05","grade":"天品","polarity":"risk","sequence":5,"title":"天威压修","narrative":"天道威压持续笼罩，使修行效率明显下降。","effect_spec":{"speed_bonus":-0.18,"duration_minutes":120},"weight":1},{"code":"heaven_risk_result_06","grade":"天品","polarity":"risk","sequence":6,"title":"神魂静养","narrative":"神魂受损，需要长时间静养。","effect_spec":{"speed_bonus":-0.25,"duration_minutes":240},"weight":1},{"code":"heaven_risk_result_07","grade":"天品","polarity":"risk","sequence":7,"title":"承符重创","narrative":"你强行承受大道符文，虽然没有失败，却付出沉重代价。","effect_spec":{"cultivation_loss_current_pct":0.1,"cultivation_loss_stage_cap_pct":0.018,"speed_bonus":-0.15,"duration_minutes":120},"weight":1},{"code":"heaven_risk_result_08","grade":"天品","polarity":"risk","sequence":8,"title":"燃石脱境","narrative":"你燃烧大量灵石才从崩溃秘境中脱身。","effect_spec":{"spirit_loss_balance_pct":0.03,"spirit_loss_base_mult":15.0,"speed_bonus":-0.12,"duration_minutes":120},"weight":1},{"code":"heaven_risk_result_09","grade":"天品","polarity":"risk","sequence":9,"title":"反噬截道","narrative":"你从天道反噬中截取了一缕珍贵道意。","effect_spec":{"cultivation_gain_pct":0.018,"speed_bonus":-0.22,"duration_minutes":120},"weight":1},{"code":"heaven_risk_result_10","grade":"天品","polarity":"risk","sequence":10,"title":"负伤携遗","narrative":"你虽然被上古力量所伤，却带回了部分珍贵遗物。","effect_spec":{"cultivation_loss_current_pct":0.08,"cultivation_loss_stage_cap_pct":0.015,"spirit_gain_mult":8.0},"weight":1},{"code":"immortal_auspicious_result_01","grade":"仙品","polarity":"auspicious","sequence":1,"title":"仙意入基","narrative":"一缕仙道真意融入根基，使修为产生巨大增长。","effect_spec":{"cultivation_gain_pct":0.06},"weight":1},{"code":"immortal_auspicious_result_02","grade":"仙品","polarity":"auspicious","sequence":2,"title":"碎片悟道","narrative":"你从大道碎片中参悟到远超当前境界的奥妙。","effect_spec":{"cultivation_gain_pct":0.09},"weight":1},{"code":"immortal_auspicious_result_03","grade":"仙品","polarity":"auspicious","sequence":3,"title":"仙影演法","narrative":"仙人残影为你演化大道，带来一次罕见蜕变。","effect_spec":{"cultivation_gain_pct":0.12},"weight":1},{"code":"immortal_auspicious_result_04","grade":"仙品","polarity":"auspicious","sequence":4,"title":"仙域珍资","narrative":"你从仙域残片中取得了数量惊人的珍贵资源。","effect_spec":{"spirit_gain_mult":35.0},"weight":1},{"code":"immortal_auspicious_result_05","grade":"仙品","polarity":"auspicious","sequence":5,"title":"大道双馈","narrative":"大道馈赠同时化为修为与庞大资源。","effect_spec":{"cultivation_gain_pct":0.05,"spirit_gain_mult":25.0},"weight":1},{"code":"immortal_auspicious_result_06","grade":"仙品","polarity":"auspicious","sequence":6,"title":"仙光洗脉","narrative":"仙光持续洗涤经脉，使修行速度产生质的提升。","effect_spec":{"speed_bonus":0.25,"duration_minutes":240},"weight":1},{"code":"immortal_auspicious_result_07","grade":"仙品","polarity":"auspicious","sequence":7,"title":"法则共鸣","narrative":"你与部分天地法则产生短暂共鸣。","effect_spec":{"speed_bonus":0.4,"duration_minutes":240},"weight":1},{"code":"immortal_auspicious_result_08","grade":"仙品","polarity":"auspicious","sequence":8,"title":"仙意改法","narrative":"仙道真意暂时改变了你运转功法的方式。","effect_spec":{"cultivation_gain_pct":0.05,"speed_bonus":0.2,"duration_minutes":240},"weight":1},{"code":"immortal_auspicious_result_09","grade":"仙品","polarity":"auspicious","sequence":9,"title":"道海长修","narrative":"你在道海中完成了一次远超寻常的修行。","effect_spec":{"cultivation_gain_pct":0.07,"spirit_gain_mult":15.0},"weight":1},{"code":"immortal_auspicious_result_10","grade":"仙品","polarity":"auspicious","sequence":10,"title":"仙缘全益","narrative":"此次仙品机缘令你的修为、资源与效率同时跃升。","effect_spec":{"cultivation_gain_pct":0.04,"spirit_gain_mult":20.0,"speed_bonus":0.18,"duration_minutes":240},"weight":1},{"code":"immortal_risk_result_01","grade":"仙品","polarity":"risk","sequence":1,"title":"仙威撼基","narrative":"仙道威压撼动根基，使大量修为散失。","effect_spec":{"cultivation_loss_current_pct":0.18,"cultivation_loss_stage_cap_pct":0.03},"weight":1},{"code":"immortal_risk_result_02","grade":"仙品","polarity":"risk","sequence":2,"title":"大道重创","narrative":"大道反噬重创神魂，当前境界进度遭受严重影响。","effect_spec":{"cultivation_loss_current_pct":0.3,"cultivation_loss_stage_cap_pct":0.05},"weight":1},{"code":"immortal_risk_result_03","grade":"仙品","polarity":"risk","sequence":3,"title":"御器燃石","narrative":"你燃烧庞大灵石才勉强抵御仙器侵蚀。","effect_spec":{"spirit_loss_balance_pct":0.05,"spirit_loss_base_mult":35.0},"weight":1},{"code":"immortal_risk_result_04","grade":"仙品","polarity":"risk","sequence":4,"title":"仙域毁资","narrative":"仙域毁灭余波摧毁了大量修炼资源。","effect_spec":{"spirit_loss_balance_pct":0.08,"spirit_loss_base_mult":60.0},"weight":1},{"code":"immortal_risk_result_05","grade":"仙品","polarity":"risk","sequence":5,"title":"仙力滞脉","narrative":"仙道残力滞留经脉，使修行效率严重下降。","effect_spec":{"speed_bonus":-0.25,"duration_minutes":240},"weight":1},{"code":"immortal_risk_result_06","grade":"仙品","polarity":"risk","sequence":6,"title":"道冲神魂","narrative":"神魂与大道发生冲突，需要长时间恢复。","effect_spec":{"speed_bonus":-0.4,"duration_minutes":480},"weight":1},{"code":"immortal_risk_result_07","grade":"仙品","polarity":"risk","sequence":7,"title":"保我重损","narrative":"你强行保住自我意识，却付出了沉重的修为代价。","effect_spec":{"cultivation_loss_current_pct":0.18,"cultivation_loss_stage_cap_pct":0.03,"speed_bonus":-0.2,"duration_minutes":240},"weight":1},{"code":"immortal_risk_result_08","grade":"仙品","polarity":"risk","sequence":8,"title":"封印碎片","narrative":"你燃烧大量灵石才将失控大道碎片封印。","effect_spec":{"spirit_loss_balance_pct":0.05,"spirit_loss_base_mult":35.0,"speed_bonus":-0.18,"duration_minutes":240},"weight":1},{"code":"immortal_risk_result_09","grade":"仙品","polarity":"risk","sequence":9,"title":"毁灭悟仙","narrative":"你从毁灭余波中截取了一丝真正的仙道感悟。","effect_spec":{"cultivation_gain_pct":0.03,"speed_bonus":-0.35,"duration_minutes":240},"weight":1},{"code":"immortal_risk_result_10","grade":"仙品","polarity":"risk","sequence":10,"title":"反噬携珍","narrative":"你虽然遭到仙道反噬，却从残破仙域带回珍贵资源。","effect_spec":{"cultivation_loss_current_pct":0.15,"cultivation_loss_stage_cap_pct":0.025,"spirit_gain_mult":20.0},"weight":1},{"code":"exclusive_auspicious_result_01","grade":"专属","polarity":"auspicious","sequence":1,"title":"本命契合一","narrative":"五道功法虚影依次消散，唯有与你命格完全契合的那一卷留在识海。","effect_spec":{"exclusive_outcome":"success"},"weight":1},{"code":"exclusive_auspicious_result_02","grade":"专属","polarity":"auspicious","sequence":2,"title":"本命契合二","narrative":"天命牵引之下，与你命格契合的功法穿越虚空而来。","effect_spec":{"exclusive_outcome":"success"},"weight":1},{"code":"exclusive_auspicious_result_03","grade":"专属","polarity":"auspicious","sequence":3,"title":"本命契合三","narrative":"那卷道法与你的本命气机完全共鸣，最终选择认你为主。","effect_spec":{"exclusive_outcome":"success"},"weight":1},{"code":"exclusive_auspicious_result_04","grade":"专属","polarity":"auspicious","sequence":4,"title":"本命契合四","narrative":"无数经文融入识海，你终于看清了这门功法的真正名称。","effect_spec":{"exclusive_outcome":"success"},"weight":1},{"code":"exclusive_auspicious_result_05","grade":"专属","polarity":"auspicious","sequence":5,"title":"本命契合五","narrative":"你与功法之间的因果彻底闭合，专属传承正式归位。","effect_spec":{"exclusive_outcome":"success"},"weight":1},{"code":"exclusive_auspicious_result_06","grade":"专属","polarity":"auspicious","sequence":6,"title":"异命收回一","narrative":"一卷强大道法已经显化，却与你的本命气机始终无法相融。","effect_spec":{"exclusive_outcome":"mismatch"},"weight":1},{"code":"exclusive_auspicious_result_07","grade":"专属","polarity":"auspicious","sequence":7,"title":"异命收回二","narrative":"功法虽已降临，却因命格不合而逐渐崩散。","effect_spec":{"exclusive_outcome":"mismatch"},"weight":1},{"code":"exclusive_auspicious_result_08","grade":"专属","polarity":"auspicious","sequence":8,"title":"异命收回三","narrative":"道法虚影在识海中停留片刻，最终被天道重新带走。","effect_spec":{"exclusive_outcome":"mismatch"},"weight":1},{"code":"exclusive_auspicious_result_09","grade":"专属","polarity":"auspicious","sequence":9,"title":"异命收回四","narrative":"你尝试与其共鸣，却始终无法跨越命格之间的隔阂。","effect_spec":{"exclusive_outcome":"mismatch"},"weight":1},{"code":"exclusive_auspicious_result_10","grade":"专属","polarity":"auspicious","sequence":10,"title":"异命收回五","narrative":"一道天道印记落下，将不属于你的传承封回虚空。","effect_spec":{"exclusive_outcome":"mismatch"},"weight":1},{"code":"exclusive_risk_result_01","grade":"专属","polarity":"risk","sequence":1,"title":"残意滞脉","narrative":"传承虽然没有成功降临，但残留道意仍让你窥见了一丝玄妙。","effect_spec":{"cultivation_gain_pct":0.008,"speed_bonus":-0.08,"duration_minutes":60},"weight":1},{"code":"exclusive_risk_result_02","grade":"专属","polarity":"risk","sequence":2,"title":"截文耗神","narrative":"你强行稳住崩解的经文，从中截取少量灵机，却消耗了大量心神。","effect_spec":{"cultivation_gain_pct":0.006,"speed_bonus":-0.12,"duration_minutes":60},"weight":1},{"code":"exclusive_risk_result_03","grade":"专属","polarity":"risk","sequence":3,"title":"乱流散修","narrative":"虚空乱流冲散部分修为，但也带来了一些可被利用的残留资源。","effect_spec":{"cultivation_loss_current_pct":0.08,"cultivation_loss_stage_cap_pct":0.015,"spirit_gain_mult":5.0},"weight":1},{"code":"exclusive_risk_result_04","grade":"专属","polarity":"risk","sequence":4,"title":"稳命耗石","narrative":"你以大量灵石稳固命格，才没有让天机反噬继续扩大。","effect_spec":{"spirit_loss_balance_pct":0.02,"spirit_loss_base_mult":15.0,"cultivation_gain_pct":0.005},"weight":1},{"code":"exclusive_risk_result_05","grade":"专属","polarity":"risk","sequence":5,"title":"余气滞识","narrative":"专属天机被迫中断，残余气息长时间滞留识海。","effect_spec":{"speed_bonus":-0.1,"duration_minutes":120,"spirit_gain_mult":3.0},"weight":1},{"code":"exclusive_risk_result_06","grade":"专属","polarity":"risk","sequence":6,"title":"道音撼魂","narrative":"混乱道音撼动神魂，使部分修为散失，但你也看清了根基的一处缺漏。","effect_spec":{"cultivation_loss_current_pct":0.06,"cultivation_loss_stage_cap_pct":0.01,"cultivation_gain_pct":0.004},"weight":1},{"code":"exclusive_risk_result_07","grade":"专属","polarity":"risk","sequence":7,"title":"驱异耗资","narrative":"你成功驱散了异命气息，却在过程中耗费了大量灵石与精力。","effect_spec":{"spirit_loss_balance_pct":0.015,"spirit_loss_base_mult":10.0,"speed_bonus":-0.08,"duration_minutes":60},"weight":1},{"code":"exclusive_risk_result_08","grade":"专属","polarity":"risk","sequence":8,"title":"五法震魂","narrative":"五道功法虚影相互冲突，神魂受到明显震荡，你保住了一丝残余感悟。","effect_spec":{"cultivation_gain_pct":0.01,"speed_bonus":-0.15,"duration_minutes":120},"weight":1},{"code":"exclusive_risk_result_09","grade":"专属","polarity":"risk","sequence":9,"title":"命格反噬","narrative":"命格共鸣失败，引发短暂反噬，但崩散经文留下了一些天道余辉。","effect_spec":{"cultivation_loss_current_pct":0.1,"cultivation_loss_stage_cap_pct":0.02,"spirit_gain_mult":8.0},"weight":1},{"code":"exclusive_risk_result_10","grade":"专属","polarity":"risk","sequence":10,"title":"碎法残意","narrative":"专属传承彻底破碎，强大余波冲击全身，你从毁灭中截取了少量大道残意。","effect_spec":{"cultivation_loss_current_pct":0.12,"cultivation_loss_stage_cap_pct":0.025,"speed_bonus":-0.1,"duration_minutes":120,"cultivation_gain_pct":0.008},"weight":1}]'::jsonb)
  as x(code text,grade text,polarity text,sequence integer,title text,narrative text,effect_spec jsonb,weight numeric)
on conflict(code) do update set grade=excluded.grade,polarity=excluded.polarity,sequence=excluded.sequence,title=excluded.title,narrative=excluded.narrative,effect_spec=excluded.effect_spec,weight=excluded.weight,is_active=true,updated_at=now();

-- 普通机缘功法扩充：原12门主修完整保留，新增12门辅修。
-- 功法自身效果沿用V0.11.5线性成长：一级完整效果，每级增加一级基础效果10%。
insert into public.techniques(code,name,category,grade,element,fixed_effects,learn_conditions,side_effects,description) values
('opp_support_jingshui','静水调息篇','support','mystic',null,'{"v3_base_cultivation_multiplier":0.01,"linear_growth_per_level":0.10}','{}','{}','玄品辅修；一级修炼速度+1%，每级线性增加一级基础效果10%。'),
('opp_support_weichen','微尘引灵术','support','mystic',null,'{"v3_base_cultivation_per_second":1,"linear_growth_per_level":0.10}','{}','{}','玄品辅修；一级每秒修为+1，每级线性增加一级基础效果10%。'),
('opp_support_liangyi','两仪养元诀','support','earth',null,'{"v3_base_cultivation_multiplier":0.03,"linear_growth_per_level":0.10}','{}','{}','地品辅修；一级修炼速度+3%，每级线性增加一级基础效果10%。'),
('opp_support_mianxi','绵息周天法','support','earth',null,'{"v3_base_cultivation_per_second":2,"linear_growth_per_level":0.10}','{}','{}','地品辅修；一级每秒修为+2，每级线性增加一级基础效果10%。'),
('opp_support_yushu','玉枢辅脉篇','support','earth',null,'{"v3_base_cultivation_multiplier":0.04,"linear_growth_per_level":0.10}','{}','{}','地品辅修；一级修炼速度+4%，每级线性增加一级基础效果10%。'),
('opp_support_xinghe','星河辅元经','support','heaven',null,'{"v3_base_cultivation_multiplier":0.07,"linear_growth_per_level":0.10}','{}','{}','天品辅修；一级修炼速度+7%，每级线性增加一级基础效果10%。'),
('opp_support_taiqing','太清归息法','support','heaven',null,'{"v3_base_cultivation_per_second":6,"linear_growth_per_level":0.10}','{}','{}','天品辅修；一级每秒修为+6，每级线性增加一级基础效果10%。'),
('opp_support_qingming','青冥养神篇','support','heaven',null,'{"v3_base_cultivation_multiplier":0.08,"linear_growth_per_level":0.10}','{}','{}','天品辅修；一级修炼速度+8%，每级线性增加一级基础效果10%。'),
('opp_support_jiuzhuan','九转聚灵诀','support','heaven',null,'{"v3_base_cultivation_per_second":8,"linear_growth_per_level":0.10}','{}','{}','天品辅修；一级每秒修为+8，每级线性增加一级基础效果10%。'),
('opp_support_zifu','紫府仙息经','support','immortal',null,'{"v3_base_cultivation_multiplier":0.14,"linear_growth_per_level":0.10}','{}','{}','仙品辅修；一级修炼速度+14%，每级线性增加一级基础效果10%。'),
('opp_support_taichu','太初辅元录','support','immortal',null,'{"v3_base_cultivation_per_second":16,"linear_growth_per_level":0.10}','{}','{}','仙品辅修；一级每秒修为+16，每级线性增加一级基础效果10%。'),
('opp_support_hunyuan','混元灵台篇','support','immortal',null,'{"v3_base_cultivation_multiplier":0.16,"linear_growth_per_level":0.10}','{}','{}','仙品辅修；一级修炼速度+16%，每级线性增加一级基础效果10%。')
on conflict(code) do update set name=excluded.name,category=excluded.category,grade=excluded.grade,fixed_effects=excluded.fixed_effects,description=excluded.description,is_active=true;

-- 各品级主修/辅修掉落概率。这里是“已经抽中对应品级且趋吉后”的概率。
-- 原主修概率保持不变；新增辅修概率为原主修的一半；单次至多获得一门普通功法。
create table if not exists public.opportunity_v4_technique_drop_rates(
  grade text primary key check(grade in('玄品','地品','天品','仙品')),
  main_rate numeric not null check(main_rate>=0 and main_rate<=1),
  support_rate numeric not null check(support_rate>=0 and support_rate<=1),
  updated_at timestamptz not null default now()
);
insert into public.opportunity_v4_technique_drop_rates(grade,main_rate,support_rate) values
('玄品',2.0/72.0,1.0/72.0),
('地品',3.0/45.0,1.5/45.0),
('天品',4.0/24.0,2.0/24.0),
('仙品',3.0/9.0,1.5/9.0)
on conflict(grade) do update set main_rate=excluded.main_rate,support_rate=excluded.support_rate,updated_at=now();

-- 功法池：保留旧12门主修与其原机缘附带奖励；新增12门辅修及首次获得奖励。
create table if not exists public.opportunity_v4_technique_pool(
  technique_code text primary key,
  technique_name text not null,
  grade text not null check(grade in('玄品','地品','天品','仙品')),
  category text not null check(category in('main','support')),
  acquisition_title text not null,
  acquisition_narrative text not null,
  first_reward_spec jsonb not null default '{}'::jsonb,
  weight numeric not null default 1 check(weight>0),
  is_active boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.opportunity_v4_technique_pool(technique_code,technique_name,grade,category,acquisition_title,acquisition_narrative,first_reward_spec,weight) values
-- 原主修：额外奖励按旧机缘完整保留，仅首次获得时发放，重复获得只转传承点。
('opp_qingquan','清泉纳灵诀','玄品','main','残简心法','你从残破竹简中悟得清泉纳灵之法，灵息如水般贯通周身。','{"permanent_speed_bonus":0.02}',1),
('opp_rumen','入门吐纳法','玄品','main','功法残片','你将散落的功法残片拼合，习得一门朴素而稳健的吐纳法。','{"permanent_speed_bonus":0.01}',1),
('opp_jichu','基础吐纳法','地品','main','功法石刻','石壁残刻补全了你的行功思路，一门基础吐纳之法由此成形。','{"cultivation_gain_fixed":2000}',1),
('opp_zhoutian_yangqi','周天养气术','地品','main','周天顿悟','你在周天运转中寻得隐秘支脉，养气之法自此圆融。','{"permanent_flat_rate":4}',1),
('opp_cuqian','粗浅吐纳法','地品','main','残简心法','残简中的粗浅法门与你当前根基相合，修行由此多了一条稳妥路径。','{"permanent_speed_bonus":0.01}',1),
('opp_liuyun','流云吐纳法','天品','main','上古传承','上古修士留下的完整传承化作流云道纹，融入你的识海。','{"cultivation_gain_fixed":50000}',1),
('opp_zhoutian_tuna','周天吐纳术','天品','main','隐世指点','隐世散修点明周天关键，你由此掌握更高层次的吐纳之术。','{"cultivation_gain_fixed":10000}',1),
('opp_qingshi','青石养气诀','天品','main','功法残篇','青石残篇中的经文逐字亮起，你终于补全其中养气法门。','{"cultivation_gain_fixed":10000}',1),
('opp_qianxi','浅溪养气诀','天品','main','吐纳顿悟','灵气如浅溪不断流转，你在顿悟中重构了吐纳节奏。','{"permanent_flat_rate":4}',1),
('opp_hongmeng','鸿蒙引气章','仙品','main','大道共鸣','鸿蒙道韵洗涤根基，一篇古老引气章在识海中完整显化。','{"permanent_speed_bonus":0.25,"cultivation_gain_fixed":200000}',1),
('opp_dongtian','洞天养元诀','仙品','main','洞天本源','洞天本源灌入灵脉，一门养元仙诀随空间道纹一同显现。','{"cultivation_gain_fixed":200000,"cave_daily_spirit_mapping":120}',1),
('opp_cangyuan','苍元仙法','仙品','main','上古仙缘','上古洞天的完整传承归入识海，苍元仙法自此认主。','{"permanent_speed_bonus":0.22,"cultivation_gain_fixed":200000,"spirit_gain_fixed":50000}',1),
-- 新辅修。
('opp_support_jingshui','静水调息篇','玄品','support','静水调息','你从一卷浸水残经中悟得静水调息之法，吐纳之间渐有清泉不争之意。','{"permanent_speed_bonus":0.01}',1),
('opp_support_weichen','微尘引灵术','玄品','support','微尘引灵','你观察微尘随灵气浮沉，逐渐领悟从细微灵机中积蓄修为的方法。','{"cultivation_gain_pct":0.005}',1),
('opp_support_liangyi','两仪养元诀','地品','support','两仪养元','阴阳二气在残阵中往复流转，你借此悟出调和元气、辅助主修的法门。','{"cultivation_gain_pct":0.012}',1),
('opp_support_mianxi','绵息周天法','地品','support','绵息周天','你在古修周天图中寻得一条隐秘支脉，自此吐纳绵延不绝。','{"permanent_flat_rate":2}',1),
('opp_support_yushu','玉枢辅脉篇','地品','support','玉枢辅脉','玉简经文不直接运转丹田，而是温养经脉、辅助诸法。','{"permanent_speed_bonus":0.01}',1),
('opp_support_xinghe','星河辅元经','天品','support','星河辅元','星辉沿经脉缓缓流转，为主修功法牵引天地灵气。','{"cultivation_gain_pct":0.03}',1),
('opp_support_taiqing','太清归息法','天品','support','太清归息','一缕太清之气归入丹田，使你在行走坐卧间也能积蓄修为。','{"cultivation_gain_pct":0.02,"spirit_gain_mult":3}',1),
('opp_support_qingming','青冥养神篇','天品','support','青冥养神','你于青冥幻境中稳住神魂，悟得以神养气、以气辅法的修炼之道。','{"permanent_speed_bonus":0.03}',1),
('opp_support_jiuzhuan','九转聚灵诀','天品','support','九转聚灵','九道聚灵阵纹在识海中接连运转，将散逸灵气重新引入周天。','{"permanent_flat_rate":3}',1),
('opp_support_zifu','紫府仙息经','仙品','support','紫府仙息','紫府之中仙气自生，呼吸之间便有大道灵机相随。','{"permanent_speed_bonus":0.10,"cultivation_gain_pct":0.06}',1),
('opp_support_taichu','太初辅元录','仙品','support','太初辅元','太初之气化作源源不断的本源灵机，辅助诸法自行运转。','{"permanent_flat_rate":8,"cultivation_gain_pct":0.06}',1),
('opp_support_hunyuan','混元灵台篇','仙品','support','混元灵台','灵台化作混元之象，诸般功法气息在其中相生相济。','{"permanent_speed_bonus":0.08,"cultivation_gain_pct":0.06,"spirit_gain_mult":20}',1)
on conflict(technique_code) do update set technique_name=excluded.technique_name,grade=excluded.grade,category=excluded.category,acquisition_title=excluded.acquisition_title,acquisition_narrative=excluded.acquisition_narrative,first_reward_spec=excluded.first_reward_spec,weight=excluded.weight,is_active=true,updated_at=now();

-- 首次获得功法时应用该机缘原有/新增附带奖励；重复只由旧函数转传承点。
create or replace function public.opportunity_v4_award_ordinary_technique(
  p_character_id uuid,
  p_lineage_id uuid,
  p_world_year integer,
  p_technique_code text,
  p_scheduled_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  p record;t record;v_existed boolean:=false;v_award jsonb;v_basis jsonb;v_b numeric:=1;v_s numeric:=100;
  v_spec jsonb:='{}'::jsonb;v_cgain bigint:=0;v_sgain bigint:=0;v_delta bigint:=0;v_mastery integer:=0;
  v_permanent jsonb:='[]'::jsonb;v_items jsonb:='{}'::jsonb;v_cave jsonb;v_amount numeric:=0;
begin
  select * into p from public.opportunity_v4_technique_pool where technique_code=p_technique_code and is_active;
  select id,code,name,grade,category into t from public.techniques where code=p_technique_code and is_active limit 1;
  if p.technique_code is null or t.id is null then
    return jsonb_build_object('awarded',false,'reason','TECHNIQUE_POOL_OR_DEFINITION_MISSING','technique_code',p_technique_code);
  end if;
  select exists(select 1 from public.character_techniques where character_id=p_character_id and technique_id=t.id) into v_existed;
  v_award:=public.award_opportunity_technique_v3(p_character_id,t.name,p_world_year);
  if v_existed then
    v_mastery:=case t.grade when 'immortal' then 80 when 'heaven' then 65 when 'earth' then 50 when 'mystic' then 40 when 'yellow' then 30 else 25 end;
    return jsonb_build_object(
      'awarded',true,'is_new',false,'technique_code',t.code,'technique_name',t.name,'grade',p.grade,'grade_code',t.grade,'category',t.category,
      'mastery_points',v_mastery,'permanent_effects','[]'::jsonb,'items','{}'::jsonb,
      'applied',jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',0,'spirit_loss',0,'speed_bonus',0,'duration_minutes',0),
      'narrative','再次参悟《'||t.name||'》，重复传承已转化为'||v_mastery||'点传承点。'
    );
  end if;

  v_spec:=coalesce(p.first_reward_spec,'{}'::jsonb);
  v_basis:=public.opportunity_v4_stage_basis(p_character_id);
  v_b:=greatest(1,coalesce((v_basis->>'cultivation_basis')::numeric,1));
  v_s:=greatest(1,coalesce((v_basis->>'spirit_stone_basis')::numeric,100));
  if v_spec ? 'cultivation_gain_fixed' then v_cgain:=v_cgain+greatest(0,(v_spec->>'cultivation_gain_fixed')::bigint);end if;
  if v_spec ? 'cultivation_gain_pct' then v_cgain:=v_cgain+greatest(0,round(v_b*(v_spec->>'cultivation_gain_pct')::numeric)::bigint);end if;
  if v_spec ? 'spirit_gain_fixed' then v_sgain:=v_sgain+greatest(0,(v_spec->>'spirit_gain_fixed')::bigint);end if;
  if v_spec ? 'spirit_gain_mult' then v_sgain:=v_sgain+greatest(0,round(v_s*(v_spec->>'spirit_gain_mult')::numeric)::bigint);end if;
  if v_sgain>0 then v_delta:=public.opportunity_v4_adjust_spirit_stones(p_character_id,v_sgain);v_sgain:=greatest(0,v_delta);end if;

  if v_spec ? 'permanent_speed_bonus' then
    v_amount:=(v_spec->>'permanent_speed_bonus')::numeric;
    insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
    values(p_character_id,'opportunity','opportunity_v4:first:'||t.code||':multiplier','机缘功法初得·'||t.name,0,v_amount,p_scheduled_at,null,true,jsonb_build_object('kind','technique_first_reward','technique_code',t.code,'grade',p.grade));
    v_permanent:=v_permanent||jsonb_build_array('《'||t.name||'》初得：永久修炼速度+'||trim(to_char(v_amount*100,'FM999990.##'))||'%');
  end if;
  if v_spec ? 'permanent_flat_rate' then
    v_amount:=(v_spec->>'permanent_flat_rate')::numeric;
    insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
    values(p_character_id,'opportunity','opportunity_v4:first:'||t.code||':flat','机缘功法初得·'||t.name,v_amount,0,p_scheduled_at,null,true,jsonb_build_object('kind','technique_first_reward','technique_code',t.code,'grade',p.grade));
    v_permanent:=v_permanent||jsonb_build_array('《'||t.name||'》初得：永久每秒修为+'||trim(to_char(v_amount,'FM999990.###')));
  end if;
  if v_spec ? 'cave_daily_spirit_mapping' then
    v_cave:=public.award_cave_resource_v3(p_lineage_id,t.code,(v_spec->>'cave_daily_spirit_mapping')::numeric);
    if coalesce((v_cave->>'awarded')::boolean,false) then
      v_items:=jsonb_build_object(v_cave->>'resource_name',(v_cave->>'amount')::numeric);
    end if;
  end if;
  return jsonb_build_object(
    'awarded',true,'is_new',true,'technique_code',t.code,'technique_name',t.name,'grade',p.grade,'grade_code',t.grade,'category',t.category,
    'mastery_points',0,'permanent_effects',v_permanent,'items',v_items,
    'applied',jsonb_build_object('cultivation_gain_requested',v_cgain,'cultivation_loss_requested',0,'spirit_gain',v_sgain,'spirit_loss',0,'speed_bonus',0,'duration_minutes',0,'basis',v_basis),
    'narrative',p.acquisition_narrative||' 获得'||case when t.category='support' then '辅修' else '主修' end||'功法《'||t.name||'》。'
  );
end$$;

-- 当前小境界完整需求B与境界灵石基数S。
create or replace function public.opportunity_v4_stage_basis(p_character_id uuid)
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  select jsonb_build_object(
    'stage_floor',coalesce(rs.cultivation_required,0),
    'stage_cap',coalesce(public.character_cultivation_cap_v1(pc.realm_stage_id),coalesce(rs.cultivation_required,0)+greatest(1,public.realm_base_cultivation_rate_v1(pc.realm_stage_id)::bigint*3600)),
    'cultivation_basis',greatest(1,coalesce(public.character_cultivation_cap_v1(pc.realm_stage_id),coalesce(rs.cultivation_required,0)+greatest(1,public.realm_base_cultivation_rate_v1(pc.realm_stage_id)::bigint*3600))-coalesce(rs.cultivation_required,0)),
    'spirit_stone_basis',greatest(100,round(greatest(1,coalesce(public.character_cultivation_cap_v1(pc.realm_stage_id),coalesce(rs.cultivation_required,0)+1)-coalesce(rs.cultivation_required,0))::numeric/200)::bigint),
    'stage_name',rs.stage_name,'realm_stage_id',pc.realm_stage_id
  )
  from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id
  where pc.id=p_character_id
$$;

-- 唯一统一灵石账户的安全增减；负数只扣到0，返回真实变动。
create or replace function public.opportunity_v4_adjust_spirit_stones(p_character_id uuid,p_delta bigint)
returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare v_item uuid;v_before bigint:=0;v_after bigint:=0;begin
  select id into v_item from public.item_definitions where code='spirit_stone' limit 1;
  if v_item is null then raise exception 'SPIRIT_STONE_ITEM_MISSING'; end if;
  select quantity into v_before from public.character_inventory where character_id=p_character_id and item_definition_id=v_item for update;
  if not found then
    if coalesce(p_delta,0)<=0 then return 0; end if;
    insert into public.character_inventory(character_id,item_definition_id,quantity,is_bound,item_instance,acquired_year)
    values(p_character_id,v_item,p_delta,false,'{}'::jsonb,1);
    return p_delta;
  end if;
  v_after:=greatest(0,coalesce(v_before,0)+coalesce(p_delta,0));
  update public.character_inventory set quantity=v_after,updated_at=now() where character_id=p_character_id and item_definition_id=v_item;
  return v_after-coalesce(v_before,0);
end$$;

-- 将单条结果转成动态数值；修为即时变化在挂机结算后统一应用，速度效果按历史时间写入。
create or replace function public.opportunity_v4_prepare_effect(
  p_character_id uuid,p_result_id uuid,p_grade text,p_polarity text,p_effect jsonb,p_scheduled_at timestamptz
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_basis jsonb:=public.opportunity_v4_stage_basis(p_character_id);
  v_b numeric:=greatest(1,coalesce((v_basis->>'cultivation_basis')::numeric,1));
  v_s numeric:=greatest(1,coalesce((v_basis->>'spirit_stone_basis')::numeric,100));
  v_current bigint;v_stones bigint:=0;v_random numeric:=0.9+random()*0.2;
  v_cgain bigint:=0;v_closs bigint:=0;v_sgain bigint:=0;v_sloss bigint:=0;
  v_speed numeric:=coalesce((p_effect->>'speed_bonus')::numeric,0);
  v_minutes integer:=greatest(0,coalesce((p_effect->>'duration_minutes')::integer,0));
  v_delta bigint:=0;
begin
  select cultivation into v_current from public.player_characters where id=p_character_id for update;
  select coalesce(ci.quantity,0) into v_stones from public.character_inventory ci join public.item_definitions i on i.id=ci.item_definition_id where ci.character_id=p_character_id and i.code='spirit_stone' limit 1;
  v_stones:=coalesce(v_stones,0);
  if p_effect ? 'cultivation_gain_pct' then v_cgain:=greatest(0,round(v_b*(p_effect->>'cultivation_gain_pct')::numeric*v_random)::bigint); end if;
  if p_effect ? 'cultivation_loss_current_pct' then
    v_closs:=least(
      greatest(0,round(greatest(0,v_current-coalesce((v_basis->>'stage_floor')::bigint,0))*(p_effect->>'cultivation_loss_current_pct')::numeric)::bigint),
      greatest(0,round(v_b*coalesce((p_effect->>'cultivation_loss_stage_cap_pct')::numeric,0))::bigint)
    );
  end if;
  if p_effect ? 'spirit_gain_mult' then
    v_sgain:=greatest(0,round(v_s*(p_effect->>'spirit_gain_mult')::numeric*v_random)::bigint);
    v_delta:=public.opportunity_v4_adjust_spirit_stones(p_character_id,v_sgain);v_sgain:=greatest(0,v_delta);
  end if;
  if p_effect ? 'spirit_loss_balance_pct' then
    v_sloss:=least(
      greatest(0,round(v_stones*(p_effect->>'spirit_loss_balance_pct')::numeric)::bigint),
      greatest(0,round(v_s*coalesce((p_effect->>'spirit_loss_base_mult')::numeric,0))::bigint)
    );
    v_delta:=public.opportunity_v4_adjust_spirit_stones(p_character_id,-v_sloss);v_sloss:=greatest(0,-v_delta);
  end if;
  if v_speed<>0 and v_minutes>0 then
    insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
    values(p_character_id,'opportunity_v4','opportunity_v4:'||p_result_id::text,
      case when v_speed>0 then '机缘·趋吉修炼增益' else '机缘·涉险修炼减益' end,
      0,v_speed,p_scheduled_at,p_scheduled_at+make_interval(mins=>v_minutes),true,
      jsonb_build_object('result_id',p_result_id,'grade',p_grade,'polarity',p_polarity,'stack_rule','strongest_positive_plus_strongest_negative'));
  end if;
  return jsonb_build_object('cultivation_gain_requested',v_cgain,'cultivation_loss_requested',v_closs,'spirit_gain',v_sgain,'spirit_loss',v_sloss,'speed_bonus',v_speed,'duration_minutes',v_minutes,'basis',v_basis);
end$$;

-- V4机缘效果仅正面取最大、负面取最小；其他系统继续原样求和，天劫感悟最终乘区不变。
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

    select
      coalesce(sum(e.flat_rate_per_second), 0),
      coalesce(sum(e.multiplier_bonus) filter (where e.source_type <> 'opportunity_v4'), 0)
      + coalesce(max(e.multiplier_bonus) filter (where e.source_type = 'opportunity_v4' and e.multiplier_bonus > 0), 0)
      + coalesce(min(e.multiplier_bonus) filter (where e.source_type = 'opportunity_v4' and e.multiplier_bonus < 0), 0)
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

  select
    coalesce(sum(e.flat_rate_per_second), 0),
    coalesce(sum(e.multiplier_bonus) filter (where e.source_type <> 'opportunity_v4'), 0)
    + coalesce(max(e.multiplier_bonus) filter (where e.source_type = 'opportunity_v4' and e.multiplier_bonus > 0), 0)
    + coalesce(min(e.multiplier_bonus) filter (where e.source_type = 'opportunity_v4' and e.multiplier_bonus < 0), 0)
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

create or replace function public.opportunity_v4_remaining_effects(p_character_id uuid,p_at timestamptz default clock_timestamp())
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  with live as(
    select multiplier_bonus,expires_at from public.character_cultivation_effects
    where character_id=p_character_id and source_type='opportunity_v4' and is_active
      and starts_at<=p_at and (expires_at is null or expires_at>p_at)
  ), picked as(
    select max(multiplier_bonus) filter(where multiplier_bonus>0) pos,
           min(multiplier_bonus) filter(where multiplier_bonus<0) neg,
           min(expires_at) filter(where multiplier_bonus=(select max(multiplier_bonus) from live where multiplier_bonus>0)) pos_exp,
           min(expires_at) filter(where multiplier_bonus=(select min(multiplier_bonus) from live where multiplier_bonus<0)) neg_exp
    from live
  ) select jsonb_strip_nulls(jsonb_build_object(
    'positive',case when pos is not null then jsonb_build_object('rate',pos,'expires_at',pos_exp,'remaining_seconds',greatest(0,extract(epoch from(pos_exp-p_at))::bigint)) end,
    'negative',case when neg is not null then jsonb_build_object('rate',neg,'expires_at',neg_exp,'remaining_seconds',greatest(0,extract(epoch from(neg_exp-p_at))::bigint)) end,
    'net_rate',coalesce(pos,0)+coalesce(neg,0)
  )) from picked
$$;

-- 统一结算入口：先补算机缘并写入历史速度效果，再调用V0.14.4修为结算，最后应用即时修为净变化。
create or replace function public.settle_opportunity_v4(p_settle_cultivation boolean default true)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  u uuid:=auth.uid();c public.player_characters%rowtype;st public.character_opportunity_v3_state%rowtype;cfg public.opportunity_v3_settings%rowtype;
  nowv timestamptz:=clock_timestamp();v_period_start timestamptz;v_event_at timestamptz;v_due integer:=0;v_capped integer:=0;v_gap numeric:=0;v_offline boolean:=false;
  v_batch uuid:=gen_random_uuid();v_grade text;v_path text;v_story record;v_result record;v_effect jsonb;v_applied jsonb;v_result_id uuid;
  v_fate_code text;v_lucky boolean:=false;v_ausp numeric:=50;v_roll numeric;v_total numeric;v_boost numeric:=1;
  w_ex numeric:=0.2;w_im numeric:=0.5;w_he numeric:=1.5;w_ea numeric:=8;w_my numeric:=25;w_ye numeric:=64.8;
  v_grade_counts jsonb:='{"黄品":0,"玄品":0,"地品":0,"天品":0,"仙品":0,"专属":0}'::jsonb;
  v_path_counts jsonb:='{"趋吉":0,"涉险":0}'::jsonb;
  v_cgain_req bigint:=0;v_closs_req bigint:=0;v_sgain bigint:=0;v_sloss bigint:=0;v_actual_gain bigint:=0;v_actual_loss bigint:=0;
  v_claim jsonb:=null;v_summary jsonb:=null;v_latest jsonb:=null;v_remaining jsonb:='{}'::jsonb;v_floor bigint:=0;v_before bigint;v_grant record;
  v_fate_has boolean:=false;v_has_own boolean:=false;v_pity numeric:=20;v_other numeric:=20;v_pick numeric;v_running numeric;v_exclusive record;v_acquired jsonb;
  v_rates record;v_tech_category text;v_tech_pool record;v_tech_award jsonb;v_tech_new jsonb:='[]'::jsonb;v_tech_dup jsonb:='[]'::jsonb;
  v_mastery integer:=0;v_permanent jsonb:='[]'::jsonb;v_items_gain jsonb:='{}'::jsonb;v_item record;v_item_amount numeric;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
  if c.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  select * into cfg from public.opportunity_v3_settings where world_code='jiuxiao_world_1';
  if cfg.world_code is null then raise exception 'OPPORTUNITY_SETTINGS_MISSING'; end if;
  insert into public.character_opportunity_v3_state(character_id,next_available_at,last_seen_at)
  values(c.id,nowv+interval '5 minutes',nowv) on conflict(character_id) do nothing;
  select * into st from public.character_opportunity_v3_state where character_id=c.id for update;
  select f.code into v_fate_code from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
  v_lucky:=coalesce(v_fate_code='lucky_encounter',false);
  v_ausp:=public.opportunity_v3_auspicious_probability_v1(c.luck,c.mindset,v_lucky);
  v_period_start:=least(coalesce(st.last_seen_at,nowv),nowv);v_gap:=greatest(0,extract(epoch from(nowv-v_period_start)));v_offline:=v_gap>=300;
  if cfg.enabled and nowv>=st.next_available_at then
    v_due:=floor(extract(epoch from(nowv-st.next_available_at))/300)::integer+1;
    v_capped:=greatest(0,v_due-least(v_due,coalesce(cfg.offline_catchup_limit,864)));v_due:=least(v_due,coalesce(cfg.offline_catchup_limit,864));
  end if;

  if v_due>0 then
    for i in 0..v_due-1 loop
      v_event_at:=st.next_available_at+make_interval(secs=>300*i);
      if v_lucky then v_boost:=1.10; else v_boost:=1; end if;
      w_ex:=0.2*v_boost;w_im:=0.5*v_boost;w_he:=1.5*v_boost;w_ea:=8*v_boost;w_my:=25;w_ye:=64.8;v_total:=w_ex+w_im+w_he+w_ea+w_my+w_ye;v_roll:=random()*v_total;
      if v_roll<w_ex then v_grade:='专属';elsif v_roll<w_ex+w_im then v_grade:='仙品';elsif v_roll<w_ex+w_im+w_he then v_grade:='天品';elsif v_roll<w_ex+w_im+w_he+w_ea then v_grade:='地品';elsif v_roll<w_ex+w_im+w_he+w_ea+w_my then v_grade:='玄品';else v_grade:='黄品';end if;
      v_path:=case when random()*100<v_ausp then 'auspicious' else 'risk' end;
      select * into v_story from public.opportunity_v4_story_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
      if v_story.code is null then raise exception 'OPPORTUNITY_V4_STORY_MISSING:%:%',v_grade,v_path; end if;
      v_grade_counts:=jsonb_set(v_grade_counts,array[v_grade],to_jsonb(coalesce((v_grade_counts->>v_grade)::int,0)+1),true);
      v_path_counts:=jsonb_set(v_path_counts,array[case when v_path='auspicious' then '趋吉' else '涉险' end],to_jsonb(coalesce((v_path_counts->>(case when v_path='auspicious' then '趋吉' else '涉险' end))::int,0)+1),true);
      v_tech_award:=null;v_tech_category:=null;

      if v_grade='专属' and v_path='auspicious' then
        select exists(select 1 from public.exclusive_technique_definitions where fate_code=v_fate_code) into v_fate_has;
        select exists(select 1 from public.character_exclusive_techniques cet join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code where cet.character_id=c.id and etd.fate_code=v_fate_code) into v_has_own;
        if v_fate_has then v_pity:=greatest(20,least(100,coalesce((st.exclusive_pity->>v_fate_code)::numeric,20)));if v_has_own then v_pity:=0;end if;v_other:=case when v_has_own then 25 else(100-v_pity)/4 end;else v_pity:=0;v_other:=20;end if;
        v_pick:=random()*100;v_running:=0;
        for v_exclusive in select etd.*,case when etd.fate_code=v_fate_code then v_pity else v_other end draw_weight from public.exclusive_technique_definitions etd order by etd.code loop v_running:=v_running+v_exclusive.draw_weight;if v_pick<=v_running then exit;end if;end loop;
        if v_exclusive.fate_code=v_fate_code and not v_has_own then
          select * into v_result from public.opportunity_v4_result_pool where grade='专属' and polarity='auspicious' and effect_spec->>'exclusive_outcome'='success' and is_active order by random() limit 1;
          update public.character_exclusive_techniques set equipped=false where character_id=c.id;
          insert into public.character_exclusive_techniques(character_id,exclusive_code,level,equipped) values(c.id,v_exclusive.code,1,true) on conflict(character_id,exclusive_code) do update set equipped=true;
          v_acquired:=coalesce(st.acquired_exclusive_codes,'[]'::jsonb);if not(v_acquired@>jsonb_build_array(v_exclusive.code)) then v_acquired:=v_acquired||jsonb_build_array(v_exclusive.code);end if;
          st.acquired_exclusive_codes:=v_acquired;st.exclusive_pity:=jsonb_set(coalesce(st.exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(20),true);
          update public.character_opportunity_v3_state set acquired_exclusive_codes=st.acquired_exclusive_codes,exclusive_pity=st.exclusive_pity,updated_at=nowv where character_id=c.id;
          perform public.refresh_exclusive_technique_effects_v1(c.id);
          v_result.title:='专属功法·'||v_exclusive.name;v_result.narrative:=v_result.narrative||' 获得专属功法《'||v_exclusive.name||'》，已进入独立专属槽并立即生效。';v_effect='{}'::jsonb;
          v_tech_new:=v_tech_new||jsonb_build_array(jsonb_build_object('name',v_exclusive.name,'grade','专属','category','exclusive'));
        else
          select * into v_result from public.opportunity_v4_result_pool where grade='专属' and polarity='auspicious' and effect_spec->>'exclusive_outcome'='mismatch' and is_active order by random() limit 1;
          if v_fate_has and not v_has_own then v_pity:=least(100,v_pity+2);st.exclusive_pity:=jsonb_set(coalesce(st.exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(v_pity),true);update public.character_opportunity_v3_state set exclusive_pity=st.exclusive_pity,updated_at=nowv where character_id=c.id;end if;
          v_result.title:='专属机缘·天道收回';v_result.narrative:=v_result.narrative||' 落下的是《'||v_exclusive.name||'》，却与你命格不合，被天道收回。';v_effect=jsonb_build_object('spirit_gain_fixed',100);
        end if;
      elsif v_path='auspicious' and v_grade in('玄品','地品','天品','仙品') then
        select * into v_rates from public.opportunity_v4_technique_drop_rates where grade=v_grade;
        v_roll:=random();
        if v_roll<coalesce(v_rates.main_rate,0) then v_tech_category:='main';
        elsif v_roll<coalesce(v_rates.main_rate,0)+coalesce(v_rates.support_rate,0) then v_tech_category:='support';end if;
        if v_tech_category is not null then
          select * into v_tech_pool from public.opportunity_v4_technique_pool where grade=v_grade and category=v_tech_category and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
          if v_tech_pool.technique_code is null then raise exception 'OPPORTUNITY_V4_TECHNIQUE_POOL_MISSING:%:%',v_grade,v_tech_category;end if;
          v_tech_award:=public.opportunity_v4_award_ordinary_technique(c.id,c.lineage_id,greatest(1,c.birth_year+c.age),v_tech_pool.technique_code,v_event_at);
          select ('technique:'||v_tech_pool.technique_code)::text as code,('功法·'||v_tech_pool.technique_name)::text as title,(v_tech_award->>'narrative')::text as narrative,'{}'::jsonb as effect_spec into v_result;
          v_effect:='{}'::jsonb;v_applied:=coalesce(v_tech_award->'applied','{}'::jsonb);
          if coalesce((v_tech_award->>'is_new')::boolean,false) then
            v_tech_new:=v_tech_new||jsonb_build_array(jsonb_build_object('name',v_tech_award->>'technique_name','code',v_tech_award->>'technique_code','grade',v_tech_award->>'grade','category',v_tech_award->>'category'));
          else
            v_tech_dup:=v_tech_dup||jsonb_build_array(jsonb_build_object('name',v_tech_award->>'technique_name','code',v_tech_award->>'technique_code','grade',v_tech_award->>'grade','category',v_tech_award->>'category','mastery_points',coalesce((v_tech_award->>'mastery_points')::int,0)));
            v_mastery:=v_mastery+coalesce((v_tech_award->>'mastery_points')::int,0);
          end if;
          v_permanent:=v_permanent||coalesce(v_tech_award->'permanent_effects','[]'::jsonb);
          for v_item in select key,value from jsonb_each_text(coalesce(v_tech_award->'items','{}'::jsonb)) loop
            v_item_amount:=coalesce((v_items_gain->>v_item.key)::numeric,0)+coalesce(v_item.value::numeric,0);
            v_items_gain:=jsonb_set(v_items_gain,array[v_item.key],to_jsonb(v_item_amount),true);
          end loop;
        else
          select * into v_result from public.opportunity_v4_result_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
          v_effect:=v_result.effect_spec;
        end if;
      else
        select * into v_result from public.opportunity_v4_result_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
        v_effect:=v_result.effect_spec;
      end if;

      if v_tech_award is null then
        if v_effect ? 'spirit_gain_fixed' then
          v_applied:=jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',greatest(0,public.opportunity_v4_adjust_spirit_stones(c.id,(v_effect->>'spirit_gain_fixed')::bigint)),'spirit_loss',0,'speed_bonus',0,'duration_minutes',0);
        else
          v_applied:=public.opportunity_v4_prepare_effect(c.id,gen_random_uuid(),v_grade,v_path,v_effect,v_event_at);
        end if;
      end if;
      insert into public.opportunity_v3_results(character_id,catalog_code,rarity,path_key,reward_text,penalty_text,result_data,settlement_batch_id,scheduled_at)
      values(c.id,null,v_grade,v_path,case when v_path='auspicious' then v_result.narrative else '' end,case when v_path='risk' then v_result.narrative else null end,
        jsonb_build_object('v','opportunity_v4','story_code',v_story.code,'result_code',v_result.code,'title',v_result.title,'story',v_story.story,'applied',v_applied,'effect_spec',v_effect,'technique',v_tech_award),v_batch,v_event_at)
      returning id into v_result_id;
      update public.character_cultivation_effects set source_key='opportunity_v4:'||v_result_id::text,metadata=jsonb_set(metadata,'{result_id}',to_jsonb(v_result_id),true) where character_id=c.id and source_type='opportunity_v4' and starts_at=v_event_at and source_key like 'opportunity_v4:%' and metadata->>'grade'=v_grade;
      v_cgain_req:=v_cgain_req+coalesce((v_applied->>'cultivation_gain_requested')::bigint,0);v_closs_req:=v_closs_req+coalesce((v_applied->>'cultivation_loss_requested')::bigint,0);v_sgain:=v_sgain+coalesce((v_applied->>'spirit_gain')::bigint,0);v_sloss:=v_sloss+coalesce((v_applied->>'spirit_loss')::bigint,0);
      v_latest:=jsonb_build_object('result_id',v_result_id,'title',v_result.title,'content',v_story.story,'result_text',v_result.narrative,'rarity',v_grade,'rarity_name',v_grade,'path_name',case when v_path='auspicious' then '趋吉' else '涉险' end,'applied',v_applied,'created_at',v_event_at);
      if v_grade in('天品','仙品','专属') then
        insert into public.history_logs(world_id,world_year,scope_type,scope_id,event_type,title,content,importance,visibility,metadata)
        values(c.world_id,greatest(1,c.birth_year+c.age),'character',c.id,'opportunity','机缘·'||v_result.title,v_story.story||'【'||case when v_path='auspicious' then '趋吉所得' else '涉险结果' end||'】'||v_result.narrative,
          case v_grade when '专属' then 5 when '仙品' then 5 else 4 end,'owner',jsonb_build_object('v','opportunity_v4','result_id',v_result_id,'batch_id',v_batch,'scheduled_at',v_event_at,'applied',v_applied));
      end if;
    end loop;
  end if;

  if v_due>0 then
    update public.character_opportunity_v3_state set next_available_at=case when v_capped>0 then nowv+interval '5 minutes' else st.next_available_at+make_interval(secs=>300*v_due) end,last_seen_at=nowv,total_resolved=total_resolved+v_due,last_result=v_latest,updated_at=nowv where character_id=c.id;
  else update public.character_opportunity_v3_state set last_seen_at=nowv,updated_at=nowv where character_id=c.id;end if;

  if p_settle_cultivation then select to_jsonb(x) into v_claim from public.claim_cultivation_v1() x;end if;
  select pc.cultivation,coalesce(rs.cultivation_required,0) into v_before,v_floor from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id where pc.id=c.id for update;
  v_actual_loss:=least(v_closs_req,greatest(0,v_before-v_floor));if v_actual_loss>0 then update public.player_characters set cultivation=cultivation-v_actual_loss,updated_at=now() where id=c.id;end if;
  if v_cgain_req>0 then select * into v_grant from public.grant_cultivation_capped_v1(c.id,v_cgain_req,'opportunity_v4',jsonb_build_object('batch_id',v_batch));v_actual_gain:=coalesce(v_grant.granted_amount,0);end if;
  v_remaining:=public.opportunity_v4_remaining_effects(c.id,nowv);
  if v_due>0 then
    insert into public.opportunity_v4_settlement_batches(id,character_id,period_started_at,period_ended_at,event_count,is_offline,capped_event_count,grade_counts,polarity_counts,gains,losses,net_result,remaining_effects,cultivation_claim,shown_at)
    values(v_batch,c.id,v_period_start,nowv,v_due,v_offline,v_capped,v_grade_counts,v_path_counts,
      jsonb_build_object('cultivation_direct',v_actual_gain,'spirit_stones',v_sgain,'items',v_items_gain,'techniques_new',v_tech_new,'techniques_duplicate',v_tech_dup,'mastery_points',v_mastery,'permanent_effects',v_permanent),
      jsonb_build_object('cultivation_direct',v_actual_loss,'spirit_stones',v_sloss,'items','{}'::jsonb),
      jsonb_build_object('cultivation',coalesce((v_claim->>'gained')::bigint,0)+v_actual_gain-v_actual_loss,'spirit_stones',v_sgain-v_sloss,'items',v_items_gain,'effects',v_remaining,'techniques_new',v_tech_new,'techniques_duplicate',v_tech_dup,'mastery_points',v_mastery,'permanent_effects',v_permanent),
      v_remaining,v_claim,case when v_offline then null else nowv end);
  end if;
  select to_jsonb(b) into v_summary from public.opportunity_v4_settlement_batches b where b.character_id=c.id and b.shown_at is null order by b.created_at desc limit 1;
  select * into st from public.character_opportunity_v3_state where character_id=c.id;
  if v_claim is not null then
    v_claim:=jsonb_set(v_claim,'{gained}',to_jsonb(coalesce((v_claim->>'gained')::bigint,0)+v_actual_gain-v_actual_loss),true);
    v_claim:=jsonb_set(v_claim,'{cultivation_total}',(select to_jsonb(cultivation) from public.player_characters where id=c.id),true);
  end if;
  return jsonb_build_object(
    'opportunity',jsonb_build_object('status','waiting','automatic',true,'next_available_at',st.next_available_at,'seconds_until_next',greatest(0,extract(epoch from(st.next_available_at-nowv))::int),'last_result',st.last_result,'auspicious_probability',v_ausp,'risk_probability',100-v_ausp,'lucky_auspicious_bonus',case when v_lucky then 5 else 0 end,'online_interval_seconds',300,'offline_interval_seconds',300,'offline_catchup_limit',864),
    'cultivation',v_claim,'offline_summary',v_summary,'events_resolved',v_due,'capped_events',v_capped
  );
end$$;

-- 兼容旧入口：旧客户端仍可得到机缘状态，但推荐新前端使用settle_opportunity_v4。
create or replace function public.get_auto_opportunity_v3() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$declare v jsonb;begin v:=public.settle_opportunity_v4(false);return v->'opportunity';end$$;

create or replace function public.ack_opportunity_v4_summary(p_batch_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$declare u uuid:=auth.uid();v_count integer;begin
  if u is null then raise exception 'AUTH_REQUIRED';end if;
  update public.opportunity_v4_settlement_batches b set shown_at=coalesce(shown_at,now())
  from public.player_characters pc where b.id=p_batch_id and b.character_id=pc.id and pc.user_id=u;
  get diagnostics v_count=row_count;return jsonb_build_object('success',v_count=1,'batch_id',p_batch_id);
end$$;

revoke all on function public.opportunity_v4_award_ordinary_technique(uuid,uuid,integer,text,timestamptz) from public,anon,authenticated;
revoke all on function public.opportunity_v4_stage_basis(uuid) from public,anon,authenticated;
revoke all on function public.opportunity_v4_adjust_spirit_stones(uuid,bigint) from public,anon,authenticated;
revoke all on function public.opportunity_v4_prepare_effect(uuid,uuid,text,text,jsonb,timestamptz) from public,anon,authenticated;
revoke all on function public.opportunity_v4_remaining_effects(uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.settle_opportunity_v4(boolean) from public,anon;
grant execute on function public.settle_opportunity_v4(boolean) to authenticated;
revoke all on function public.get_auto_opportunity_v3() from public,anon;
grant execute on function public.get_auto_opportunity_v3() to authenticated;
revoke all on function public.ack_opportunity_v4_summary(uuid) from public,anon;
grant execute on function public.ack_opportunity_v4_summary(uuid) to authenticated;

-- A线安全加固：V4内容池与私人离线结算批次禁止客户端直接访问。
alter table public.opportunity_v4_story_pool enable row level security;
alter table public.opportunity_v4_result_pool enable row level security;
alter table public.opportunity_v4_settlement_batches enable row level security;
alter table public.opportunity_v4_technique_drop_rates enable row level security;
alter table public.opportunity_v4_technique_pool enable row level security;
revoke all on table public.opportunity_v4_story_pool from public,anon,authenticated;
revoke all on table public.opportunity_v4_result_pool from public,anon,authenticated;
revoke all on table public.opportunity_v4_settlement_batches from public,anon,authenticated;
revoke all on table public.opportunity_v4_technique_drop_rates from public,anon,authenticated;
revoke all on table public.opportunity_v4_technique_pool from public,anon,authenticated;

comment on table public.opportunity_v4_story_pool is 'V0.14.5：机缘V4触发文案池，仅由安全定义函数读取。';
comment on table public.opportunity_v4_result_pool is 'V0.14.5：机缘V4结果池，仅由安全定义函数读取。';
comment on table public.opportunity_v4_settlement_batches is 'V0.14.5：玩家离线机缘净汇总批次，禁止客户端直接读写。';
comment on table public.opportunity_v4_technique_pool is 'V0.14.5：普通机缘功法掉落池。';

commit;
