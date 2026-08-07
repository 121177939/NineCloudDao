# 九霄问道 V2.0.12 CACHE104 · 当前发布流程（已锁定）

## 最高优先级结论
V2.0.11 已由用户实际确认：**GitHub Pages 部署成功、APK 生成成功、APP 在线更新成功**。

因此后续版本只允许在现有成功链上推进版本号和游戏内容，**不得擅自更换 Pages 部署方式或 APK 生成/签名/Release 方式**。

## GitHub Pages
1. 用当前仓库包覆盖/更新 `main`。
2. `Settings → Pages → Source` 保持 **GitHub Actions**。
3. 使用 `.github/workflows/deploy-pages.yml`。
4. 继续默认 `github-pages` Artifact：`configure-pages@v5 → upload-pages-artifact@v4 → deploy-pages@v4`。
5. 部署后工作流必须在线无缓存读取 `VERSION.txt` 与 `index.html`；V2.0.12 成功标志：
   `LIVE PAGES PASS: V2.0.12 CACHE104 / default artifact R3`

## Android 正式 APK
1. Pages 验收成功后运行 `Build and publish Android APK`。
2. 使用当前 `.github/workflows/release-apk.yml` 成功链，不改步骤顺序。
3. 保持永久签名四项 Repository Secrets，不把值提交进仓库。
4. 默认 Release：`v2.0.12-cache104`。
5. Release 必须包含：
   - `jiuxiao-wendao-release.apk`
   - `app-update.json`
   - `SHA256SUMS.txt`

## 已知不要再踩的坑
- 不因 `Node.js 20 is deprecated` 这类非阻断警告就升级/替换已成功 Actions。
- 不恢复旧 `reset-pages-deployments` 清理逻辑；当前同名文件只允许安全占位。
- 不切换自定义 Pages Artifact 名称。
- 不把 APP 改成远程网页壳。
- 不在静态校验前生成 `release.keystore/signing.properties`。

更多见 `DEPLOYMENT_LOCK_已验证成功_禁止擅自变更.md`。
