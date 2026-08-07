# 发布方式锁定：已验证成功，禁止擅自变更

## 已验证成功案例
用户已明确确认 V2.0.11：
1. GitHub Pages 网页部署成功。
2. GitHub Actions 正式 APK 生成成功。
3. 已安装旧版 APP 能收到更新并成功完成在线升级。

这三项构成当前发布体系的最高优先级成功案例。

## GitHub Pages 锁定方式
- `.github/workflows/deploy-pages.yml`
- 默认 `github-pages` Artifact，不使用自定义唯一 Artifact 名。
- `actions/configure-pages@v5`
- `actions/upload-pages-artifact@v4`
- `actions/deploy-pages@v4`
- 部署后无缓存读取线上 `VERSION.txt` 与 `index.html` 做真实版本验收。
- `reset-pages-deployments.yml` 只保留安全占位/墓碑用途，不允许恢复旧清理部署逻辑。

## Android APK 锁定方式
- `.github/workflows/release-apk.yml`
- `ubuntu-24.04`、Java 17、Gradle 8.2.1、AGP 8.2.2、Android SDK 34。
- 先静态校验，再临时注入永久签名 Secrets。
- `assembleRelease` 后立即清理临时签名文件。
- 发布 APK + `app-update.json` + `SHA256SUMS.txt` 到 GitHub Release，并验证三个附件完整。
- 永久沿用相同包名 `com.jiuxiaowendao.game` 与同一生产签名。

## 禁止事项
除非用户明确要求，或者已验证方式因平台强制变化而无法继续执行，否则不得：
- 擅自切换 Pages 到 `/docs`、`gh-pages`、第三方部署或自定义 Artifact 策略。
- 因 Node.js deprecated 等警告就升级/替换已成功 Actions 版本。
- 恢复曾经干扰 Pages 的部署清理 workflow。
- 改动 APK 签名、包名或 release 关键步骤顺序。
- 把 APP 改成远程网页壳。
