# 九霄问道 V2.1.0 CACHE105：世界BOSS / 装备8孔统一升级候选

当前客户端目标基线：**V2.1.0 CACHE105**。

本版从 V2.0.12 CACHE104 选择性集成 B-WBOSS01，并加入装备孔位/洗练/器魂/升品破境、元神总属性弹窗与 ADMIN9 R21。**没有整包覆盖 CACHE104**。

- Web：V2.1.0 CACHE105，Build `v2-1-0-cache105-wboss01-equipmentforge1-admin21-sql233-deploylock1`。
- Android：`versionCode=2001405`，`versionName=2.1.0-cache105`，内置游戏资源已同步。
- 数据库：目标迁移 **SQL233**；下一编号 234。
- GM：**ADMIN9 R21**，可调整世界BOSS、孔位数值/概率/比例、强化开孔、升品破境、器魂等本次新增配置。
- 发布方式：继续沿用 V2.0.11 用户已验证成功的 Pages 默认 `github-pages` Artifact R3 与 Android R6 发布/签名链，工作流保持锁定。

## 重要门禁

当前构建环境没有测试库管理员 SQL 连接，因此这里只完成代码集成与静态验收；**没有执行 SQL233，也没有把世界BOSS生产开启**。

正式上线必须严格按：`PRECHECK → SQL233安装 → POSTCHECK → TEST_ENABLE（仅测试库）→ 测试验收 → PRODUCTION_ENABLE`。

详见 `V2.1.0升级说明.md`、`RELEASE_VALIDATION_REPORT.json` 与 `DEPLOYMENT_LOCK_已验证成功_禁止擅自变更.md`。
