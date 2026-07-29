# B模块交付规范

B模块压缩包至少包含：

- `00_MODULE_README.md`：目标、范围、用户规则；
- `CHANGE_LIST.md`：新增、修改、删除的文件；
- `SQL_CANDIDATE/`：候选SQL、检查SQL、回滚或紧急停用SQL；
- `TEST_RESULTS.txt`：本地静态检查和场景测试；
- `CONFLICT_NOTES.md`：可能与正式基线冲突的表、函数、RPC、界面和缓存；
- 完整源文件，不只交付diff截图。

B不得自称正式发布，不得直接升版。所有数据库对象应带模块前缀或版本后缀，避免覆盖正式函数；确需替换正式函数时必须在说明中逐项列出。
