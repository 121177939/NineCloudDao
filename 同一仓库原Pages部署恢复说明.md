# 同一仓库原GitHub Actions部署恢复说明

本包没有更换仓库，也没有改为分支发布。部署结构与V1.8.7 CACHE89一致：

`push main → build → upload-pages-artifact → deploy-pages`

只修复两项：

1. 工作流先检查当前仓库Pages发布源；若之前被改成分支发布，会自动恢复为GitHub Actions。
2. deploy-pages默认10分钟等待改为20分钟，部署作业总超时为25分钟。

上传前请在当前仓库执行一次：

- Actions：取消仍在运行的旧Pages工作流。
- Settings → Pages → Source：应为GitHub Actions（工作流也会自动校正）。
- Settings → Environments → github-pages：删除等待时间、Required reviewers和自定义保护规则；部署分支允许main。
- `.github/workflows`中只能有一个会调用`upload-pages-artifact`或`deploy-pages`的Pages工作流，即`deploy-pages.yml`。Android发布工作流不属于Pages工作流，可以保留。

然后将本包内容覆盖到同一仓库main根目录并产生一次新提交。不要重新运行旧失败记录。
