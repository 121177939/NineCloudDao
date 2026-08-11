# 九霄问道 · V2.2.0 CACHE133

当前交付：**CACHE133 / ADMIN9 R38 / SQL261 READY（生产当前 SQL260 ONLINE）**。CACHE133 同时修复 Android APK 发布校验器与天道人物自由交谈的真实 AI 回应。

## CACHE133 · 真实AI自由交谈 + APK发布修复

- 人物自由交谈不再调用浏览器原生 `prompt()`；改为游戏内输入框，并保留玩家原话展示。
- Cloudflare Workers AI 必须针对玩家原话、NPC人格、关系、当日心情/活动/事件给出具体回应；空回应判定失败并自动进入 `server_personality_v1`。
- 结果页明确显示本次是 **Cloudflare AI** 还是 **本地人格兜底**。
- SQL261 将 AI 的 accept/defer/reject/neutral 只映射为服务端固定范围关系反馈；明显侮辱不会再错误增加信任/好感。
- 修复 GitHub Actions APK 失败：`android/tools/validate_project.py` 改为从当前基线动态读取 versionCode/versionName/buildId，不再硬编码 CACHE129。
- 根仓库与 Android 独立仓库两套 `release-apk.yml` 路径均已校正。
- CACHE132 PC 底部导航鼠标横拖/滚轮分页继续保留。

## 本版部署顺序

1. 执行 SQL261，必须看到 `SQL261_GATE_PASSED`。
2. 重部署 `tiandao-ai` CACHE133 R2（本版必须重部署，Secrets 名称不变）。
3. 部署 CACHE133 Pages/游戏仓库。
4. 重新运行 `release-apk.yml` 生成 Android APK。

Android：**versionCode 2001512 / versionName 2.2.0-cache133**。GM：**ADMIN9 R38，不改**。下一 SQL：**SQL262**。

---

# 九霄问道 V2.2.0 CACHE127

当前开发交付基线：**V2.2.0 CACHE127**；Android：**versionCode 2001506 / versionName 2.2.0-cache127**；GM：**ADMIN9 R34**。

生产数据库当前按 **SQL258 ONLINE** 管理；CACHE127 是天墟装备详情前端修复版，不需要新增 SQL；下一条数据库编号 **SQL259**。

## V2.2.0 CACHE127 · 天墟装备详情
- 商品列表继续只显示品级、名字、价格。
- 装备“详情”改为中文玩家属性：境界/部位/武器类型、强化、主属性、开放孔位、孔位属性与LV。
- 不再显示 location / is_locked / grade_code / acquired_at / source_type 等数据库字段。

- 市坊旧博弈玩家运行时退役，新增玩家自由市场 **天墟**。
- 所有真实库存物品均可交易；灵石作为唯一结算货币，角色成长状态不作为商品。
- 公开一口价、完全自由定价、买入后可再次出售；不可指定买家，不可购买自己的挂单。
- 默认上架费1%、成交税5%、挂单72小时、每角色最多10个有效挂单；GM ADMIN9 R34可调整。
- 可堆叠物品支持部分购买；装备按唯一实例原样托管与转移，不重建属性/孔位。
- 浏览页商品卡严格只显示 **品级 · 名字 · 价格**；其它内容统一进入详情查看。
- 服务端使用资产托管、原子成交、幂等请求与永久交易流水，避免重复扣款、重复发物和一物多卖。
- 当前客户端已移除旧牌桌/实时前端运行资源；历史数据库记录本版保留归档，SQL255负责关闭旧Feature、相关Cron及玩家RPC权限。

## V2.2.0 CACHE123

- 修复功法三页签串显示：修炼只显示修炼，攻伐只显示攻伐，护体只显示护体。

## V2.2.0 CACHE122

- 功法页拆分为修炼 / 攻伐 / 护体，新增攻伐10本、护体10本、残卷10合1与同品5换1。
- 四类功法升级灵石默认统一提高至旧成本10倍；功法效果真实接入天命榜、秘境PVP、秘境妖兽与世界BOSS服务端结算。

CACHE120装备洗炼极速链、GitHub Pages默认artifact R3、Android既有正式签名/Release在线更新链全部继承，不改变已验证发布方式。
