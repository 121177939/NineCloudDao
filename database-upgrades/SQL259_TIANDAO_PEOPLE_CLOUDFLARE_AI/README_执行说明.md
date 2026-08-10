# SQL259 R2 执行说明

生产基线：**SQL258 ONLINE**。本文件用于 **SQL259 尚未正式上线** 的当前阶段，R2 正式替代先前 SQL259 R1。

执行文件：`01_SQL259_R2_V2.2.0_CACHE129_天道人物_CloudflareWorkersAI_执行即门禁.sql`

完整执行后，最后必须返回：`SQL259_GATE_PASSED`。看到该标志后才把数据库记录为 **SQL259 ONLINE / NEXT SQL260**。

R2 兼容曾经测试执行过 R1 的情况：AI设置与AI决策表使用 `ADD COLUMN IF NOT EXISTS` 补齐新增字段；旧直接写RPC仍保留历史定义但撤销玩家执行权，新玩家写操作统一经过 `tiandao-ai` Edge Function → AI提案 → 服务端规则审核。

不要把 `CLOUDFLARE_AUTH_TOKEN` 的实际值写进本 SQL、GitHub、Pages、Android 或客户端配置。
