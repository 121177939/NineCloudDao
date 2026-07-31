# B-EQUIPMENT01正式接入审计

## 候选可采用部分

- 五部位和132模板目录完整；
- 黄玄地第一阶段数值、品级颜色、孔位预留和分解精粹规则明确；
- 装备实例与模板分离、30格背包、待领取及请求ID幂等方向正确；
- 客户端装备卡、洞府切换和详情交互可复用。

## A线修复后才并线的事项

1. `player_characters.status='alive'`改为正式状态集合`active/secluded/missing`。
2. 不再因候选猜测的`require_game_session_v1/assert_game_session_v1`缺失而封死全部RPC；已登录为硬要求，生产库若存在既有断言则兼容调用。
3. 战斗loadout的`metadata`改为合并，不覆盖其他模块字段。
4. 机缘30%装备分支真正合入当前正式`settle_opportunity_v4`，并确保与原奖励互斥。
5. 机缘详情、离线批次和历史结果正式携带装备摘要。
6. 戒指加成真正合入战斗快照与最终伤害，保持五行链、变异灵根和天生剑心规则不变。
7. 客户端移除全局`fetch`劫持、全DOM `MutationObserver`和20秒轮询，改为`jiuxiao:*`事件触发。
8. 修正装备机缘分支未初始化`record`字段就赋值的潜在运行时错误。

## 未宣称已完成

- 生产Supabase迁移；
- 真实账号机缘掉落、穿戴、并发幂等和战斗联调；
- 洞府装备权威容量；
- 词条、开孔、天品和仙品获取。

## V1.7.2补充

正式背包容量已由30格调整为36格，并统一使用6×6界面；洞府装备不再使用第二套常驻洞府格。

## V1.7.3补充：洞府版式稳定性

- 禁止把随身装备背包节点插入`caveSystemRoot`或`caveStorageB01`附近；原生洞府每次重绘会替换整个根节点，动态插入会造成界面在两种版式之间闪变。
- 随身装备背包固定从元神页独立入口打开6×6弹窗。
- 洞府只允许`renderCaveEquipmentIntoNative()`把`location='cave'`装备填入原生空格，不得创建第二套储物面板。
- 后续B候选不得恢复`equipmentStorageShellBEquipment01`、`cave.parentNode.insertBefore(...)`或背包/洞府双页签。

## V1.7.4补充：常驻背包与洞府资源去重

- 随身装备背包固定挂载在`primordialSpiritRootV1`内，使用`equipmentBackpackInlineBEquipment01`常驻显示。
- 禁止恢复`equipmentBackpackLauncherBEquipment01`、`data-equipment-backpack-modal`、打开按钮、关闭按钮或点击遮罩关闭逻辑。
- 元神面板重绘后，只允许通过`jiuxiao:primordial-rendered`重新挂载常驻背包。
- 点击空装备槽只能滚动定位到常驻背包。
- 洞府顶部资源卡只展示洞府专属资源；统一灵石不得在该资源条重复显示。
- 统一灵石的全局余额、洞府储物物品格与数据库资金逻辑保持不变。
