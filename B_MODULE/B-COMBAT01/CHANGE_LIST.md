# 改动清单

## 修改候选源文件

- `app.js`
  - 开放战力榜。
  - 新增战力榜、挑战预览、挑战结算RPC客户端。
  - 新增本尊战力/五行摘要。
  - 新增挑战确认弹窗、战斗播放、伤害日志、结算页与文案。
  - 新增错误提示与战后榜单/界闻刷新。
- `styles.css`
  - 新增战力榜、五行标识、挑战确认、战斗战报、结算与移动端样式。
- `tools/test_ranking_render_v0143.js`
  - 改成兼容旧占位版与B-COMBAT01开放版，避免旧测试误判正式开放后的战力榜。

## 新增候选SQL

- `00_PRECHECK.sql`
- `10_B_COMBAT01_MAIN.sql`
- `20_CHECK.sql`
- `90_EMERGENCY_DISABLE.sql`
- `99_ROLLBACK.sql`

## 新增测试与说明

- `00_MODULE_README.md`
- `DESIGN_SPEC.md`
- `BALANCE_TABLE.md`
- `RPC_CONTRACT.md`
- `LOADOUT_ADAPTER_SPEC.md`
- `ACCEPTANCE_SCENARIOS.md`
- `CONFLICT_NOTES.md`
- `TEST_RESULTS.txt`
- `tools/ci_bcombat01.py`
- `tools/static_audit_bcombat01.py`
- `tools/test_balance_bcombat01.py`
- `tools/test_client_bcombat01.js`

## 未修改

- 版本号与CACHE27。
- `config.js`、`sw.js`、PWA与Pages工作流。
- `SQL/`正式编号迁移链。
- `database/`有效迁移链。
- 既有修炼、突破、赌场、灵石、功法槽和九霄界闻发布函数。
