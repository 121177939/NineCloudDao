# GitHub Desktop 更新到 V0.11.5

1. 先在 Supabase 备份数据库。
2. 执行 `database/V0.11.5/202607252030_v0115_full_activation.sql`。
3. 执行 `database/V0.11.5/202607252030_v0115_full_check.sql`，确认综合结果全部 PASS。
4. 解压 GitHub 上传包，将内层全部文件覆盖到仓库根目录。
5. GitHub Desktop 提交说明：`Upgrade to V0.11.5 FINAL and activate all opportunity features`。
6. Commit to main，然后 Push origin。
7. 等待 GitHub Actions 变绿。
8. 手机清理旧站点/PWA缓存后使用 `?v=0115` 重新进入。

不要执行废弃的 `202607240019_auto_opportunity_v2.sql`，也不要执行早期 V0.11.5 草稿 SQL。
