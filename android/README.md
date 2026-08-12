# 九霄问道 Android Studio 本地运行版 V2.2.0 CACHE136

本工程与网页 CACHE136 同步。Android：**versionCode 2001515 / versionName 2.2.0-cache136**，包名和正式签名方案不变。

当前生产基线（用户本对话确认）：**SQL264 ONLINE / ADMIN9 R40 / tiandao-ai CACHE136 R6 ONLINE**。

CACHE136 包含九霄游历300故事、天道人物自然AI、B模块多模型路由来源显示。APK发布前校验器继续动态读取 `CURRENT_BASELINE.json` / `PROJECT_MANIFEST.json` / `gradle.properties`，不硬编码旧 CACHE。

R6 只更新 Supabase Edge Function；如果已有 CACHE136 APK，不需要因 R6 单独重发 APK。新环境重建时请先确保 SQL264_GATE_PASSED，并部署 tiandao-ai R6。
