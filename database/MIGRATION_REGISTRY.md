## V1.2 CACHE37

- `database/V1.1_FIX1/202607300950_v1_1_fix1_secure_rng_compat.sql`：补齐64号安全随机兼容修复。
- `database/V1.2/202607301300_v1_2_precheck.sql`：V1.2升级前检查。
- `database/V1.2/202607301310_v1_2_mutation_roots_sword_heart_mutex.sql`：雷风冰变异灵根、剑心互斥、冲突随机替换、战斗8%与UI数据契约。
- `database/V1.2/202607301320_v1_2_cache37_release.sql`：CACHE37发布门禁。
- `database/V1.2/202607301330_v1_2_check.sql`：升级后检查。
- `database/V1.2/202607301340_v1_2_emergency_disable_mutation.sql`：紧急停用变异伤害加成。
- `database/V1.2/202607301350_v1_2_resume_mutation.sql`：恢复变异伤害加成。

## V1.1 FIX1 CACHE36
- `database/V1.1_FIX1/202607300850_v1_1_fix1_precheck.sql`：V1.1 CACHE35前置检查与未结算注单门禁。
- `database/V1.1_FIX1/202607300900_v1_1_fix1_casino_period_bankroll.sql`：两小时赌场资金、公开赔率、30%单局上限、玩家庄2.5%平台费和70%奖池。
- `database/V1.1_FIX1/202607300910_v1_1_fix1_cache36_release.sql`：CACHE36发布门禁。
- `database/V1.1_FIX1/202607300920_v1_1_fix1_check.sql`：只读最终检查。
- `database/V1.1_FIX1/202607300930_v1_1_fix1_emergency_disable.sql`：紧急停用赌坊。
- `database/V1.1_FIX1/202607300940_v1_1_fix1_resume.sql`：恢复启用赌坊。

# 数据库迁移登记

## V0.14.9

- 无新增数据库迁移。
- 继续沿用`database/V0.14.8/202607281630_v0148_fish_shrimp_mobile_casino.sql`。
- 若V0.14.8已经执行，不得为V0.14.9重复执行。

## V0.14.1 FIX4 CACHE1

- 文件：`database/V0.14.1/202607262230_v0141_fix4_cache1_release_control.sql`
- 状态：缓存发布控制热修复；只需执行一次。
- 新增`jiuxiao_app_release_control`单例表及`get_jiuxiao_app_release_control_v1()`匿名只读RPC。
- 不修改玩家资产、赌坊、灵石、修为或世界事件结算。
- 以后每次新前端发布后只增加`cache_epoch`，CACHE1及后续客户端会自动清缓存重载。


- V0.11.0：`202607240018_sect_system.sql`（线上既有，禁止重跑）
- V0.11.1：无数据库迁移
- **永久废弃：`202607240019_auto_opportunity_v2.sql`，严禁部署**
- V0.11.2 FINAL：`database/V0.11.2/202607250020_auto_opportunity_v3.sql`（只执行一次）
- V0.11.3：前端运行时修复，无数据库迁移
- V0.11.4：机缘轮界面修复，无数据库迁移
- V0.11.5 FINAL：`database/V0.11.5/202607252030_v0115_full_activation.sql`（在V0.11.2迁移成功后执行一次）

## V0.11.5 配套文件

- 检查：`202607252030_v0115_full_check.sql`
- 紧急停用：`202607252030_v0115_emergency_disable.sql`
- 恢复：`202607252030_v0115_resume.sql`
- 结构回滚：`202607252030_v0115_rollback.sql`

早期草稿 `202607251900_v0115_exclusive_fix.sql` 已由最终主SQL取代，不得混用。

## V0.11.6

- `database/V0.11.6/202607252300_v0116_opportunity_polarity.sql`：趋吉/涉险正负互斥、50/50基准、机缘深厚趋吉+5个百分点。
- `database/V0.11.6/202607252300_v0116_check.sql`：升级后概率与互斥规则检查。
- `database/V0.11.6/202607252300_v0116_emergency_disable.sql`：紧急停用自动机缘。
- `database/V0.11.6/202607252300_v0116_resume.sql`：恢复自动机缘。
- `database/V0.11.6/202607252300_v0116_rollback.sql`：恢复V0.11.5机缘函数，不删除历史数据。

## V0.11.7

