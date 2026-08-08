# 九霄问道 Android Studio 本地运行版 V2.1.1 CACHE113

本版与网页 V2.1.1 CACHE113 核心游戏资源同步，并保留 Android 专用 `android-local.js` 入口，不加载 PWA Service Worker / update-guard。

正式版：versionCode **2001413** / versionName **2.1.1-cache113**。数据库目标为 SQL243（升级SQL + 制度门禁）。GitHub Release 在线更新链继续沿用已验证 R6 流程，包名、签名和Release发布方式不变。

## CACHE113变化

- PERF2只降低空闲状态固定RPC轮询；修炼250ms本地显示、机缘1秒倒计时、牌九Realtime、战斗和主动业务即时同步保持。
- DBCAP03由SQL243负责，客户端不直接DELETE业务表。
- 网页与Android内置游戏资源必须保持同步。

## 构建与发布

继续使用仓库中既有Android构建/签名/Release工作流。不要因为Node/Action非阻断警告擅自替换已经验证成功的R6链路。

运行 `python3 tools/validate_project.py` 校验Android版本、BuildConfig和内置游戏资源；再运行仓库根目录 `python3 tools/verify_web_android_sync.py` 检查网页/Android同步。
