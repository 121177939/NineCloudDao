# 九霄问道 V1.8.4 CACHE85 GitHub Pages完整仓库包

构建：`v1-8-4-cache85-bsect03-growth1-uifix1`

本版为CACHE84宗门成长系统的纯前端修复版：补回宗门页面合并时遗漏的`tabNav()`与`metric()`渲染函数，并提升缓存纪元，确保旧Service Worker不会继续返回错误脚本。

数据库继续使用SQL193—197；已经执行成功时禁止重跑。GM继续使用ADMIN9 R15。

上传时将本ZIP解压后的内容直接覆盖GitHub仓库根目录。根目录应直接看到`index.html`、`.github`、`tools`和`.nojekyll`。
