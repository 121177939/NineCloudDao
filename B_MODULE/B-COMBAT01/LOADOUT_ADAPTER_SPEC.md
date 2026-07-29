# 武器与法衣适配契约

## 当前事实

V0.15.5 FIX1 CACHE27中没有可直接作为权威穿戴来源的正式武器/衣服系统。B-COMBAT01不能伪造玩家装备，因此新增候选适配表：

`public.character_combat_loadouts_bcombat01`

## 字段

- `weapon_name`：当前武器名称；空值显示“赤手空拳”。
- `weapon_kind`：武器类型；剑类必须使用 `sword` 才能触发天生剑心。
- `weapon_attack`：武器基础道攻。
- `weapon_requirement_coefficient`：装备要求境界系数。
- `armor_name`：当前法衣/护甲名称；空值显示“赤裸”。
- `armor_defense`、`armor_vitality`、`armor_agility`：法衣属性。
- `armor_requirement_coefficient`：装备要求境界系数。
- `metadata`：未来装备ID、品质、图标等扩展信息。

## 生效公式

`有效装备属性 = 装备基础属性 × min(1, 使用者境界系数 / 装备要求境界系数)`

达到要求后最高100%，不会超额放大。

## 接入要求

正式装备模块接入时，穿戴/卸下必须在服务端同一事务中同步该表。不得授权客户端直接更新。若A线已有更权威的装备表，应改写 `bcombat01_character_snapshot` 的适配查询，而不是保留两套装备真相。
