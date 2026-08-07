# 九霄问道：重建新仓库与APP自动更新完整流程

## 一、最终结构

建议保留原GitHub账号和原仓库名称 `NineCloudDao`。先把旧仓库改名为 `NineCloudDao-archive-20260806`，再创建全新的公开仓库 `NineCloudDao`。

这样可保持：

- Pages地址仍为 `https://你的用户名.github.io/NineCloudDao/`
- 已安装APP仍访问 `你的用户名/NineCloudDao` 的最新Release
- 不继承旧仓库的Actions运行、部署环境、Artifact、缓存和卡死记录

不要先删除旧仓库。新仓库网页和APK均验收完成后，再把旧仓库设为Archive。

## 二、重命名旧仓库

1. 打开旧仓库。
2. 进入 `Settings → General → Repository name`。
3. 改名为 `NineCloudDao-archive-20260806`。
4. 在旧仓库 `Actions` 中保持旧Pages工作流禁用。

## 三、创建新仓库

1. GitHub右上角 `+ → New repository`。
2. Repository name：`NineCloudDao`。
3. Visibility：`Public`。
4. 不勾选README、.gitignore或License。
5. 点击 `Create repository`。

## 四、上传本包（推荐GitHub Desktop）

### 推荐方式：GitHub Desktop

1. 解压本ZIP到全新目录。
2. GitHub Desktop选择 `File → Add local repository`；若提示不是Git仓库，选择创建仓库。
3. Local path选择解压目录，Repository name填 `NineCloudDao`。
4. 提交信息填 `Initial clean V2.0.10 CACHE102 repository`。
5. 点击 `Publish repository`，选择GitHub上的新 `NineCloudDao` 公共仓库。

### 命令行方式

在解压目录打开终端：

```bash
git init
git add .
git commit -m "Initial clean V2.0.10 CACHE102 repository"
git branch -M main
git remote add origin https://github.com/你的用户名/NineCloudDao.git
git push -u origin main
```

确认仓库根目录直接包含：

```text
.github/workflows/deploy-pages.yml
.github/workflows/release-apk.yml
android/
index.html
VERSION.txt
```

仓库中不应出现 `reset-pages-deployments.yml`、`nineclouddao-pages-live`或旧部署脚本。

## 五、首次部署网页

1. 新仓库进入 `Settings → Pages`。
2. `Build and deployment → Source` 选择 `GitHub Actions`。
3. 进入 `Actions → Deploy NineCloudDao V2.0.10 CACHE102 to GitHub Pages`。
4. 若首次push已经自动运行，可直接等待；也可以点击 `Run workflow → main → Run workflow`。
5. 正常流程：`build → deploy`。
6. 部署后打开：

```text
https://你的用户名.github.io/NineCloudDao/VERSION.txt
```

必须显示：

```text
V2.0.10 CACHE102
```

V2.0.10 R2 已恢复 V1.8.2 验证成功的默认 `github-pages` Artifact 部署方式，不再自定义 Artifact 名称。部署结束后 Actions 会自动无缓存访问线上 `VERSION.txt` 与 `index.html` 验证当前版本；只有读到 V2.0.10 CACHE102 R2 才算部署成功。

另外，根 `.github/workflows` 只允许 `deploy-pages.yml` 与 `release-apk.yml`。如果旧仓库残留其他 Pages 工作流，构建会明确报错；必须删除旧工作流后再运行。

## 六、APP签名：最重要的一次性设置

### 已有正式签名密钥

必须继续使用原来发布APP的同一把keystore。Android更新要求包名相同、签名证书相同，且新APK的versionCode更高。

### 没有正式签名密钥

在 `android/tools` 目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File ".\生成签名密钥并输出GitHubSecrets说明.ps1"
```

会生成：

```text
jiuxiao-release.keystore
ANDROID_KEYSTORE_BASE64.txt
```

把keystore至少备份到两个安全位置，绝对不要上传到GitHub。若之前用户安装的是不同签名或Debug APK，第一次切换到正式版可能需要卸载旧APP后再装；卸载可能清除本机APP数据。

## 七、在新仓库配置四个Secret

进入：

```text
Settings → Secrets and variables → Actions → New repository secret
```

添加：

```text
ANDROID_KEYSTORE_BASE64
ANDROID_KEY_ALIAS
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_PASSWORD
```

- `ANDROID_KEYSTORE_BASE64`：复制 `ANDROID_KEYSTORE_BASE64.txt` 的全部内容。
- `ANDROID_KEY_ALIAS`：默认脚本为 `jiuxiao`，或填写你原密钥真实Alias。
- 两个PASSWORD：填写创建keystore时使用的密码。

## 八、发布首个V2.0.10正式APK

1. 进入 `Actions → Build and publish Android APK`。
2. 点击 `Run workflow`。
3. Branch选 `main`。
4. Release标签留空。
5. 点击绿色 `Run workflow`。

成功后打开仓库右侧 `Releases`，应看到：

```text
v2.0.10-cache102
```

附件应包含：

```text
jiuxiao-wendao-release.apk
app-update.json
SHA256SUMS.txt
```

给用户安装的是 `jiuxiao-wendao-release.apk`。

## 九、APP自动更新的实际流程

正式版APP启动约2.5秒后、以及从后台回到前台时检查最新正式Release。30分钟内不重复检查。

- 没有新版：界面不显示任何内容。
- 有更高versionCode：弹出“发现新版本，是否立即更新”。
- 用户选择“立即更新”：下载APK。
- 下载完成：校验SHA-256、包名、versionCode和签名证书。
- 校验通过：打开安卓系统安装器。
- Android 8及以上首次需要允许“来自此来源的应用”。

普通APP不能静默覆盖安装；最后一步必须由安卓系统让用户确认。

## 十、以后每次更新APP

每次新版本必须同时修改：

```text
APP_VERSION_CODE（必须增大）
APP_VERSION_NAME
网页VERSION.txt与CACHE编号
GitHub Release标签
APP内置游戏资源
release-notes.txt
```

把新版本文件提交到新仓库 `main`：

1. 网页工作流自动部署；或在Actions中手动运行Pages工作流。
2. 运行 `Build and publish Android APK`。
3. 发布新的Release。
4. 旧APP检测到更高versionCode后弹窗更新。

始终使用同一包名 `com.jiuxiaowendao.game` 和同一签名密钥。

## 十一、验收清单

网页：

- `/VERSION.txt` 显示 `V2.0.10 CACHE102`
- Actions中build与deploy均为绿色
- Deployments只有新仓库自己的 `github-pages`

APP：

- 安装后游戏资源本地启动
- 华为手机可以登录并访问Supabase
- 右下角没有更新圆圈
- 没有新版本时不弹窗
- 发布更高versionCode测试版后能弹出更新询问
- 下载后能够进入系统安装确认

数据库：本版本无新增SQL，不执行任何迁移。

## 十二、V2.0.10 在线更新专项验收

1. 手机必须先安装同一签名的 V2.0.7 正式 Release APK。
2. 将本 V2.0.10 CACHE102 仓库内容提交到 main。
3. 网页工作流部署 V2.0.8。
4. 运行 `Build and publish Android APK`，默认发布 `v2.0.10-cache102`。
5. V2.0.8 APP 启动或回到前台后应检测到 versionCode 2001102，高于 V2.0.8 的 2000900，并弹窗询问更新。
6. 验收成功后，下一段对话可从 V2.0.10 CACHE102 客户端基线继续开发游戏内容。
