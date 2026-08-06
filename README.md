# V2.0.4 CACHE96｜原GitHub Actions部署恢复版

> 本包继续使用V1.8.7 CACHE89相同的GitHub Actions Pages发布方式，不使用Deploy from a branch，也不需要新仓库。详细步骤见《同一仓库原Pages部署恢复说明.md》。

# 九霄问道 V2.0.4 CACHE96

构建号：`v2-0-4-cache96-equipment-worldnews3-branchpublish2-appautoupdate1`。

## 发布方式

本包直接上传到 GitHub 仓库 `main` 根目录。进入 `Settings → Pages`，选择 `Deploy from a branch`、`main`、`/(root)`。

`.github/workflows/deploy-pages.yml` 现在只允许手动做静态校验，不会在 push 时创建 deploy 作业，也不会出现一直停在 `Deploying to github-pages` 的自定义环境部署。

数据库沿用 V2.0.3 CACHE95（SQL211-221 + SQL229-231），本版本无新增SQL。
