# 九霄问道 Android Studio 本地运行版 V2.2.0 CACHE133

本工程与网页 CACHE133 同步。Android：**versionCode 2001512 / versionName 2.2.0-cache133**，包名和正式签名方案不变。

本版修复 GitHub Actions 发布前校验器：`tools/validate_project.py` 不再硬编码旧 CACHE，而是动态读取当前 `CURRENT_BASELINE.json` / `PROJECT_MANIFEST.json` / `gradle.properties`。同时同步天道人物真实AI自由交谈客户端。

数据库必须先达到 `SQL261_GATE_PASSED`，并重部署 `tiandao-ai` CACHE133 R2 后再发布客户端。GM 继续 ADMIN9 R38。
