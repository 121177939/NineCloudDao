# Web A v2.0.51 – 识别预览与 Android A 对齐（仅 UI 增量）

目标仓库：`121177939/NineCloudDao`，分支：`main`，GitHub Pages 采用已建立的 `.github/workflows/web-a-pages.yml`。

## 上传这三份必需网页文件

在 GitHub 的 `web-a/site/` 中覆盖上传：

- `app.js` —— 按原 Android v2.0.51 `openPreviewSheet()` 分区显示散码、全转与套码，支持来源原文高亮、忽略文本黄底、展开和复制识别结果。
- `index.html` —— 对应字号、卡片、文案和预览细节。
- `preview-model.js` —— 新增独立的展示分组/来源回溯辅助代码。**它不替代原 Kotlin/JS 识别器，也不改变命令或金额。**

仓库里的 `web-a/site/parser.js`、`safety.js`、`supabase.js`、`transactions.js`、`.nojekyll` 全部保留，不需要重新上传。

## 建议同时上传

- `web-a/tests/preview-model.test.mjs`（新增预览回归检查）。
- `.github/workflows/web-a-pages.yml`（在原部署工作流中增加预览测试和必要文件检查；如仓库现存版本有其他自定义配置，请人工合并，不应直接替换其他工作流）。

已存在的 `web-a/tests/parser.test.cjs` / `safety.test.mjs` / `transactions.test.mjs` 保留。绝对不要删除 Android `update/android/`、APK、JSON、历史记录和其他老工作流。

上传成功后到 Actions 运行 `Web A - GitHub Pages (manual)`（`main`），等待变成绿色，再从网页访问，最好使用无痕窗口或强制刷新缓存。

## 参考示例

- `1234-1234各1`：识别成功，套码 1 条，预览可展开 16 组；第 1 卡为手机端保留的空散码区。
- `5000..5157..8157...5638..8638..5303..8303, 8182..0182, 4323, 3712, 5155..7197, , 5290, , 8782....1503五七各1`：散码 16 组，首页汇总为单张“散码区”卡，单组金额 1 元；“五七”标注已自动忽略并在原文黄底标识。

## 验证边界

本次只调整预览 UI 和显示模型，原 `parser.js` 及 B/云端任务协议不变。离线预览 20 项、原 Kotlin/JS 识别 45 项及安全/事务离线测试通过；GitHub Pages 在线 UI 与真实云端联调未重新执行。原版本的真实发送、STOP 及双账号写入仍因安全验收不足保持禁用，**不能声称是 100% 功能版**。
