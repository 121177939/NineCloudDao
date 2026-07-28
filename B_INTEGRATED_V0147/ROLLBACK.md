# 回滚与止损

## 紧急止损

执行 `database/90_emergency_disable.sql` 会暂停整个自动机缘系统，阻止继续生成机缘和道卷。已有道卷不会删除。

故障排除后执行 `database/91_resume.sql` 恢复。

## 完整回滚

1. 前端对两个补丁执行反向应用，或恢复V0.14.6_AB4的原始 `app.js`、`styles.css`。
2. 执行 `database/99_rollback.sql`。
3. 复跑V0.14.6原门禁。

回滚SQL会恢复：

- 普通功法即时学习、重复即时转传承点。
- 本命专属即时获得与装备。
- 异命专属回收并补偿100灵石。

`character_technique_books` 表和已获得道卷会保留为休眠数据，不会删除。这样后续重新接入时仍可恢复玩家道卷库存。
