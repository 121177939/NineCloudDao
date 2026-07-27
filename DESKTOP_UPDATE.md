# V0.14.1 FIX5 CACHE2更新说明

1. 先在Supabase执行`database/V0.14.1/202607270100_v0141_fix5_breakthrough_insight_route.sql`，末尾8项检查均应为`true`。
2. 再覆盖GitHub仓库并部署本包。
3. 已部署CACHE1的客户端会收到新的`cache_epoch`并自动刷新。
4. 不要重跑V0.13.0、V0.14.1主迁移、FIX2、FIX3或FIX4。

---

# V0.14.1 FIX4 CACHE1 覆盖升级

1. 使用本包覆盖GitHub仓库并推送。
2. GitHub Pages部署完成后，执行一次CACHE1发布控制SQL。
3. 旧页面首次收到新Service Worker后会自动刷新一次。
4. 玩法数据库仍为V0.14.1 FIX4，不要重跑主迁移、FIX2、FIX3或FIX4。
5. 以后发布新前端时，同时修改`buildId`和资源查询参数，并将`cache_epoch`加1。

本热修复不改变任何游戏玩法或玩家资产。