- `database/V0.11.7/202607260030_v0117_heaven_balance.sql`：天道福泽、大道均衡、天道阻滞；按全服主流大境界动态计算灵气环境系数。
- `database/V0.11.7/202607260030_v0117_check.sql`：9档系数、RPC、自动修炼加法结算和数据库基线检查。
- `database/V0.11.7/202607260030_v0117_emergency_disable.sql`：临时将全部天道系数固定为×1，不删除数据。
- `database/V0.11.7/202607260030_v0117_resume.sql`：恢复V0.11.7九档天道系数。
- `database/V0.11.7/202607260030_v0117_rollback.sql`：恢复V0.11.6之前的灵气环境整体乘算规则，并删除V0.11.7新增RPC。


## V0.11.7 FIX1

- `database/V0.11.7/202607260200_v0117_fix1_full_heaven_multiplier.sql`：修复天道系数仅影响微小灵气基础值的问题，改为作用于完整自动修炼速度。
- `database/V0.11.7/202607260200_v0117_fix1_check.sql`：检查×5、×1、×0.5及完整乘算公式。
- `database/V0.11.7/202607260200_v0117_fix1_emergency_disable.sql`：临时固定为大道均衡×1。
- `database/V0.11.7/202607260200_v0117_fix1_resume.sql`：恢复九档动态系数。
- `database/V0.11.7/202607260200_v0117_fix1_rollback.sql`：仅在紧急情况下恢复V0.11.7主版本的加法算法。

执行顺序：先完成V0.11.7主迁移，再执行FIX1；不要重复执行V0.11.7主迁移。

## V0.11.9

- `database/V0.11.9/202607260300_v0119_heaven_balance_full_multiplier.sql`：天道动态均衡正式整合，完整自动修炼倍率。
- `database/V0.11.9/202607260300_v0119_check.sql`：12项核心检查。
- `database/V0.11.9/202607260300_v0119_emergency_disable.sql`：紧急固定大道均衡x1。
- `database/V0.11.9/202607260300_v0119_resume.sql`：恢复九档动态系数。
- `database/V0.11.9/202607260300_v0119_rollback.sql`：回滚到V0.11.7初版加法结算。

## V0.11.10

- `database/V0.11.10/202607260500_v01110_roots_realms_breakthrough.sql`：灵根修炼/战斗双系数、境界基础吐纳、渡劫失败结果、名字旁状态与目标绑定失败补偿。
- `database/V0.11.10/202607260500_v01110_check.sql`：16项部署检查。
- `database/V0.11.10/202607260500_v01110_emergency_safe_breakthrough.sql`：紧急将境界基础突破率临时设为100%。
- `database/V0.11.10/202607260500_v01110_resume.sql`：从备份恢复境界基础突破率；之后需重跑主SQL恢复正式函数。
- `database/V0.11.10/202607260500_v01110_rollback.sql`：从非public备份架构恢复升级前灵根值与三个关键RPC，并删除V0.11.10新增结构。

执行顺序：V0.11.9已完成 → V0.11.10主SQL → V0.11.10检查SQL → 上传前端。

## V0.11.10 FIX1

- `database/V0.11.10_FIX1/202607260530_v01110_fix1_precheck.sql`：只读类型预检查。
- `database/V0.11.10_FIX1/202607260530_v01110_fix1_roots_realms_breakthrough.sql`：smallint类型修复、元婴保护、单次大跌境锁。
- `database/V0.11.10_FIX1/202607260530_v01110_fix1_check.sql`：22项检查。

旧V0.11.10主SQL存在UUID/smallint类型错误，已从本修复包移除，不得执行。

## V0.12.0 FIX1

- `database/V0.12.0/202607260830_v0120_fix1_precheck.sql`：只读检查V0.11.10 FIX1/FIX2基础结构。
- `database/V0.12.0/202607260830_v0120_fix1_market_casino.sql`：万运博弈楼完整安全修正版。
- `database/V0.12.0/202607260830_v0120_fix1_check.sql`：27项结构、权限、赔率结算和修为保护检查。
- `database/V0.12.0/202607260830_v0120_fix1_emergency_disable.sql`：暂停创建新对局，保留已有结算与返还。
- `database/V0.12.0/202607260830_v0120_fix1_resume.sql`：恢复创建新对局。
- `database/V0.12.0/202607260830_v0120_fix1_rollback.sql`：先返还未结算赌注，再移除赌场结构。

V0.12.0初稿 `202607260800_v0120_market_casino.sql` 存在严重权限与规则缺口，标记为废弃，严禁部署。若已部署，直接执行FIX1主SQL覆盖修复，不要重复执行初稿。


