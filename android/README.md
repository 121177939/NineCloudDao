# 九霄问道 Android Studio 本地运行版 V2.2.0 CACHE130

本工程与网页 **V2.2.0 CACHE130** 核心游戏资源同步，继承既有正式签名、GitHub Release 与在线更新链，不改变包名。

Android版本：**versionCode 2001509 / versionName 2.2.0-cache130**。

本版修复天道人物详情弹窗动态事件、移动端 MutationObserver 重挂载卡顿，以及 Cloudflare 人物交互缺少即时反馈的问题。生产数据库已确认 **SQL259 ONLINE / NEXT SQL260**；本次无需新SQL，也无需重新部署已正常工作的 `tiandao-ai`。`server_personality_v1` 继续保留为独立 fallback。
