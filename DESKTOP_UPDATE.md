# GitHub Desktop更新到V0.14.1 FIX4

1. 先备份Supabase数据库和当前GitHub仓库。
2. 确认V0.14.1主迁移、FIX2与FIX3已经部署。
3. 只执行一次`九霄问道_V0.14.1_FIX4_雅间胜者结算热修复.sql`。
4. 确认脚本末尾所有自检项均为`true`。
5. 解压`NineCloudDao_GitHub_Upload_V0.14.1_FIX4.zip`并覆盖仓库根目录。
6. GitHub Desktop提交：`Fix VIP duel payout for V0.14.1 FIX4`。
7. 推送后确认版本验证、JavaScript检查、SQL静态审计、赌坊渲染模拟和Pages制品验证均为绿色。
8. 部署完成后刷新PWA缓存，确认雅间规则显示“双方各押100，胜者共到账195，奖池增加5”。

不要重跑V0.14.1主迁移、FIX2或FIX3。FIX4只覆盖贵宾雅间正常胜负结算与页面说明。
