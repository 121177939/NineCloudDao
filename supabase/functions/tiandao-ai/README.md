# tiandao-ai · 天道人物 Cloudflare Workers AI 网关

生产链路：玩家客户端 → Supabase Edge Function `tiandao-ai` → Cloudflare Workers AI → PostgreSQL `tiandao_ai_apply_v259` 服务端规则复核 → 状态写入。

## 必须配置的 Supabase Edge Functions Secrets

- `CLOUDFLARE_ACCOUNT_ID`：在 Supabase Dashboard → Edge Functions → Secrets 中填写 Cloudflare Account ID。
- `CLOUDFLARE_AUTH_TOKEN`：由项目所有者本人填写，严禁提交 Git、Pages、Android 或任何客户端资源。

Supabase 自带的 `SUPABASE_URL`、publishable/secret key 环境变量由平台提供。本函数兼容新 `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS` 与旧 `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY`。

## 部署

```bash
supabase functions deploy tiandao-ai --project-ref <你的Supabase项目ref>
```

本函数需要用户 JWT；不要以 `--no-verify-jwt` 方式公开部署。

## Cloudflare 模型

默认模型由 SQL259 R2 设置为 `@cf/qwen/qwen3-30b-a3b-fp8`，GM 可读取当前模型。本版不允许客户端提交模型名覆盖服务端设置。
