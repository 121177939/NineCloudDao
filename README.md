# 九霄问道 V2.1.1 CACHE118

当前客户端基线：**V2.1.1 CACHE118**；Android：**versionCode 2001418 / versionName 2.1.1-cache118**；GM：**ADMIN9 R27**。

## 本次 CACHE118
- 修复 GitHub Pages 工作流版本漂移：CACHE117代码上传后，deploy-pages.yml仍校验/调用CACHE116构建器，导致build exit 1。
- 新增 `tools/build_pages_v2_1_1_cache118.py`，工作流源码门禁、构建与线上验收全部统一为CACHE118。
- 保留已验证的 default github-pages Artifact R3 部署方式；Node.js 20 deprecated提示是非阻断warning。
- 完整继承CACHE117装备修复：装备主列表location/is_locked为权威值；穿戴/卸下后强制重新拉取；淬炼/升品/破境提交前通过SQL247实时确认数据库位置。
- SQL247修复造化升品玉/乾坤破境石成功分支，统一使用 `bequipment01_value(template_id, grade_code)`。

## 数据库状态
**SQL247 R2 已由用户确认门禁成功。CACHE118无新增SQL，下一编号仍为SQL248。**

## 发布锁
沿用已验证的 Pages R3 与 Android Release R6 流程，不更换包名、签名链或Pages部署方式。
