# 九霄问道 V1.8.4 CACHE83

客户端构建：`v1-8-4-cache83-bsect02-deployfix1`。

本版从V1.8.3 CACHE82原样保留宗门经营V2第二阶段及此前全部修复，只处理GitHub Pages部署包结构错误并提升缓存纪元。上一版公开ZIP错误地只打包了`.pages-site`产物，没有携带`.github/workflows/deploy-pages.yml`与`tools`构建脚本；仓库原工作流因此可能在build阶段退出。本版同时将GitHub Actions组件升级为Node 24兼容版本。

## 部署方式

1. 解压本ZIP。
2. 将ZIP根目录里的全部文件和隐藏目录上传到GitHub仓库根目录，必须包含`.github`、`tools`、`.nojekyll`。
3. 不要把外层文件夹整体再套一层上传，也不要只上传`.pages-site`。
4. 提交到`main`后等待`build`与`deploy`两个任务完成。
5. SQL185—190已经执行完成，本版没有新SQL，禁止重复执行。

GM继续使用ADMIN9 R13，本次无需更换。
