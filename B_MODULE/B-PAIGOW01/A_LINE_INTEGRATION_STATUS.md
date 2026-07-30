# A线正式并线状态

B-PAIGOW01已在V1.2 FIX1 CACHE38完成A线正式并线。

正式实现位于：
- `SQL/72_V1.2_FIX1_九霄灵牌正式并线.sql`
- 根目录 `b-paigow01.html`、`paigow-app.js`、`paigow-app.css`
- 根目录启动器 `b-paigow01.js`、`b-paigow01.css`

A线补齐了候选模块原先缺少的服务端安全洗牌、私牌遮罩、抢庄、倍率、组合、阶段推进、整桌单事务结算、请求幂等、责任资金冻结与生产页面RPC接入。原候选文件保留用于来源审计，不作为正式运行入口。
