# AGP兼容修复说明

旧项目使用AGP 9.3.0、Gradle 9.5.0和API 37。Android Studio版本低于Quail 2时会直接提示AGP不兼容，项目无法同步。

本版改为：

- AGP 8.2.2
- Gradle 8.2.1
- JDK 17
- compileSdk / targetSdk 34
- AndroidX Core 1.13.1
- AndroidX WebKit 1.11.0

这些调整只影响Android构建工具兼容性，不改变游戏强化界闻、Supabase连接、本地资源加载或GitHub APK在线更新逻辑。
