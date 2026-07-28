# 数据模型

`character_technique_books`

- `character_id`：所属角色。
- `book_kind`：`ordinary` 或 `exclusive`。
- `technique_code`：普通功法代码或专属代码。
- `quantity`：当前持有数量。
- 唯一键：`character_id + book_kind + technique_code`。
- 写入只通过安全定义者函数；客户端只允许读取自己的记录。

研习/参悟使用行锁读取道卷库存和角色，事务内扣减数量，因此同一行并发请求以数据库锁串行处理。实际并发仍需在Supabase环境验证。
