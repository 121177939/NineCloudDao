# V0.15.0 数据库变更

执行顺序：

1. `202607281900_v0150_precheck.sql`
2. `202607281910_v0150_fish_continuous_bet_world_feed_exclusion.sql`
3. `202607281920_v0150_check.sql`

本迁移不修改鱼虾灵局概率、赔率、结算公式、下注表或历史数据，只在九霄界闻触发器中加入 `fish_shrimp` 显式排除，并将发布控制提升到 CACHE16。

回滚时执行 `202607281930_v0150_rollback.sql`。回滚不会删除任何鱼虾下注记录。
