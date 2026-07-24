# GitHub Desktop 更新到 V0.7.0

> V0.7.0 与之前不同：必须先升级 Supabase 数据库，再上传网页。不要颠倒顺序。

## 一、先备份

1. 复制当前本地仓库目录，命名为 `NineCloudDao_V0.6.6_上线前备份`。
2. 在 Supabase 中记录当前项目为 `fyykkqkovccgmamsdeoq`。
3. 建议在 SQL Editor 中保存当前 40 表、23 函数的检查结果或完成数据库备份。

## 二、执行数据库升级

1. 解压完整游戏包 `NineCloudDao_Game_V0.7.0.zip`。
2. 打开 Supabase → SQL Editor → New query。
3. 完整复制并执行：
   `database/V0.7.0/202607240013_time_lifespan_reincarnation.sql`
4. 成功后另开一个查询，执行：
   `database/V0.7.0/202607240013_check.sql`
5. 确认：
   - 公共业务表为 43 张；
   - 公共函数为 26 个；
   - `game_years_per_real_day` 为 12；
   - `is_enabled` 为 `true`；
   - 三张新表均开启 RLS。

如果升级 SQL 报错，不要继续上传网页，也不要反复执行。保存完整错误信息。

## 三、覆盖 GitHub 仓库

1. 打开 GitHub Desktop，选择 `NineCloudDao`，确认分支为 `main`。
2. 点击 `Fetch origin`；出现 `Pull origin` 时先 Pull。
3. 解压 `NineCloudDao_GitHub_Upload_V0.7.0.zip`。
4. 进入能直接看到 `index.html`、`app.js`、`release_config.json` 的文件夹。
5. 在 GitHub Desktop 选择 `Repository` → `Show in Explorer`。
6. 把上传包内部全部文件复制到仓库根目录，选择替换。
7. Summary 填写：`Update game to V0.7.0`。
8. 点击 `Commit to main`，再点击 `Push origin`。
9. 打开 GitHub Actions，等待绿色对勾。

## 四、线上验证

打开：

`https://121177939.github.io/NineCloudDao/?v=070`

确认页脚显示 `Web Alpha 0.7.0`，然后检查：

- 页面显示“现实1日=仙历12年”；
- 年龄、剩余寿元和仙历能够同步；
- 命书仍为最新100条；
- 修炼、突破、机缘、储物、功法和单设备会话正常。

## 五、出现严重问题时

不要删表。先执行：

`database/V0.7.0/202607240013_emergency_disable.sql`

这会立即暂停仙历、年龄和寿元推进，同时保留全部角色、死亡和轮回数据。修复后用 `202607240013_resume_12x.sql` 恢复。
