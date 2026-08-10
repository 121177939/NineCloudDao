# 九霄问道 · V2.2.0 CACHE129

当前正式交付：**天道人物 Cloudflare Workers AI + 服务端规则审核 + 本地人格Fallback**。

- 生产数据库当前确认：**SQL258 ONLINE**。
- 发布前执行：**SQL259 R2**，最后必须看到 `SQL259_GATE_PASSED`；成功后 NEXT SQL260。
- GM：**ADMIN9 R36**。
- Edge Function：**tiandao-ai**。
- AI模型：**@cf/qwen/qwen3-30b-a3b-fp8**。
- Pages：继续使用已验证的预构建 `pages/` + GitHub 官方 artifact/deploy 链。
- Android：**versionCode 2001508 / 2.2.0-cache129**。

玩家人物写操作不再直接调用数据库写RPC，而是先进入 Edge Function；Cloudflare 只提供人物提案，数据库服务端重新校验后才允许状态变化。外部AI失败或超时时自动走 `server_personality_v1`。

公开客户端与 `pages/` / Android assets 不包含 Cloudflare 服务端凭据。Edge Function 与 Secrets 配置放在服务端私有交付中。

详见 `V2.2.0_CACHE129_Cloudflare_Workers_AI正式接入升级说明.md`。

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
