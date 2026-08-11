# CACHE134 · B模块天道AI多模型调度器正式合并

## 版本
- 游戏客户端：V2.2.0 CACHE135（不变）
- 数据库：SQL263 READY，当前已知生产基线 SQL262 ONLINE
- Edge：tiandao-ai CACHE135 R5
- GM：ADMIN9 R39

## 路由
1. 智谱 GLM-4.7-Flash 主力。
2. GLM 缺 Key、超时、请求失败、空回复或被自然对白门禁判定无效时，自动尝试 Cloudflare Workers AI。
3. 两家云AI都失败时，继续数据库 server_personality_v1。

## 保留
- CACHE134 R4 Cloudflare 多响应结构兼容。
- 自由交谈必须直接回答玩家问题的自然对白规则。
- AI不能修改灵石、装备、境界、战斗、掉落或正式关系结果。
- SQL262 九霄游历300故事完整保留。

## SQL263
只新增 ADMIN9 只读指标 RPC `admin9_get_tiandao_ai_router_v263()`，统计 zhipu_glm / cloudflare_workers_ai / server_personality_v1；不改游戏状态表。

## 部署
新增 Supabase Secret `ZHIPU_API_KEY` → SQL263_GATE_PASSED → 部署 tiandao-ai R5 → 使用 ADMIN9 R39 测试。
B模块不改客户端，因此不要求重发 Pages / APK。
