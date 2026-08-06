# 九霄问道 Android本地运行版｜无浮动按钮・新版本弹窗更新

本版不显示右下角小圆圈。正式版启动及回到前台时自动检查GitHub Releases；仅在发现更高versionCode时弹出是否更新。

APP版本：2.0.4-cache96-app2（2000497）
游戏资源：V2.0.4 CACHE96

# 九霄问道 Android Studio 本地运行版 V2.0.4 CACHE96

游戏资源直接打入 APK，不加载远程网页。构建组合：AGP 8.2.2、Gradle 8.2.1、JDK 17、Android SDK 34。

## GitHub自动更新

将本项目上传到公开GitHub仓库后，配置四个Actions Secrets：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

运行 `Build and publish Android APK`，或推送标签 `v2.0.4-cache96`。工作流会自动把当前GitHub仓库写进APK，生成签名APK并发布到该仓库的最新Release。

正式版APP启动以及回到前台时会自动检查最新Release；发现更高 `versionCode` 后提示下载。下载完成后校验SHA-256、包名、版本号和签名，再打开安卓系统安装确认。

普通Android应用不能无提示静默安装，用户首次需要允许“来自此来源”，每次更新仍由系统安装器确认。

内置游戏构建：`v2-0-4-cache96-equipment-worldnews3-branchpublish2-appautoupdate1`。数据库沿用V2.0.3 CACHE95 / SQL211-221 + SQL229-231；本版本无新增SQL。
