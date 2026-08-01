# 九霄问道 V1.7.5.3 CACHE54｜GitHub轻量部署包

基线：V1.7.5 CACHE51。

本包是纯前端热修，不执行SQL。

## CACHE54修复

- 修复上一版CACHE53的GitHub Actions工作流仍调用不存在的 `tools/build_pages_v1_7_5_1.py`，导致构建失败、线上实际上继续停留旧前端的问题。
- 灵骰中奖高亮继续复用鱼虾灵局金色发光效果。
- “本人已下注”改为服务端 `my_bets` 与本机已确认批次双源判断，不再依赖当前灵石/修为切换或旧DOM里的 `data-dice-has-bet`。
- 命中时同时挂载 `win` 与 `dice-win-glow`，并显式覆盖封盘后按钮的 disabled 透明度。
- 不修改赔率、开奖、资金结算、联合庄、奖池和数据库。
- 保留120ms批量下注、本地倒计时、阶段边界同步等多人性能设计。

## 部署

1. 解压本ZIP并覆盖GitHub仓库根目录，包含 `.github`。
2. 推送 `main`。
3. **确认GitHub Actions中的 build 和 deploy 两个Job均成功**；CACHE53如果构建失败，旧站点不会自动变成新版本。
4. 不执行任何新增SQL。数据库继续沿用V1.7.5 CACHE51（104/105/106）结构。
5. 手机彻底关闭旧页面后重新打开；CACHE54使用独立cache epoch 54。

