# GitHub Desktop 更新到 V0.11.6

1. 备份当前V0.11.5 GitHub仓库和Supabase数据库。
2. 在Supabase执行 `database/V0.11.6/202607252300_v0116_opportunity_polarity.sql`。
3. 执行 `database/V0.11.6/202607252300_v0116_check.sql`，确认所有检查为PASS。
4. 解压V0.11.6 GitHub上传包，将包内文件覆盖到仓库根目录。
5. GitHub Desktop提交说明：`Upgrade to V0.11.6 opportunity polarity`。
6. Commit to main，然后Push origin。
7. 等待GitHub Actions变绿。
8. 手机清理旧PWA缓存后使用 `?v=0116` 重新进入。

不要重新执行V0.11.2或V0.11.5主SQL；不要执行废弃的 `202607240019_auto_opportunity_v2.sql`。
