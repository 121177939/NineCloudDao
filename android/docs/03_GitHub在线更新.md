# GitHub在线更新

正式版APP在启动和回到前台时自动检查当前GitHub仓库的最新Release，30分钟内不会重复请求。

## 一次性配置

在GitHub仓库 `Settings → Secrets and variables → Actions` 添加：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

永久签名可以运行 `tools/生成签名密钥并输出GitHubSecrets说明.ps1` 创建。签名密钥丢失后，已安装用户将无法覆盖更新。

## 发布

手动运行 `Build and publish Android APK`，Release标签留空即可使用 `v2.0.5-cache97`；也可以：

```bash
git tag v2.0.5-cache97
git push origin v2.0.5-cache97
```

GitHub Actions正式构建时会自动把当前仓库owner/repo写进APK，不需要手工修改仓库地址。Release会包含APK、`app-update.json`和SHA清单。

普通Android应用不能静默安装。APP可自动检测、下载和校验，但安装时必须显示安卓系统确认界面。
