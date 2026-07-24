# GitHub Desktop 更新到 V0.8.0

> 本版必须先升级 Supabase 数据库，再上传网页。不要先上传 V0.8.0 前端。

## 一、先备份

1. 复制当前本地仓库，命名为 `NineCloudDao_V0.7.0_上线前备份`。
2. 确认线上 V0.7.0 已经可以正常登录、修炼、死亡和转世。
3. 建议备份 Supabase，或至少保存当前 43 表、26 函数的检查结果。

## 二、执行数据库升级

1. 解压 `NineCloudDao_Game_V0.8.0.zip`。
2. 打开 Supabase → SQL Editor → New query。
3. 完整复制并执行：
   `database/V0.8.0/202607240014_technique_system_v2.sql`
4. 只执行一次，不要连续点击 Run。
5. 成功后新建查询，执行：
   `database/V0.8.0/202607240014_check.sql`
6. 重点确认：
   - 公共业务表为 47 张；
   - 公共函数为 35 个；
   - 品质规则 6 条、组合规则 4 条；
   - 时间倍率仍为 12；
   - 重复功法、重复槽位和异常熟练查询均为 0 行。

若 SQL 报错，不要上传网页，也不要重复运行迁移。保存完整报错信息。

## 三、覆盖 GitHub 仓库

1. 打开 GitHub Desktop，选择 `NineCloudDao`，确认分支为 `main`。
2. 点击 `Fetch origin`；有 `Pull origin` 时先 Pull。
3. 解压 `NineCloudDao_GitHub_Upload_V0.8.0.zip`。
4. 进入能直接看到 `index.html`、`app.js`、`release_config.json` 的目录。
5. 在 GitHub Desktop 选择 `Repository` → `Show in Explorer`。
6. 把上传包内部全部文件复制到仓库根目录并替换。
7. Summary 填写：`Update game to V0.8.0`。
8. 点击 `Commit to main`，再点击 `Push origin`。
9. 打开 GitHub Actions，确认自动验证和部署均为绿色。

## 四、线上验证

打开：

`https://121177939.github.io/NineCloudDao/?v=080`

确认页脚为 `Web Alpha 0.8.0`，并检查：

- 功法页显示主修槽、辅修一、辅修二；
- 功法显示品质、第几层/最高层、熟练、传承点和获得次数；
- 主修不能直接卸下，只能切换另一门主修；
- 最多运转两门辅修；
- 熟练与传承点合计不足 100 时不能精进；
- 组合条件满足后显示“已激活”，并影响修炼速度；
- 现实 1 天 = 仙历 12 年保持不变；
- 命书仍显示最新 100 条。

## 五、严重异常处理

不要删除功法表或手工改玩家数据。先执行：

`database/V0.8.0/202607240014_emergency_disable.sql`

它只暂停熟练增长和组合效果，保留功法、层数、传承点和槽位。修复后执行：

`database/V0.8.0/202607240014_resume.sql`
