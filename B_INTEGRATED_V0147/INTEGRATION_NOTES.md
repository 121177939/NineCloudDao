# A线接入说明

## 基线锁

只允许接入：

- `baselineId`: `V0.14.6_AB4`
- `releaseLabel`: `Web Alpha V0.14.6 CACHE10`
- `app.js`: `e945f9dc2665934df924298f5777f99ee6175fd98bd28ad9585f0b0051740c6e`
- `styles.css`: `09fa1430daf2d9aa01bcaf623cfe74938fc364ec1cb04a8de326548d7c3fe41d`

若共享文件哈希不一致，应停止套补丁并由A线手工重放差异。

## 推荐接入步骤

```bash
patch -p1 < patches/app.js.patch
patch -p1 < patches/styles.css.patch
node --check app.js
```

数据库按以下顺序执行：

1. `database/00_precheck.sql`
2. `database/10_technique_book_library.sql`
3. `database/30_postcheck.sql`

也可审阅后执行：

- `database/九霄问道_B线_功法书与洞府藏经架.sql`

建议先上SQL再上前端，避免前端先调用尚未进入PostgREST缓存的新RPC。

## 数据兼容

- 旧玩家已经学会的功法保持原状，不补发功法书。
- 旧玩家已经领取过的首次奖励不重复发放。
- 模块生效后新产生的功法掉落才进入藏经架。
- 回滚时故意保留道卷表和道卷数据，避免玩家库存丢失。

## A线必须复核

- Supabase实际编译和事务执行。
- `30_postcheck.sql` 全部为真。
- 两设备同时点击同一本书时，只消费一次。
- 研习普通功法时，修为硬上限、灵石账户和洞府资源实际正确。
- 本命专属可学、异命专属不可学。
- 学习后没有自动装备。
- 离线864次事件中道卷聚合和性能。
- Android/iOS洞府卡片与底部导航真机显示。
- FIX7A、玩家庄、界闻、三榜、V0.14.6命书全量回归。
