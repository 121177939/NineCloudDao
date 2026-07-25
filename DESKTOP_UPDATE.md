# GitHub Desktop 更新到 V0.11.0

1. 备份当前V0.10.0本地仓库与Supabase数据库。
2. 完整执行 `database/V0.11.0/202607240018_sect_system.sql`。
3. 执行 `database/V0.11.0/202607240018_check.sql`，确认68张表、57个函数及异常检查正常。
4. GitHub Desktop点击Fetch origin；有Pull时先Pull。
5. 解压 `NineCloudDao_GitHub_Upload_V0.11.0.zip`。
6. 将内层全部文件覆盖到仓库根目录。
7. Summary填写：`Update game to V0.11.0`。
8. Commit to main并Push origin。
9. 等待GitHub Actions绿色。
10. 打开正式站点并使用 `?v=0110` 强制读取新版本。
