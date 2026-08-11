# 九霄问道 · V2.2.0 CACHE135

当前正式交付：**CACHE135 / ADMIN9 R39 / SQL263 READY（生产当前 SQL262 ONLINE）/ tiandao-ai CACHE135 R5 REQUIRED**。

## CACHE135 · B模块天道AI多模型调度器正式接入

- 天道AI云端路由：**GLM-4.7-Flash 主力 → Cloudflare Workers AI 备用 → server_personality_v1 永久本地兜底**。
- CACHE134 R4 已验证的 Cloudflare 响应兼容、人物自然对白门禁、鉴权、prepare/apply 服务端审计全部保留。
- 玩家人物结果卡准确显示 **GLM AI / Cloudflare AI / 本地人格兜底**，不会把 GLM 成功误标为本地Fallback。
- SQL263 只新增 ADMIN9 多供应商只读统计 RPC，不修改人物、九霄游历300故事、经济、关系或战斗规则。
- ADMIN9 R39 可分别测试 GLM、Cloudflare、本地Fallback，并查看24小时真实决策来源。
- CACHE134 九霄游历 V1：300条正式故事（240境界专属 + 60跨境界）、8区域、游历/调查/追踪/回访完整继承。
- CACHE132 PC底部导航鼠标横拖/滚轮分页、CACHE133 Android动态发布校验继续保留。

## 本版部署顺序

1. Supabase Edge Functions Secrets 配置B模块主力 GLM 凭据；原 Cloudflare Secrets 保留。
2. 执行 SQL263，必须看到 `SQL263_GATE_PASSED`。
3. 覆盖部署 `tiandao-ai CACHE135 R5`，函数名继续为 `tiandao-ai`，JWT验证保持开启。
4. 部署 CACHE135 Pages/游戏仓库。
5. 使用 ADMIN9 R39 分别测试 GLM / Cloudflare / 本地Fallback。
6. Android 如需同步本次来源显示，生成 CACHE135 APK。

Android：**versionCode 2001514 / versionName 2.2.0-cache135**。下一 SQL：**SQL264**。

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