## V0.13.0

- 基线：V0.12.0 FIX1 + Deploy Hotfix；数据库V0.11.10 FIX1/FIX2 + V0.12.0 FIX1。
- `database/V0.13.0/202607261300_v0130_precheck.sql`：只读前置检查。
- `database/V0.13.0/202607261300_v0130_breakthrough_cultivation_cap.sql`：天劫感悟、失败概率、修为硬上限、旧数据截断及赌场限制。
- `database/V0.13.0/202607261300_v0130_check.sql`：31项部署检查。
- `database/V0.13.0/202607261300_v0130_data_audit.sql`：超额修为截断审计。
- `database/V0.13.0/202607261300_v0130_emergency_disable.sql`：关闭新突破但保留修为上限。
- `database/V0.13.0/202607261300_v0130_resume.sql`：恢复。
- `database/V0.13.0/202607261300_v0130_rollback.sql`：恢复基线函数；无法恢复已截断数值，数据恢复必须使用部署前备份。
- **永久废弃：所有旧V0.12.0 FIX3突破补丁，严禁部署。**


## V0.13.1

- 类型：纯发布流水线热修复。
- 数据库变更：无。
- SQL：无。
- 禁止将V0.13.1理解为需要重跑V0.13.0迁移。
- GitHub Actions #28失败事故已记录于 `docs/V0.13.1_DEPLOYMENT_HOTFIX.md`。

## V0.14.0

- 基线：V0.13.1前端 + 已部署V0.13.0数据库。
- `database/V0.14.0/202607261430_v0140_precheck.sql`：只读前置检查。
- `database/V0.14.0/202607261430_v0140_bazaar_world_events.sql`：市坊总入口配套的九霄界闻表、RPC与触发器。
- `database/V0.14.0/202607261430_v0140_check.sql`：权限、触发器、RLS与启用公告检查。
- `database/V0.14.0/202607261430_v0140_data_audit.sql`：重复来源、空文案和事件分布审计。
- `database/V0.14.0/202607261430_v0140_emergency_disable.sql`：停止新播报，不影响核心玩法。
- `database/V0.14.0/202607261430_v0140_resume.sql`：恢复播报。
- `database/V0.14.0/202607261430_v0140_rollback.sql`：删除触发器与RPC，保留历史表供审计。
- 正式规则：赌坊大堂每一局已结算胜负均播报；退款、取消、等待和失败事务不播报。
- 执行顺序：备份 → precheck → 主迁移 → check → data audit。主迁移成功后不要重跑。

## V0.14.0 FIX2 / FIX3（当前权威历史基线）

- V0.14.0原始主迁移会与既有`world_events`表冲突，且FIX1存在函数实参类型推断错误，均不得再部署。
- `database/V0.14.0_FIX2/九霄问道_V0.14.0_FIX2_主迁移.sql`：使用独立`jiuxiao_world_events`表的正式界闻迁移。
- `database/V0.14.0_FIX3/九霄问道_V0.14.0_FIX3_账号删除自动播报.sql`：Supabase Auth直接删号自动生成“名籍除却”播报。
- V0.14.1以FIX2为强制数据库前提，FIX3建议已部署。

## V0.14.1

- `database/V0.14.1/202607261700_v0141_spirit_stone_casino.sql`：唯一灵石账户、历史绑定/非绑定余额合并、机缘/洞府/赌坊/功法统一读写、赌坊不限次、分层入口、全服双造化池、每人每期一份资格、40%命中与60%滚存。
- 执行前提：V0.13.0和V0.14.0 FIX2已成功部署。
- 执行方式：备份后完整执行一次；脚本末尾自检结果应全部为`true`。

## V0.14.1 FIX2

- `database/V0.14.1/202607261930_v0141_fix2_loss_pool_rate.sql`：修复赌坊败局损失全额进入造化池的问题。
- 新规则：仅实际败局损失的5%进入对应全服造化池，余下95%由天道回收；赢局、退款、取消、超时返还和同招流局不入池。
- 贵宾雅间只按败者的一笔实际损失计算分流；胜者奖励规则、每期等权资格、40%命中与60%滚存保持不变。
- 执行前提：V0.14.1主迁移已经成功部署。只需执行本FIX2一次，不要重跑V0.14.1主迁移。
## V0.14.1 FIX3

