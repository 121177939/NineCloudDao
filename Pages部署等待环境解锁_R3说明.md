# Pages部署等待环境解锁 R3

本包保持同一仓库、GitHub Actions、Pages Artifact与deploy-pages方式不变。

本次只解决deploy作业显示“This check hasn't started”的问题：

- 不再使用可能被旧任务或保护规则锁住的 `github-pages` Environment。
- 新环境名：`nineclouddao-pages-live`。
- 不再使用旧的 `pages` 并发组。
- 新并发组按main分支隔离。
- 删除工作流内自动修改Pages设置的REST步骤，避免构建期间再次改变仓库发布配置。

APP仍为启动/回到前台静默检查；发现更高versionCode才弹窗，不显示右下角浮动按钮。
