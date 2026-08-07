# V2.0.10 CACHE102 R2：GitHub Pages 部署恢复说明

## 结论

本次把网页部署方式恢复为 V1.8.2 已实际验证成功的官方默认方式：

- `actions/upload-pages-artifact@v4` 使用默认 Artifact 名 `github-pages`；
- `actions/deploy-pages@v4` 不再手动指定 `artifact_name`；
- checkout / Python / Node 回到旧稳定组合：`checkout@v4`、`setup-python@v5`、`setup-node@v4 + Node 20`；
- 保留 V2.0.10 的网页/Android资源一致性校验和 JS 语法检查；
- 新增部署后的线上强制验收：直接访问本次 Pages URL 的 `VERSION.txt` 和 `index.html`，带随机查询参数并禁止缓存。线上没有出现 V2.0.10 CACHE102 R2 时，工作流会明确失败。

## 为什么 V2.0.9 Release 成功但 Pages 仍可能是旧版

APK Release 与 GitHub Pages 是两条独立工作流。Release 成功只能证明 APK 发布链成功，不能证明 Pages 已更新。

与 V1.8.2 相比，V2.0.8/V2.0.9 的 Pages 流程曾增加“每次运行自定义唯一 Artifact 名称 + deploy-pages 指定同名 Artifact”的机制，并把运行环境提升到更新的 setup actions / Node 24。GitHub 官方目前支持自定义 Artifact 名称，但它不是这个项目必须的能力，也让排障多了一层变量。因此 R2 直接恢复已验证的默认 Artifact 流程。

另一个必须检查的问题是旧仓库残留工作流：如果只是把新文件覆盖上传到旧仓库，ZIP 里没有的旧 `.github/workflows/*.yml` 不会自动从 GitHub 删除。旧 Pages 工作流可能继续运行并覆盖新站点。R2 在构建开始时会检查根 `.github/workflows`，只允许：

- `deploy-pages.yml`
- `release-apk.yml`

发现其他工作流会直接报错并告诉你文件名。

## 正确上传方式

最好使用“干净替换仓库内容”的方式，不要仅在 GitHub 网页端把文件覆盖上去而保留旧文件。

提交后确认仓库根目录直接看到：

- `.github/workflows/deploy-pages.yml`
- `.github/workflows/release-apk.yml`
- `index.html`
- `VERSION.txt`
- `android/`

然后进入 `Settings → Pages`，确认 `Build and deployment → Source` 是 **GitHub Actions**。

## 验收

推送 `main` 后打开 Pages 工作流。成功时最后一步会出现：

`LIVE PAGES PASS: V2.0.10 CACHE102 / default artifact R2`

随后直接访问：

`你的Pages地址/VERSION.txt`

应看到：

- `V2.0.10 CACHE102`
- `PAGES_DEPLOY default-github-pages-artifact-r2`

如果 `VERSION.txt` 已是 V2.0.10，但普通首页仍显示旧版，说明是浏览器/PWA Service Worker 本地缓存问题，而不是 GitHub Pages 部署问题；此时用带查询参数的首页地址重新打开即可触发新资源，例如 `?pages_r2=1`。
