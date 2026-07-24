# GitHub Desktop 更新到 V0.9.1

1. 先备份当前V0.9.0本地仓库与Supabase数据库。
2. 在Supabase完整执行 `database/V0.9.1/202607240016_destiny_ranking.sql`。
3. 执行 `database/V0.9.1/202607240016_check.sql`，确认55张表、43个函数及权限检查正常。
4. GitHub Desktop点击Fetch origin；有Pull时先Pull。
5. 解压 `NineCloudDao_GitHub_Upload_V0.9.1.zip`。
6. 将内层全部文件覆盖到仓库根目录。
7. Summary填写：`Update game to V0.9.1`。
8. Commit to main并Push origin。
9. 等待GitHub Actions绿色。
10. 打开正式站点并使用 `?v=091` 强制读取新版本。
