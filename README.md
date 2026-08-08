# 九霄问道 V2.1.1 CACHE117

当前客户端基线：**V2.1.1 CACHE117**；Android：**versionCode 2001417 / versionName 2.1.1-cache117**；GM：**ADMIN9 R27**。

本轮装备修复：

- 装备主列表的 `location/is_locked` 以 `get_equipment_system_bequipment01` 返回值为权威，强化状态并行结果不得覆盖装备实际位置。
- 穿戴/卸下后的强制刷新若遇到并发旧刷新，会等待后再次真实拉取，避免“画面在背包、操作却提示仅背包可用”。
- 打开孔位/升品/破境以及提交操作前，CACHE117 通过 SQL247 的只读 RPC 再次确认数据库实时 `location/is_locked`。
- SQL247 修复造化升品玉、乾坤破境石成功分支读取不存在的 `ring_element_multiplier`：统一改用 `bequipment01_value(template_id, grade_code)` 权威装备数值链。
- SQL246规则继续保留：兵魄/护道对未锁孔同时随机属性+等级；百炼只随机未锁已有属性孔等级；整次无变化则事务回滚不扣材料/锁玉/灵石。
- 穿戴中的装备仍禁止淬炼、升品、破境；必须先卸下回背包。

数据库要求：**CACHE117 部署前必须确保 SQL245 R2、SQL246、SQL247 已安装且对应门禁通过。** SQL247成功后下一数据库编号为 **SQL248**。

GitHub Pages继续使用已验证的 **R3 default github-pages Artifact** 流程；Android继续使用已验证的 **Release R6** 构建、正式签名与在线更新链。不得因为本轮功能修复更换发布方式、包名或签名链。
