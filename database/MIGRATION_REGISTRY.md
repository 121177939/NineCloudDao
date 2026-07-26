# 数据库迁移登记

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
