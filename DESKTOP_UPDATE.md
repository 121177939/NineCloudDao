# GitHub Desktop 更新到 V0.11.10-fix3

本次只更新前端底部导航，不需要执行新的SQL，也不要重复执行FIX1或FIX2数据库脚本。

1. 解压GitHub上传包。
2. 用解压后的全部文件覆盖仓库根目录。
3. 在GitHub Desktop中提交：`Fix six-item paged bottom navigation`。
4. Push到`main`，等待GitHub Actions变绿。
5. 彻底关闭旧PWA或浏览器标签，再访问`?v=01110fix3`。

底部导航第一页固定显示6项，多出的“命书”在第二页，手指左右滑动即可切换。
