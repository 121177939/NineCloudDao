# 变更清单

## 数据库

新增：

- `public.character_technique_books`：角色功法书/专属道卷库存，按角色、类型、功法代码唯一堆叠。
- `public.get_technique_library_v1()`：读取洞府藏经架。
- `public.use_technique_book_v1(uuid)`：研习或参悟一本书。
- `public.technique_book_add_v1(...)`：内部安全入库。
- `public.technique_book_summary_add_v1(...)`：离线汇总聚合。
- `public.apply_technique_book_first_rewards_v1(...)`：首次研习时应用原附带奖励。

覆盖：

- `public.opportunity_v4_award_ordinary_technique(...)`
  - 原：直接写入 `character_techniques`，重复自动转传承点。
  - 新：只增加普通功法书×1。
- `public.settle_opportunity_v4(boolean)`
  - 普通功法分支改为道卷入库。
  - 专属本命/异命均入库。
  - 异命不再回收、不再发100灵石。
  - 离线汇总新增 `technique_books`。

## 前端

- 洞府增加“藏经架”区块。
- 显示名称、品级、主修/辅修/专属、数量、一级效果、首次研习奖励与命格契合状态。
- 普通未学显示“研习”；普通已学显示“参悟”。
- 本命专属未学显示“研习”；异命和已学专属为锁定留存状态。
- 离线汇总由“新获得/重复转化”改为“功法书所得×N”。
- 在线机缘生成书后刷新洞府藏经架。

## 不改动

- 现有已经学会的普通/专属功法数据。
- 现有装备槽、功法等级、熟练度、传承点。
- 24门普通功法定义与掉率。
- 5门专属定义及基础数值。
- 机缘修为/灵石/速度规则。
- FIX7A系统庄、玩家庄5%佣金、严格界闻、三榜和V0.14.6命书。
