# GitHub Desktop 更新到 V0.11.10-fix1

1. 暂时不要执行旧V0.11.10 SQL，也不要先上传前端。
2. 运行只读预检查`database/V0.11.10_FIX1/202607260530_v01110_fix1_precheck.sql`。
3. 确认核心ID均为`smallint`后，执行FIX1主SQL。
4. 执行FIX1检查SQL，确认22项全部`PASS`。
5. 用GitHub上传包覆盖仓库根目录并提交：`Fix V0.11.10 breakthrough migration`。
6. Push后清除PWA缓存，访问`?v=01110fix1`。
