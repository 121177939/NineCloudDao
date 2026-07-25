# GitHub Desktop 更新到 V0.11.3

1. 备份当前本地仓库与线上V0.11.2文件。
2. V0.11.3不执行新Supabase SQL。
3. 打开GitHub Desktop并选择NineCloudDao仓库。
4. 点击Fetch origin；出现Pull origin时先Pull。
5. 解压 `NineCloudDao_GitHub_Upload_V0.11.3.zip`。
6. 进入内层目录，将全部文件覆盖到仓库根目录；不要多套一层文件夹。
7. Summary填写：`Fix runtime error and update to V0.11.3`。
8. 点击Commit to main，再点击Push origin。
9. 等待GitHub Actions显示绿色对勾。
10. 访问正式站点并使用 `?v=0113` 强制读取新版本。
11. 若PWA仍显示旧代码，完全关闭PWA并清理站点缓存后重开。

## 重点验证

- 页面版本显示Web Alpha 0.11.3；
- 登录角色后不再出现 `updateProgressionDisplay is not defined`；
- 修为持续增长；
- 突破进度条实时变化；
- 修为满足门槛后突破按钮自动可用；
- 自动机缘、功法、洞府、红尘、宗门、天命榜和命书仍可打开。
