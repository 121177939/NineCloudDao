# 九霄问道 V1.8.5 CACHE86 GitHub Pages完整仓库包

构建：`v1-8-5-cache86-casinogate1`

本版新增赌场全服开关。SQL198执行后，可使用本地ADMIN9 R16开启或关闭赌场。关闭时，游戏显示固定提示：

> 服务器检查到当前游戏进行非法活动，已暂停此项功能。

## 部署

解压后将全部内容覆盖到GitHub仓库根目录。根目录必须直接包含`index.html`、`.github`、`tools`和`.nojekyll`。

先执行SQL198并确认`overall_ok=true`，再部署本前端。ADMIN9 R16仅本地使用，禁止上传到公开仓库。
