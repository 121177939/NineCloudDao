# 九霄问道 · Web Alpha 0.6.0

东方文字修仙人生模拟游戏。当前版本已接入 Supabase 云存档，并可通过 GitHub Pages 自动发布。

## 当前可玩内容

- 邮箱注册、登录与云端角色
- 自动修炼与离线结算
- 灵根、命格、机缘与境界突破
- 功法运转、功法切换与灵石升级
- 储物袋、丹药与限时修炼增益
- 每日洞府补给
- 移动端五栏导航
- PWA 安装与 GitHub Pages 部署

## 数据库升级

首次使用 0.6.0 前，在 Supabase SQL Editor 执行：

`database/202607240011_inventory_technique_supply.sql`

不要重新执行阶段1的 `all_in_one.sql`。

## 本地运行

- 电脑：双击 `启动游戏.bat`
- 同一 Wi-Fi 手机测试：双击 `启动游戏_手机测试.bat`
- 固定端口：`8787`

## GitHub Pages

完整步骤见 [GITHUB_DEPLOY.md](GITHUB_DEPLOY.md)。仓库已包含 `.github/workflows/deploy-pages.yml`，推送到 `main` 后可自动发布。

## 安全说明

`config.js` 只包含 Supabase Project URL 与 Publishable key。Publishable key 是浏览器客户端使用的公开密钥；权限由数据库 RLS 控制。项目中没有 Secret key、service_role 或数据库密码。
