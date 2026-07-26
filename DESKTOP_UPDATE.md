# GitHub Desktop更新到V0.14.1

1. 先备份Supabase数据库和当前GitHub仓库。
2. 在Supabase新建SQL窗口，完整执行`九霄问道_V0.14.1_升级SQL.sql`一次。
3. 确认脚本末尾所有自检项均为`true`。
4. 解压`NineCloudDao_GitHub_Upload_V0.14.1_FINAL.zip`并覆盖仓库根目录。
5. GitHub Desktop提交：`Update unified spirit stones and casino to V0.14.1`。
6. 推送后确认Actions的版本验证、JavaScript检查、SQL静态审计、赌坊渲染模拟和Pages制品验证均为绿色。
7. 部署完成后清理旧PWA缓存，确认页脚显示Web Alpha 0.14.1。

不要重跑V0.14.0原始SQL、FIX1或FIX2；当前数据库已经部署FIX2时只执行V0.14.1升级SQL。
