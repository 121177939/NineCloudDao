# 九霄问道 Android Studio 本地运行版 V2.5.0 CACHE138

本工程与网页 **V2.5.0 CACHE138** 同步。Android：**versionCode 2001517 / versionName 2.5.0-cache138**，正式包名 `com.jiuxiaowendao.game`、原签名链与在线更新方式不变。

## 本版

- **SQL267**：灵兽完整闭环；数据库执行成功唯一门禁 `SQL267_GATE_PASSED`。
- **ADMIN9 R41**：灵兽全局参数、60图鉴物种、玩家灵兽发放/管理与接入检查。
- **CACHE138**：洞府新增“灵兽”页，包含捕捉、兽卵、喂养、互动、突破、三段进化、性格、技能、血脉传承、放归、图鉴、排行、兽苑。
- 游历、秘境、世界BOSS、天命PVP/共享战斗快照均接入灵兽。
- tiandao-ai **CACHE135 R6** 保持不变。

## 发布前

1. Supabase 执行 SQL267，必须看到 `SQL267_GATE_PASSED`。
2. 运行 `python tools/validate_project.py`。
3. 正式 APK 继续使用现有 GitHub Actions + Secrets 签名，不把 keystore/signing.properties 提交仓库。
