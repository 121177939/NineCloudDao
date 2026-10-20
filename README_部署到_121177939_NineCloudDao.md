# TwoPhoneRemote Web A → 121177939/NineCloudDao（阶段六）

**Android 基线：** A/B `v2.0.51 / versionCode 105`，不升级、不修改。

**本阶段：** 历史列表与任务详情截图对齐。主历史页显示最近 30 条任务中最新 8 条终态任务；“查看全部历史”打开分页历史弹窗；点击任务直接展示私有云端小票图片、任务时间/状态/账号/说明与核验摘要。支持勾选最多 6 张历史图片，通过浏览器系统分享或下载原图。

## 部署文件

- 将本目录 `web-a/` 和 `.github/workflows/web-a-pages.yml` 按相对路径合并到 `121177939/NineCloudDao` 仓库根目录。
- 工作流只发布 `web-a/site/`，手动触发；不会发布 Android 源码、历史归档或测试材料。
- 不覆盖仓库已有 `update/android/`、A/B APK、`update_a.json`、`update_b.json` 或其他工作流。先人工检查仓库现状，再决定是否部署。
- 当前包尚未上传 GitHub，也未发布 Pages。`https://121177939.github.io/NineCloudDao/` 只是预期地址，不代表已部署或可访问。

## 云端与安全边界

- 历史任务与截图继续使用当前登录用户的 Supabase Auth/RLS/私有 Storage；图片下载仍要求路径以当前 UID 开头、拒绝 `..` 并限制 5 MB。
- 浏览器分享能力由 `navigator.share/canShare` 决定；不支持时下载原图供用户手动分享。网页不会自动选择微信联系人。
- 真实建单、双账号发送、STOP、取消、人工结案、通知 B 自动恢复接单继续关闭；详情中的结案按钮始终禁用。
- 不能把离线测试通过写成真实 Supabase、微信分享、Android 真机或生产任务验收通过。

## 测试

见 `README_WEB_A_阶段六_历史详情对齐.md` 与 `交接_验证结果.txt`。离线测试共 141 项通过。Playwright 浏览器 smoke 因运行环境导航策略拦截 `127.0.0.1` 而未通过/未验证；需要在允许浏览器导航的环境复跑。