- `database/V0.14.1/202607262030_v0141_fix3_house_win_pool_rate.sql`：修复大堂胜局未向造化池注入5%赌注的问题。
- 大堂每一局成功结算的赌注均固定5%入池。1倍胜局押100时返还本金100、净赢95、总到账195，奖池增加5。
- 大堂败局继续为5%入池、95%天道回收；灵石和修为完全一致。
- 贵宾雅间保持FIX2规则不变：仅败者实际损失5%入池，同招流局、取消和退款不入池。
- 执行前提：V0.14.1主迁移与FIX2已成功部署。只执行FIX3一次，不要重跑前序迁移。


## V0.14.1 FIX4

- `database/V0.14.1/202607262130_v0141_fix4_duel_pool_payout.sql`：修复贵宾雅间胜者奖励与5%入池同时计算导致的资产超发。
- 新规则：双方各押100时，胜者取回自身本金100，并获得败者赌注中的95，总到账195；败者损失100；奖池增加5；雅间天道回收为0。
- 灵石与修为完全一致；同招流局、取消和超时返还不入池。
- 执行前提：V0.14.1主迁移、FIX2与FIX3已成功部署。只执行FIX4一次。


## V0.14.1 FIX5

- `database/V0.14.1/202607270100_v0141_fix5_breakthrough_insight_route.sql`：修复跌落境界后天劫感悟仅在直接冲击原始目标时才参与成功率计算的问题。
- 新规则：只要原始目标尚未抵达，全部累计感悟都会对恢复路线上的当前下一境突破生效；每丝固定增加5个百分点，最终不超过80%。
- 成功抵达原始目标后，感悟仍按既有规则清零。
- 本迁移不修改已有境界、修为或感悟数量。执行前提为V0.13.0突破系统已部署；当前项目还应已完成V0.14.1主迁移及FIX2—FIX4。


## V0.14.1 FIX6

- `database/V0.14.1/202607270230_v0141_fix6_spirit_dice_triple_auto_side.sql`：修复灵骰豹子被“大/小”通杀且需要单独押围骰的规则。
- 新规则：玩家只押大或小；3—10点为小，11—18点为大；豹子按总点数自动归类。
- 111/222/333归小，444/555/666归大；豹子命中对应大小时净赔率34倍，普通命中净赔率1倍。
- 大堂每局5%入池规则继承FIX3，不修改贵宾雅间、造化池或突破逻辑。
- 执行前提：V0.14.1主迁移、FIX2、FIX3、FIX4已成功部署。只执行FIX6一次。


## V0.14.1 FIX7

- `database/V0.14.1/202607270430_v0141_fix7_destiny_triple_expected_value.sql`：修复FIX6免费豹子34倍导致长期固定押一边稳定盈利。
- 普通结果和普通豹子押中均为净赔率1倍；对应豹子后以9/275判定天命豹子，天命豹子净赔率34倍。
- 固定押一边时天命豹子触发概率恰为1/2200；押100长期期望为-1，赌场优势约1%。
- 天命豹子会生成独立九霄界闻播报。
- 执行前提：V0.14.1主迁移、FIX2、FIX3、FIX4、FIX6已成功部署。只执行FIX7一次。

## V0.14.1 FIX7A

- `database/V0.14.1/202607270730_v0141_fix7a_fair_dice_pool_split.sql`：从FIX7直接升级；大小各50%，普通豹子1/80且毛利润3倍，天命豹子1/5000且毛利润34倍；赢利5%入池，败局10%入池、90%天道回收。

## V0.14.2

- `database/V0.14.2/202607270900_v0142_world_feed_strict_newest.sql`：九霄界闻严格新消息排序。
- 新增`feed_sequence`单调序号，任何新消息均顶掉旧消息；`is_pinned`不再参与排序。
- RPC默认返回30条，前端每10秒刷新并执行防御性倒序。
- 本版不修改突破、赌坊、造化池、命格或角色资源。
- 执行前提：V0.14.1 FIX7A已经部署。FIX8不在有效链内，严禁执行。

## V0.14.3

- `database/V0.14.3/202607271720_v0143_multi_ranking_wealth.sql`：天命榜三榜切换配套财富榜只读RPC与CACHE7发布控制。
- 修为榜继续调用既有`get_destiny_ranking_v1`，排序规则不变。
- 财富榜新增`get_wealth_ranking_v1(integer,integer)`，按唯一统一灵石余额倒序，同额时按大境界、小境界、修为、创建时间与角色ID稳定排序。
- 战力榜仅为前端占位，本版不新增战力字段、表或RPC。
- 本迁移不修改角色资产、修为、命格、突破、赌坊、造化池或九霄界闻数据。
- 执行前提：V0.14.1统一灵石体系和V0.14.2九霄界闻迁移均已部署。只执行本SQL一次。

