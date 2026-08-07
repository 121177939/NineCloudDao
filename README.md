# 九霄问道 V2.1.1 CACHE110：装备孔位洗炼交互重做

当前客户端目标基线：**V2.1.1 CACHE110**。

- Web：V2.1.1 CACHE110，Build `v2-1-1-cache110-forgeui2-admin22-sql239`。
- Android：`versionCode=2001410`，`versionName=2.1.1-cache110`，内置游戏资源与网页同步。
- GM：继续使用 **ADMIN9 R22**。
- 数据库：本次使用 **SQL239 升级 + SQL239制度门禁**；SQL239幂等保留百炼GM总开关。

本版重点：材料栏压缩、孔位规则点击查看、单列孔位最终值、最多锁3孔、百炼一次重炼全部未锁已有孔等级、兵魄/护道/百炼操作原地即时更新。

发布方式继续锁定沿用已验证成功的 GitHub Pages 默认 Artifact R3 与 Android Release R6 流程，不更换发布链。
