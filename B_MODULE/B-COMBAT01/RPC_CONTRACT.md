# B-COMBAT01 RPC契约

## `get_battle_power_ranking_bcombat01(p_limit, p_offset)`

返回战力榜分页、本尊战斗快照与榜单规则。单项包含四属性、五行、境界、命格、战力、是否本人及是否满足“目标战力更高”。只读。

## `get_battle_challenge_preview_bcombat01(p_target_character_id)`

返回双方当前快照、双方潜在1%修为损失、每日次数、同对手次数、保护截止时间、能否开始与阻止原因。只读；真实开战时仍会再次验证。

## `challenge_battle_power_bcombat01(p_target_character_id, p_request_id)`

服务端权威挑战入口。执行资格核验、角色锁定、战斗模拟、修为转移、硬上限暂存、挑战审计与九霄界闻发布。返回双方快照、完整行动数组、胜负、剩余生机、转移修为、暂存修为、保护时间及本尊结算后修为。

`p_request_id` 为客户端生成的UUID。重复请求返回原结果，不重复扣发。

## `claim_battle_cultivation_escrow_bcombat01()`

将战利修为暂存中、当前境界硬上限允许容纳的部分转入当前角色。不会突破硬上限。A线应接入突破成功后或登录结算链。

## 内部函数

- `bcombat01_assign_element(uuid)`：均衡随机分配五行。
- `bcombat01_character_snapshot(uuid)`：生成服务端战斗快照与常驻战力。
- `bcombat01_element_multiplier(...)`：五行倍率。
- `bcombat01_resolve_hit(...)`：单次伤害与战报事件。

内部函数均未授权给客户端直接调用。
