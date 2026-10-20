# Web A 阶段五（安全预览审计修复 / 完整 GitHub Pages 工程）

基线：Android A/B `v2.0.51 / versionCode 105`（**不升级、不修改**）；Web A GitHub Pages 阶段三完整工程 + 阶段四覆盖文件。原阶段三、阶段四目录仍在同一个源码 ZIP 中保留；本目录是已整合的下一版 Web 工程。

## 部署文件

将本目录中的 `web-a/` 与 `.github/workflows/web-a-pages.yml` 按相对路径合并到用户确认的仓库 `121177939/NineCloudDao` 的 `main` 分支。GitHub Pages 工作流仍为**手动触发**，只上传 `web-a/site/`。保留仓库现有 `update/android/`、APK、在线 JSON 以及其他自定义工作流；不要整体清空仓库或覆盖无关文件。上线前人工核对仓库现状。

## 相对阶段四的变动

1. 整合完整可部署的 `parser.js`、`app.js`、`index.html`、`preview-model.js`、`safety.js`、`supabase.js`、`transactions.js`、`.nojekyll` 与既有测试和工作流，避免只给零散覆盖文件。
2. 修复两条相同套码在预览中错误高亮同一原文范围的问题；未找到的原文位置不再回退复用旧命中。
3. 套码未找到文字来源时明确标记“需确认”；仅一条旧式速记套码时可展示完整原始文字供核对，但**不伪称已准确定位**。
4. 按既有 v2.0.21 Android 规则：最终仅展开一组号码的定位型结果属于“散码区”，不因解析器返回 `suites` 而显示为套码。此处仅改 Web 展示分类，不变更 Kotlin/JS 解析结果、命令内容或金额。
5. 混合输入优先定位套码来源，再标记普通散码，避免普通散码错选在前面套码的内容中。新增 16 项专项回归断言；部署工作流纳入这一组测试。

## 安全边界

真实建单、双账号发单、STOP、取消、人工结案等生产写入继续关闭；**不得**因为网页预览通过就解开 `app.js` 的 `FAIL_CLOSED`。浏览器登录会申请 A 角色租约，可能影响 Android A 当前登录；生产任务未决时勿测试登录。公开站点源码只能含 Supabase publishable key，绝对不能提交 secret/service_role key、登录密码、私有截图或 APK 签名材料。

## 离线验证（在本目录运行）

```sh
node --check web-a/site/app.js
node --check web-a/site/preview-model.js
node --check web-a/site/supabase.js
node --check web-a/site/safety.js
node --check web-a/site/transactions.js
node web-a/tests/parser.test.cjs
node web-a/tests/preview-model.test.mjs
node web-a/tests/preview-audit-regression.test.mjs
node --experimental-default-type=module web-a/tests/safety.test.mjs
node --experimental-default-type=module web-a/tests/transactions.test.mjs
```

离线回归：45 项解析 + 20 项阶段四预览 + 16 项阶段五定位回归 + 26 项安全 + 12 项事务模拟通过。Chromium/Playwright 原浏览器 smoke 因 `https://web-a.test/` 导航被环境策略拒绝，**未通过浏览器自动化**；未进行 GitHub Pages 在线访问、真实 Supabase/RLS、B 真机、APK、Android 覆盖安装或生产发布验收。

历史与源码交付必须两包同时提供；历史旧记录及 SHA256 清单全部保留。此次只升级 Web 阶段，不改 Android `v2.0.51 / 105` 及其 A/B JSON。
