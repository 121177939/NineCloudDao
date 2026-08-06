# 九霄问道 V2.0.1 CACHE93

这是已构建好的GitHub Pages静态文件，构建号：`v2-0-1-cache93-equipment-worldnews1-branchdeploy1`。

## 发布方式

本版本**不使用自定义Pages Artifact工作流**。把本包全部文件覆盖到仓库 `main` 分支根目录，然后在：

`Settings → Pages → Build and deployment → Source`

选择：

- `Deploy from a branch`
- Branch：`main`
- Folder：`/(root)`

保存后，由GitHub Pages的分支发布机制直接上线。`.github/workflows/deploy-pages.yml`只保留手动校验，不会上传Artifact或执行部署。

## 数据库

先运行SQL221状态只读检查：未安装才执行SQL221；页面确认显示 `V2.0.1 CACHE93` 后执行SQL224正式门禁，再执行SQL225只读验收。SQL222—223不用于V2.0.1发布。

ADMIN9为本地文件，不得上传公开仓库。
