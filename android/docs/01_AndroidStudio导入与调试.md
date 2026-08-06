# Android Studio 导入与调试

## 兼容环境

- Android Studio：Hedgehog 2023.1.1或更新版本
- Android Gradle Plugin：8.2.2
- Gradle：8.2.1
- Gradle JDK：17
- Android SDK：API 34
- 最低运行系统：Android 7.0（API 24）

## 导入

1. Android Studio → Open。
2. 选择本项目根目录，不要选择ZIP本身。
3. 打开 Settings → Build, Execution, Deployment → Build Tools → Gradle。
4. 将 Gradle JDK 设为 `jbr-17` 或其他JDK 17。
5. 在 SDK Manager 安装 Android SDK Platform 34 与 Build-Tools 34.0.0。
6. 点击 Sync Project with Gradle Files。
7. 连接开启USB调试的安卓手机，选择 `app` 后运行。

首次同步需要下载 Gradle 和 AndroidX 依赖。如果网络较慢，请等待下载完成，不要反复中断同步。

Debug 包名会自动增加 `.debug`，并默认关闭 GitHub 自动更新，避免调试签名与正式签名混用。

## 旧工程缓存处理

若你曾打开AGP 9.3旧工程：

1. 关闭旧工程。
2. 打开本修复版的新目录。
3. 仍显示旧错误时，执行 File → Invalidate Caches / Restart。
4. 不要把旧工程的 `.gradle`、`.idea` 或 `local.properties` 覆盖进新工程。
