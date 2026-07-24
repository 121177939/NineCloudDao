# GitHub Desktop 更新到 V0.9.0

> 必须先确认 V0.8.0 修正版已成功，再升级 V0.9.0 数据库，最后上传网页。不要颠倒顺序。

## 一、确认 V0.8.0 修正版

若你曾看到：

`relation "v080_legacy_equipped" does not exist`

说明原版 V0.8.0 没有成功。请先执行修正版 `202607240014_technique_system_v2.sql`，再执行 V0.8.0 检查 SQL。V0.9.0 迁移会主动检查此前置条件，不满足时返回 `V080_FIXED_REQUIRED`。

## 二、备份

1. 复制当前本地仓库，命名为 `NineCloudDao_V0.8.0_升级前备份`。
2. 备份或记录 Supabase 当前数据状态。
3. 不要重新执行阶段 1 `all_in_one.sql`，也不要执行已经废弃的 V0.8.0 原始临时表脚本。

## 三、升级数据库

在 Supabase → SQL Editor → New query 中：

1. 一次性完整执行 `database/V0.9.0/202607240015_cave_management.sql`。
2. 成功后另开查询，执行 `database/V0.9.0/202607240015_check.sql`。
3. 确认新增表为 8、新增函数为 7、设置/资源/建筑/配方为 1/3/5/3。
4. 确认三种配方的 `output_item_exists` 全部为 `true`。
5. 确认理论总基线为 55 张公共表、42 个公共函数，异常查询均返回 0 行。

升级 SQL 报错时，不要反复点击 Run，也不要发布 V0.9.0 前端。

## 四、覆盖 GitHub 仓库

1. 打开 GitHub Desktop，选择 `NineCloudDao` 和 `main` 分支。
2. 点击 `Fetch origin`；出现 `Pull origin` 时先 Pull。
3. 解压 `NineCloudDao_GitHub_Upload_V0.9.0.zip`。
4. 进入能直接看到 `index.html`、`app.js`、`release_config.json` 的内层目录。
5. 点击 `Repository` → `Show in Explorer`，用上传包内部文件覆盖仓库根目录。
6. Summary 填写 `Update game to V0.9.0`。
7. 点击 `Commit to main`，再点击 `Push origin`。
8. 在 GitHub Actions 中等待绿色对勾。

## 五、线上验证

访问：

`https://121177939.github.io/NineCloudDao/?v=090`

确认页脚显示 `Web Alpha 0.9.0`，然后检查：

- 手机底部导航出现“洞府”；
- 洞府显示灵蕴、灵草、灵矿；
- 五座建筑及升级费用正常；
- 炼丹倒计时、取丹和储物数量正常；
- 转世后仍读取同一道统洞府；
- 功法、修炼、机缘、突破、时间寿元、命书和单设备会话无回归。

## 六、严重问题处理

不要删表。先执行：

`database/V0.9.0/202607240015_emergency_disable.sql`

它会暂停洞府资源生产和炼丹入口，但保留建筑、资源和炼丹记录。修复后执行 `202607240015_resume.sql` 恢复。
