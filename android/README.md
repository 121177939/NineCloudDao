# 九霄问道 Android Studio 本地运行版 V2.0.6 CACHE98

- APP版本：2.0.6-cache98（2000698）
- 游戏资源：V2.0.6 CACHE98
- 构建号：`v2-0-6-cache98-equipment-worldnews3-pagesrecovery2-huaweinet1-appdialogupdate1`
- 数据库基线：V2.0.3 CACHE95 / SQL211-221 + SQL229-231
- AGP 8.2.2 / Gradle 8.2.1 / JDK 17 / API 34

游戏资源随APK本地运行，账号、存档和实时业务连接现有Supabase后端。华为网络兼容修复已经保留。

正式版启动及回到前台时静默检查同仓库最新GitHub Release；没有新版本时不显示任何内容，检测到更高versionCode时才弹窗询问是否更新。右下角没有浮动更新按钮。

在GitHub Actions中运行 `Build and publish Android APK`，默认Release标签为 `v2.0.6-cache98`。正式更新必须持续使用同一签名密钥。