## V0.14.4 CACHE8

- 正式迁移：`database/V0.14.4/202607272200_v0144_player_house_casino_notice_insight.sql`
- 合并玩家自愿坐庄、修为小境界保底、赌契即时结算、天劫感悟总修炼速度与私人天谕。
- 管理后台配套：`V0.14.4 ADMIN2`，必须在游戏V0.14.4迁移后执行。
- 不执行V0.14.1 FIX8；不改变V0.14.2界闻严格排序与V0.14.3财富榜排序。
## V0.14.5 · 机缘V4、功法扩充与玩家庄5%佣金
- 正式脚本：`database/V0.14.5/202607272330_v0145_opportunity_v4_techniques_player_house_commission.sql`。
- 前置：V0.14.4综合升级已部署。
- 机缘在线/离线统一5分钟，离线最多72小时/864次。
- 原12主修保留，新增12辅修；离线净汇总。
- 玩家庄赢家毛利润5%由当局庄家保留；系统庄FIX7A不变。
- 新增V4表启用RLS并撤销客户端直连权限。
- 部署状态：交付就绪，生产执行待用户确认。

## V0.14.6 CACHE10
- `database/V0.14.6/202607280230_v0146_opportunity_history_detail.sql`
- 修复机缘V4效果来源约束、结算批次外键、离线命书明细和具体结果展示。

## V0.14.7 CACHE11
- `database/V0.14.7/202607280600_v0147_library_opportunity_inventory_house.sql`
- 功法书藏经架、机缘明细、物品批量使用、双庄切换、2小时任期与玩家庄系统兜底。

## V0.14.8 CACHE12
- `database/V0.14.8/202607281630_v0148_fish_shrimp_mobile_casino.sql`
- 新增鱼虾灵局60秒公共轮次、服务端押注/结算及客户端CACHE12。

## V0.15.0 CACHE16
- `database/V0.15.0/202607281910_v0150_fish_continuous_bet_world_feed_exclusion.sql`
- 前端新增鱼虾灵局连续点击队列：法印不再因单次请求显示“落注中”并锁定，快速点击短窗合并后顺序提交。
- 数据库仅重定义既有赌坊界闻触发函数，在入口显式排除 `game_code='fish_shrimp'`；鱼虾灵局下注和结算不进入九霄界闻。
- 灵骰问道、气运龟卜、天命豹子、造化池及其他界闻规则保持不变。
- 发布控制提升为 `V0.15.0 CACHE16`。

## V0.15.1 CACHE17
- `database/V0.15.1/202607282010_v0151_casino_world_feed_dealer_and_fish_40s.sql`
- 赌坊大堂界闻显示荷老或具体玩家庄姓名及净赢净输。
- 鱼虾灵局结算恢复发布九霄界闻。
- 鱼虾灵局完整单局改为40秒。
- 发布控制提升为 `V0.15.1 CACHE17`。

## V0.15.1 CACHE18 节奏修正

- `database/V0.15.1/202607282040_v0151_fix1_fish_30_2_5_3.sql`
- `database/V0.15.1/202607282050_v0151_fix1_check.sql`
- `database/V0.15.1/202607282060_v0151_fix1_rollback.sql`
- 鱼虾灵局40秒节奏修正为30秒下注、2秒封盘、5秒开骰、3秒结算展示。
- 九霄界闻庄家与净输赢播报保持启用。
- 发布控制提升为 `V0.15.1 CACHE18`。
## V0.15.5 CACHE26
- 文件：`database/V0.15.5/202607291340_v0155_cache26_cave_yuanshen_release.sql`
- 仅提升 `jiuxiao_app_release_control.cache_epoch` 到26，触发客户端更新。
- 不新增战斗属性表、字段、函数或RPC。
## V0.15.5 FIX1 CACHE27

- 文件：`database/V0.15.5_FIX1/202607291500_v0155_fix1_precheck.sql`（只读前置检查）。
- 文件：`database/V0.15.5_FIX1/202607291510_v0155_fix1_cache27_cave_visual_release.sql`（仅更新客户端发布门禁至 CACHE27）。
- 文件：`database/V0.15.5_FIX1/202607291520_v0155_fix1_check.sql`（只读升级后检查）。
- 可从 V0.15.4 FIX5 CACHE25 直接升级，不要求先执行 CACHE26。
- 不新增表、字段、RPC、触发器或RLS；不修改玩家资产、洞府结算、突破或渡劫规则。



