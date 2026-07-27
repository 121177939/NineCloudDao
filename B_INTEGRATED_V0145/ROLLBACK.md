# 回滚

1. 先执行`database/90_emergency_disable.sql`停止新结算。
2. 执行`database/99_rollback.sql`恢复机缘旧函数并撤销玩家庄佣金。
3. 反向应用共享文件patch。
4. 回滚会删除本模块新增12门辅修的角色持有记录和定义；执行前必须备份。
