# Cron关键任务与生产确认表 · CACHE112

## B资料确认的改造前生产R3

| jobname | 改造前schedule | 状态/用途 |
|---|---|---|
| `jiuxiao-auto-cleanup-v210` | 每日一次，20:25 | SQL210全局技术历史清理 |
| `jiuxiao_bsect06_daily_maintenance` | 每日一次，04:35 | BSECT06普通历史/请求维护 |
| PostgreSQL autovacuum | 系统自动 | B资料确认工作正常，保持开启 |
| 历史牌九1秒Cron | 已停用 | **禁止重新启用** |

每日扫一次时即便TTL字段写1天，实际历史最老可能接近24—48小时，因此CACHE112调整的是**现有任务**，不是再创建一套任务。

## SQL241门禁要求的正式CACHE112

| jobname | CACHE112 schedule | active | command用途 |
|---|---|---|---|
| `jiuxiao-auto-cleanup-v210` | `25 */6 * * *` | 必须true | DBCAP03全局技术历史滚动24h治理 |
| `jiuxiao_bsect06_daily_maintenance` | `35 */6 * * *` | 必须true | BSECT06普通历史先月汇总、请求TTL和案牍维护 |

SQL241只调用 `cron.alter_job` 修改这两个**已有job**，前置检查要求每个job恰好存在1个，防止重复任务。

## 其他已有Cron怎么处理

B的前置检查材料还会读取 `jiuxiao-auto-vacuum-v210`、`jiuxiao_bsect06_hourly` 等既有任务。SQL241不擅自改它们的schedule，也不在离线制作环境猜生产实际值。上线时请运行 `数据库健康检查_只读.sql`，它会把 `cron.job` 全部输出；将实际 jobname / schedule / active / command 保存进1h/6h/24h/48h验收记录。

红线：任何 `command` 含 `paigow_tick_due_rooms_bpaigow01` 且active=true，SQL241前置检查和门禁都会直接阻止通过。
