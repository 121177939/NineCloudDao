# Web A 阶段六：历史列表与任务详情截图对齐

基线：Android A/B `v2.0.51 / versionCode 105`，不升级 Android 版本。Web A 基于阶段五完整工程，新增独立阶段六目录；阶段三、阶段四、阶段五工程均在源码包中保留。

## 本阶段修复

1. 历史主页面只显示最近读取的 30 条云端任务中，最新的 8 条终态任务（`finished / cancelled / failed`），卡片改为与 APP 相近的名称、状态圆点、简要说明布局。
2. `查看全部历史 · 微信转发小票` 打开分页历史弹窗，30 条/页，支持上一页、下一页、刷新、勾选最多 6 张图片并通过浏览器系统分享或下载原图。
3. 点击任意历史任务，详情弹窗直接显示任务时间、状态、执行账号、说明、任务 ID、套码核验摘要及实际云端私有截图，不再要求用户先点“查看或分享”才能看到图。
4. 按 Android A `MainActivity.showHistoryDetail()` 的截图路径规则选择 `result_path / scatter_path / suite_path`：兼容旧任务、M1 纯散码、合并小票、独立散码+套码截图、套码下注页截图及 STOP 核实图。重复路径不重复展示。
5. 图片继续通过当前登录用户的 Supabase Storage 鉴权读取；路径仍必须属于当前 UID，拒绝 `..`，并限制 5 MB。读图失败会显示原因，不会删除或隐藏历史任务。
6. 真实建单、发送、STOP、取消、人工结案及通知 B 自动恢复接单保持关闭；人工结案按钮始终禁用。分享只把用户选中的图片交给系统分享面板，或在不支持时下载文件，不会写入云端任务。

## 部署

将本目录的 `web-a/` 与 `.github/workflows/web-a-pages.yml` 按相对路径合并到 `121177939/NineCloudDao` 仓库根目录。工作流只发布 `web-a/site/`，手动触发。不要覆盖仓库已有的 Android APK、`update/android/` JSON 或其他工作流；发布前先人工检查仓库现状。本阶段没有连接 GitHub、没有上传或发布。

## 离线测试

```sh
node --check web-a/site/app.js
node --check web-a/site/history-detail.js
node --check web-a/site/preview-model.js
node --check web-a/site/supabase.js
node --check web-a/site/safety.js
node --check web-a/site/transactions.js
node web-a/tests/parser.test.cjs
node web-a/tests/preview-model.test.mjs
node web-a/tests/preview-audit-regression.test.mjs
node --experimental-default-type=module web-a/tests/history-detail.test.mjs
node --experimental-default-type=module web-a/tests/history-ui.test.mjs
node --experimental-default-type=module web-a/tests/safety.test.mjs
node --experimental-default-type=module web-a/tests/transactions.test.mjs
python web-a/tests/browser_smoke.py
```

离线断言共 141 项通过（解析 45、阶段四预览 20、阶段五来源审计 16、历史路径与状态 13、历史 UI/安全结构 9、安全策略 26、模拟事务 12）。浏览器 smoke 在本运行环境仍被导航策略拦截（`ERR_BLOCKED_BY_ADMINISTRATOR`），不能算通过；需在允许浏览器导航的环境复跑。未验证真实 GitHub Pages、Supabase Auth/RLS/Storage、手机 B 联调或生产任务。

## 安全与历史

- Android A/B 的 Gradle、`versionName/versionCode`、`update_a.json/update_b.json`、APK URL、签名、数据库和协议均未修改。
- 本阶段仅改变 Web A 历史 UI、截图只读读取与分享；不启用任何生产写入。
- `README_WEB_A_阶段五_集成与边界.md`、阶段五校验清单与原始交接文件作为历史材料保留，不要将其当作阶段六当前校验清单。阶段六校验使用 `SHA256SUMS_WEB_A_阶段六.txt`。
