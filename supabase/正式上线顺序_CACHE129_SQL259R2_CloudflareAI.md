# CACHE129 / SQL259 R2 / Cloudflare AI 正式上线顺序

生产当前确认：**SQL258 ONLINE**。请严格按以下顺序操作。

## 1. 执行 SQL259 R2

执行：
`database-upgrades/SQL259_TIANDAO_PEOPLE_CLOUDFLARE_AI/01_SQL259_R2_V2.2.0_CACHE129_天道人物_CloudflareWorkersAI_执行即门禁.sql`

最后必须看到：`SQL259_GATE_PASSED`。
只有看到该标志后，数据库才记为 **SQL259 ONLINE / NEXT SQL260**。

## 2. Supabase Edge Functions → Secrets

新增：

- `CLOUDFLARE_ACCOUNT_ID` = `5b79ea0b023989a461bbb8f8a6f0b374`
- `CLOUDFLARE_AUTH_TOKEN` = **由项目所有者本人在 Supabase 后台填写**

不要把 API Token 值复制进源码、聊天记录、GitHub、Pages、Android、`config.js` 或 `app.js`。

## 3. 部署 Edge Function

函数目录：`supabase/functions/tiandao-ai`

CLI 方式：

```bash
supabase functions deploy tiandao-ai --project-ref <你的Supabase项目ref>
```

`supabase/config.toml` 已明确 `verify_jwt = true`。不要改成公开匿名函数。

## 4. ADMIN9 R36 测试

打开 ADMIN9 R36 → 天道人物 → 测试AI连接。

成功目标：

Cloudflare Workers AI：连接成功
模型：@cf/qwen/qwen3-30b-a3b-fp8
NPC人格决策：正常
fallback：可用

如果 Cloudflare 失败但 fallback 可用，系统仍可运行；GM 会记录失败原因。

## 5. 最后部署 CACHE129

测试 Edge Function 后，再发布 CACHE129 Pages / Android。这样不会出现新客户端先上线、服务端 AI 网关尚未准备完成的窗口。
