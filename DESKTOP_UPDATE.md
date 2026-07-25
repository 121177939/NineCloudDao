# GitHub Desktop 更新到 V0.10.0

1. 备份当前V0.9.1本地仓库与Supabase数据库。
2. 完整执行 `database/V0.10.0/202607240017_npc_relationships.sql`。
3. 执行 `database/V0.10.0/202607240017_check.sql`，确认60张表、49个函数及异常检查正常。
4. GitHub Desktop点击Fetch origin；有Pull时先Pull。
5. 解压 `NineCloudDao_GitHub_Upload_V0.10.0.zip`。
6. 将内层全部文件覆盖到仓库根目录。
7. Summary填写：`Update game to V0.10.0`。
8. Commit to main并Push origin。
9. 等待GitHub Actions绿色。
10. 打开正式站点并使用 `?v=0100` 强制读取新版本。
