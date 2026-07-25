# GitHub Desktop 更新到 V0.11.7

1. 先备份Supabase数据库与当前GitHub仓库。
2. 在Supabase执行 `database/V0.11.7/202607260030_v0117_heaven_balance.sql`。
3. 执行 `database/V0.11.7/202607260030_v0117_check.sql`，确认全部为PASS。
4. 解压V0.11.7 GitHub上传包，将包内文件覆盖到仓库根目录。
5. GitHub Desktop提交说明：`Upgrade to V0.11.7 heaven balance`。
6. 点击 `Commit to main`，再点击 `Push origin`。
7. 等GitHub Actions变绿后，用 `?v=0117` 打开并清理旧PWA缓存。

检查SQL出现FAIL时，不要上传前端。