## V1.0 CACHE30
- `database/V1.0/202607291700_v1_precheck.sql`：只读升级前检查，可从 CACHE25 直接升级。
- `database/V1.0/202607291710_v1_bcombat01.sql`：B-COMBAT01 正式迁移。
- `database/V1.0/202607291720_v1_cache30_release.sql`：V1.0 CACHE30 发布门禁。
- `database/V1.0/202607291730_v1_check.sql`：只读升级后检查。
- `database/V1.0/202607291740_v1_emergency_disable.sql`：紧急停用挑战。
- `database/V1.0/202607291750_v1_rollback.sql`：完整回滚（破坏性）。


## V1.0 FIX1 CACHE31
- `database/V1.0_FIX1/202607291820_v1_fix1_precheck.sql`：已部署CACHE30的只读检查。
- `database/V1.0_FIX1/202607291830_v1_fix1_challenge_compat.sql`：挑战战报参数兼容重载。
- `database/V1.0_FIX1/202607291840_v1_fix1_cache31_release.sql`：CACHE31发布门禁。
- `database/V1.0_FIX1/202607291850_v1_fix1_check.sql`：升级后只读检查。

## V1.0 FIX2 CACHE32
- `database/V1.0_FIX2/202607291910_v1_fix2_precheck.sql`：CACHE31只读检查。
- `database/V1.0_FIX2/202607291920_v1_fix2_cache32_release.sql`：前端隐私与弹窗调整的CACHE32发布门禁。
- `database/V1.0_FIX2/202607291930_v1_fix2_check.sql`：升级后只读检查。

## V1.0 FIX3 CACHE33
- `database/V1.0_FIX3/202607292020_v1_fix3_precheck.sql`：CACHE32只读检查。
- `database/V1.0_FIX3/202607292030_v1_fix3_battle_story.sql`：挑战界闻趣味文案、历史战报重写与故障隔离触发器。
- `database/V1.0_FIX3/202607292040_v1_fix3_cache33_release.sql`：CACHE33发布门禁。
- `database/V1.0_FIX3/202607292050_v1_fix3_check.sql`：升级后只读检查。
- `database/V1.0_FIX3/202607292060_v1_fix3_rollback.sql`：停止后续界闻重写；历史正文不自动恢复。

## V1.1 CACHE35
- `database/V1.1/202607300230_v1_1_precheck.sql`：V1.0 FIX4 前置检查。
- `database/V1.1/202607300240_v1_1_battle_rules_world_event_fix.sql`：双向挑战、20次/20分钟、阶段修为转移与界闻错表修复。
- `database/V1.1/202607300250_v1_1_cache35_release.sql`：CACHE35发布门禁。
- `database/V1.1/202607300260_v1_1_check.sql`：只读最终检查。
- `database/V1.1/202607300270_v1_1_emergency_disable.sql`：紧急关闭战力挑战。
- `database/V1.1/202607300280_v1_1_resume.sql`：恢复战力挑战。

## V1.2 FIX1 CACHE38
- `database/V1.2_FIX1/202607301500_v1_2_fix1_precheck.sql`
- `database/V1.2_FIX1/202607301510_v1_2_fix1_paigow_main.sql`
- `database/V1.2_FIX1/202607301520_v1_2_fix1_cache38_release.sql`
- `database/V1.2_FIX1/202607301530_v1_2_fix1_check.sql`
- `database/V1.2_FIX1/202607301540_v1_2_fix1_emergency_disable_paigow.sql`
- `database/V1.2_FIX1/202607301550_v1_2_fix1_resume_paigow.sql`
- B-PAIGOW01正式并线；后续SQL从77号追加。


## V1.2 FIX2 CACHE39

- `202607301600_v1_2_fix2_cache39_paigow_ui_release.sql`：验证77/78并提升客户端发布门禁。
- `202607301610_v1_2_fix2_cache39_check.sql`：升级后只读检查。
- 前端按V26预览重制，不修改牌局概率与资金结算。

## V1.2 FIX3 CACHE40

- `202607301830_v1_2_fix3_cache40_paigow_stable_render_release.sql`：验证既有牌九RPC并发布无闪烁轮询、自定义底注客户端CACHE40。
- `202607301840_v1_2_fix3_cache40_check.sql`：升级后只读检查；不修改牌型、概率或资金规则。
