# B-SECRETREALM01 CACHE59 接入审计

正式版本：V1.7.9 CACHE59 / SECRETCLAIM2-HISTORY5

- 场景资源：assets/secret-realm-portal.webp
- 领取RPC：claim_secret_realm_rewards_bsecretrealm01(uuid)
- 历史RPC：get_secret_realm_history_bsecretrealm01()
- 玩家历史：按需读取，仅返回当前角色最近5轮
- 历史内容：入场快照、结局、奖励、损失与完整分钟事件
- 领取门禁：pending_claim / SECRET_REALM_REWARDS_UNCLAIMED
- 奖励比例：reward_result_fraction=0.10（SQL131 R2开启）
- 怪物事件：境界、五行、类型、战力、四维
- 界闻结局：成功/妖兽败/玩家败各6套文案
- 战斗快照：沿用SQL128拆分JSON修复
