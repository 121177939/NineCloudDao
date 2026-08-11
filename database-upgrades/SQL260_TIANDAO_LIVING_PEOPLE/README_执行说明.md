# SQL260 执行说明

前置：当前生产必须已经是 **SQL259 ONLINE**。

执行 `01_SQL260_V2.2.0_CACHE131_完整天道人物_活人系统_执行即门禁.sql`（文件内容已是 SQL260 R2 ABI兼容版）。

最后必须看到：`SQL260_GATE_PASSED`。

如果事务中任何门禁失败会直接报错并停止，不要继续部署 CACHE131。成功后数据库基线记为 **SQL260 ONLINE / NEXT SQL261**。

本 SQL 保持现有 `tiandao-ai` Edge Function 的 prepare/apply RPC 签名，因此无需重新部署 Edge。

## R2 函数 ABI 兼容热修

SQL259 线上已有 `tiandao_add_memory_v259(uuid,uuid,text,text,integer,boolean,jsonb)`，其返回类型是 `void`，第三个参数名是 `p_type`。SQL260 R1 错误地把同一签名改成了 `RETURNS uuid` / `p_memory_type`，PostgreSQL 会报 `42P13 cannot change return type of existing function`。

R2 **不 DROP 原函数**，保持 SQL259 的参数名和 `RETURNS void`，只替换函数体加入记忆去重，并继续保留每组关系低重要度记忆最多50条的原容量治理。若 R1 已报 42P13，直接重新执行 R2 全文件即可；若编辑器提示当前事务已中止，先单独执行 `rollback;` 再运行 R2。
