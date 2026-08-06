# Gradle 启动器说明

本项目附带自包含的 `gradle-wrapper.jar` 启动器及源码。它读取标准的
`gradle-wrapper.properties`，下载官方 Gradle 8.2.1 分发包，按固定 SHA-256
校验后安全解压并启动 Gradle。这样电脑不需要预装 Gradle。

- Android Gradle Plugin：8.2.2
- Gradle：8.2.1
- JDK：17
- Android SDK：API 34

启动器只负责 Gradle 分发包的下载、校验、解压和启动，不包含游戏、账号信息或签名密钥。
源码位于 `bootstrap-src/org/gradle/wrapper/GradleWrapperMain.java`。
