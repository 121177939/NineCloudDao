# GitHub Desktop 更新到 V0.11.9

1. 备份当前仓库。
2. 在Supabase执行 `database/V0.11.9/202607260300_v0119_heaven_balance_full_multiplier.sql`。
3. 执行 `database/V0.11.9/202607260300_v0119_check.sql`，确认全部PASS。
4. 用V0.11.9 GitHub上传包覆盖仓库根目录。
5. 提交：`Upgrade to V0.11.9 heaven balance`。
6. Push origin并等待Actions变绿。
7. 手机清理PWA缓存后访问 `?v=0119`。
