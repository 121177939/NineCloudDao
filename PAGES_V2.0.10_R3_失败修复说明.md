# V2.0.10 CACHE102 R3：Pages 构建失败修复

## 本次截图的真实失败原因

截图中的红色错误不是 GitHub Pages 部署动作本身失败，而是 R2 新增的“工作流必须只有两个文件”自检主动 `exit 1`。仓库仍残留 `reset-pages-deployments.yml`，因此构建在真正上传 Pages Artifact 之前就被我们自己的门禁拦截了。

`Node.js 20 is deprecated` 是 GitHub Actions 的警告，不是这次 exit code 1 的原因。

## R3 怎么修

1. 删除 R2 的“任何额外 workflow 都失败”规则。
2. 只在发现另一个真正含 Pages 发布动作的 workflow 时阻止部署。
3. R3 仓库包主动包含 `.github/workflows/reset-pages-deployments.yml` 同名安全占位文件；覆盖上传后会把旧内容替换掉。这个占位 workflow 只有手动触发入口，而且 job 永远跳过，不会响应 push、不会删除部署、不会覆盖站点。
4. Pages 仍使用 V1.8.2 验证过的默认 `github-pages` Artifact 路径。
5. 部署后仍在线读取 `VERSION.txt` 与 `index.html`，必须看到 `PAGES_DEPLOY default-github-pages-artifact-r3` 才算完成。

## 上传后应看到的根工作流

- `deploy-pages.yml`：当前 Pages 部署。
- `release-apk.yml`：Android Release。
- `reset-pages-deployments.yml`：R3 安全占位，不会自动运行。

因此 R3 不要求你先手动删除截图中的旧文件；用 R3 仓库内容完整覆盖即可。
