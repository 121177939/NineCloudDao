# GitHub Desktop更新到V0.14.0

## 更新前

1. 备份Supabase数据库。
2. 确认当前线上源码基线为V0.13.1 FINAL。
3. 先在Supabase依次执行V0.14.0的precheck、主迁移、check与data audit。
4. 所有检查通过后再上传前端。

## 覆盖仓库

1. 解压 `NineCloudDao_GitHub_Upload_V0.14.0_FINAL.zip`。
2. 将包内全部文件覆盖到GitHub仓库根目录。
3. GitHub Desktop提交说明建议填写：`Add bazaar hub and world events V0.14.0`。
4. Commit to main并Push origin。

## Actions检查

以下步骤应全部为绿色：

- Verify V0.14.0 release metadata
- JavaScript syntax checks
- V0.14.0 SQL static audit
- Bazaar render simulation
- Build clean Pages staging directory
- Verify Pages staging directory
- Deploy to GitHub Pages

部署后访问站点并清理旧PWA缓存，页脚应显示Web Alpha 0.14.0。进入“市坊”确认三个入口与九霄界闻均正常；完成一局赌坊后应出现对应胜负播报。

不要重跑V0.13.0迁移，也不要执行任何已标记废弃的V0.12.0 FIX3脚本。
