# TwoPhoneRemote Web A → 121177939/NineCloudDao

**目标仓库：** `https://github.com/121177939/NineCloudDao`

**当前状态：源代码安全迁移工程 / 不可宣称 Android A 100% 功能等价或可投入真实资金任务。** 此包没有上传到 GitHub；没有连接账户写入权限，没有真实 Supabase/B 端联网验收。发布后，网页仍将以只读/原 Kotlin 解析与预览模式运行，尚不开放真实发送、STOP、取消及人工结案。

## 代码目录与部署

- 提交本包的 `web-a/` 目录和 `.github/workflows/web-a-pages.yml` 到 `121177939/NineCloudDao` 仓库根目录。
- **不要覆盖** 仓库已有的 `update/android/控制A.apk`、`控制B.apk`、`update_a.json`、`update_b.json` 或其他工作流。
- 打开仓库 `Settings → Pages → Build and deployment → Source`，选择 **GitHub Actions**。
- 进入 `Actions → Web A - GitHub Pages (manual) → Run workflow`，从目标分支手工发布。
- 当 Pages 在该仓库启用且部署成功后，项目站点的默认路径通常为 `https://121177939.github.io/NineCloudDao/`；**这只是预期路径，不是已经发布或验证可访问的地址。**
- 仓库若已经托管另一份 Pages 网站，启用本工作流可能替换同一仓库的站点，应先检查已有部署计划。

工作流只发布 `web-a/site/`，不发布 Android 源码、私有历史记录、测试材料或任何账号。GitHub Pages 是静态托管，不运行后台 STOP 守护进程。

## 基于 Android A v2.0.51 的 Web 能力

- **源码实现：** 手机风格的登录、控制中心、原 Kotlin/JS 识别和预览、账号信息展示、在线状态刷新、任务与历史列表、云端私有回图及分享。云端接口使用原版 Supabase URL、公开 publishable key、用户 Auth、RLS 和私有存储鉴权。
- **本阶段增强：** 整理了普通建单、双账号原子 RPC、STOP/自动释放、取消、人工核查相关 API 的浏览器适配器；加入任务 UUID 持久化、跨标签页互斥、旧任务未知结果保留锁定、B 心跳与 ACK 门禁；登录后可提示本地未决操作。相关代码在 `web-a/site/safety.js`、`transactions.js`。
- **仍未启用：** 网页按钮的真实发送、STOP、自动释放、取消、人工结案。即使 RPC 调用代码存在也不意味着其已通过生产运行验收。前端改动不能替代数据库 RLS、服务端幂等、防重试、任务一致性和真机检查。

## 达到用户要求的“真正完整版”还需完成

1. 需要 GitHub 仓库的授权连接，才能检查原仓库现有内容、避免覆盖其他配置并实际提交/发布。
2. 需要允许的 Supabase **测试环境**（独立于真实下注任务），核实 RPC、RLS、CORS、Storage 权限、数据库迁移实际部署情况。**不要把账户密码、管理员/secret key 发在聊天里或提交到 GitHub。**
3. 对普通/双账号发送做真实服务端幂等与断网/刷新恢复，验证与目标 B 端的每一个状态门禁；如有需在浏览器关闭后继续可靠收尾的操作，应放在服务器端，而不是依赖 GitHub Pages/浏览器定时器。
4. 完整移植 Android A 设置、发送确认、核对结案、赔率与 STOP 状态机所有分支，并逐屏进行移动浏览器与 Android 真机对照验收。
5. 验收前不要修改 `site/app.js` 的写入禁用规则，亦不要尝试修改代码绕开服务器权限。

## 验证方法

仓库根目录运行：

```bash
node --check web-a/site/app.js
node --check web-a/site/supabase.js
node --check web-a/site/safety.js
node --check web-a/site/transactions.js
node web-a/tests/parser.test.cjs
node --experimental-default-type=module web-a/tests/safety.test.mjs
node --experimental-default-type=module web-a/tests/transactions.test.mjs
```

此次共通过 45 条 Kotlin/JS 解析/协议断言、26 条安全结构/策略断言和 12 个模拟事务场景，**仅限离线 mock**。浏览器真实页面自动化在工作环境被拦截本地 URL 导航，未取得通过结果；没有部署或连真实设备。

## 版本与归档

本次只是 Web A 安全移植的 **阶段三**，没有修改 Android A/B 的原 `2.0.51 / versionCode 105`，也没有更新在线 APK/JSON。新源码与新历史记录必须分别附在原完整双包之上，保留所有历史文件和 SHA-256 清单，不得用此部署包替代历史归档。
