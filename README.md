# 九霄问道 Web Alpha 0.11.9

V0.11.9是天道动态均衡正式整合版，继承V0.11.6机缘正负互斥及V0.11.7全部功能。

## 本版修复

- 灵气环境格保持原有UI，仅显示 `灵气环境（天道状态）x系数` 并支持点击弹窗。
- 天道系数作用于完整自动修炼速度。
- x0.5约为原速度的一半，x5约为原速度的五倍。
- 迁移SQL可在V0.11.6、V0.11.7或V0.11.7 FIX1之后安全重复执行。

## 数据库

先执行：

```text
database/V0.11.9/202607260300_v0119_heaven_balance_full_multiplier.sql
```

再执行：

```text
database/V0.11.9/202607260300_v0119_check.sql
```

预期数据库基线：75张public业务表、至少75个public函数。真实结果以Supabase检查SQL为准。

永久禁止执行：

```text
202607240019_auto_opportunity_v2.sql
```
