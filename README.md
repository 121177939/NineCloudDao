# 九霄问道 V2.1.1 CACHE119

当前客户端基线：**V2.1.1 CACHE119**；Android：**versionCode 2001419 / versionName 2.1.1-cache119**；GM：**ADMIN9 R27**。

## 本次 CACHE119

- 修复装备淬炼弹窗事件监听器残留：旧版把 click/change 监听器绑定到永久存在的 `modalRoot`，每打开一件装备就累积一次并捕获旧装备对象。
- 切换到第二件装备后，旧监听器会先执行并把 `busy` 设为 true，当前装备的新监听器随后退出，因此出现“只有第一件能洗，换装备后兵魄/护道/百炼无反应，重进游戏才恢复”。
- CACHE119 改为把监听器绑定到每次新建的 `.forge-backdrop-v210`；关闭弹窗时DOM与监听器一起销毁。
- 所有孔位洗炼、百炼、升品、破境、器魂承接按钮在点击时实时读取 `state.item`，不再使用弹窗打开时捕获的旧装备。
- CACHE118 GitHub Pages构建修复和CACHE117/116装备数据库规则全部保留。

数据库仍为 **SQL247 R2 已上线**；CACHE119无新增SQL，下一编号仍为 **SQL248**。

发布链继续锁定：`default-github-pages-artifact-r3` / Android Release R6，不改变已验证方式。
