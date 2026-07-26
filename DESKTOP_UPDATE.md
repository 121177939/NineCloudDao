# GitHub Desktop更新到V0.13.1

## 重要说明

V0.13.0失败的根因是：复制新包只会覆盖同名文件，不会删除仓库中已存在的旧文件。旧的 `tools/audit_v0120_fix1.py` 因此仍保留，而V0.13.0验证器把它的存在直接判为失败。

V0.13.1已经从设计上兼容这种覆盖升级方式。

## 操作步骤

1. 备份当前仓库。
2. 解压 `NineCloudDao_GitHub_Upload_V0.13.1_FINAL.zip`。
3. 将包内全部文件覆盖到GitHub仓库根目录。
4. 不需要执行任何V0.13.1 SQL。
5. GitHub Desktop提交说明填写：`Fix Pages pipeline and update to V0.13.1`。
6. Commit to main，然后Push origin。
7. 打开Actions，检查以下步骤均为绿色：
   - Verify V0.13.1 release metadata
   - JavaScript syntax checks
   - V0.13.0 SQL static audit
   - Market render simulation
   - Build clean Pages staging directory
   - Verify Pages staging directory
   - Upload Pages artifact
   - Deploy to GitHub Pages
8. 部署成功后访问 `https://121177939.github.io/NineCloudDao/?v=0131`。
9. 完全关闭旧PWA并清理站点缓存后，确认页面显示Web Alpha 0.13.1。

## 可选清理

旧的根目录工具文件可以稍后删除，但不再是本次部署成功的前置条件。建议删除：

- `tools/audit_v0120_fix1.py`
- `tools/test_market_render_v0120_fix1.js`
- `tools/__pycache__/`

不要删除 `tools/legacy/` 中的历史审计材料。
