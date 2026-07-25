# GitHub Desktop 更新到 V0.11.7-fix1

1. 备份当前数据库和仓库。
2. 在Supabase执行 `database/V0.11.7/202607260200_v0117_fix1_full_heaven_multiplier.sql`。
3. 执行 `database/V0.11.7/202607260200_v0117_fix1_check.sql`，确认全部PASS。
4. 解压GitHub上传包，覆盖仓库根目录。
5. 提交：`Fix V0.11.7 heaven multiplier and restore UI`。
6. Push origin，等待Actions变绿。
7. 手机清理PWA缓存后用 `?v=0117fix1` 访问。
