# GitHub Release在线更新

正式APK由仓库根目录 `.github/workflows/release-apk.yml` 构建。工作流自动把当前仓库owner/repo注入APP，因此新仓库应继续使用原名称 `NineCloudDao`。

Release必须包含：`jiuxiao-wendao-release.apk`、`app-update.json`、`SHA256SUMS.txt`。

APP无新版时不显示任何更新入口；发现更高versionCode时弹窗。APK下载后校验SHA-256、包名、版本号与签名证书，再交给系统安装器。
