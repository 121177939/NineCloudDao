TwoPhoneRemote A/B GitHub 在线更新发布说明（v2.0.47）

仓库：https://github.com/121177939/NineCloudDao
目标目录：update/android/
默认分支：main

文件对应关系：
- 控制A.apk + update_a.json -> com.example.remotea（控制 A）
- 控制B.apk + update_b.json -> com.example.remoteb（控制 B）

**强制要求：每个交付的完整源码包都必须包含 `update/android/update_a.json` 和 `update/android/update_b.json`，两份都必须与 A/B Gradle 的版本号同步；严禁漏包或只更新其中一份。**

每次发布步骤：
1. 在 Android Studio 分别构建 A/B 正式 release APK，必须使用与设备现有安装版本兼容的签名密钥。
2. 将 APK 命名为 `控制A.apk`、`控制B.apk`。
3. 直接编辑本目录现有 `update_a.json` 和 `update_b.json`，同步更新 `versionName`、`versionCode`、`description`、对应 `apkUrl`；`applicationId` 保持不变。不要运行生成脚本也可以完成发布。
4. 先上传两个 APK 到 GitHub 的 `main/update/android/` 并确认 raw 链接可下载；再最后上传两份 JSON。源码内 JSON 不会自动推送到 GitHub。
5. 应用内检查更新、下载后由 Android 系统安装器确认。

远端地址：
- A 清单：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/update_a.json
- B 清单：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/update_b.json
- A APK：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/%E6%8E%A7%E5%88%B6A.apk
- B APK：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/%E6%8E%A7%E5%88%B6B.apk

SHA-256 规则：v2.0.45 及之后的更新器接受缺失/空白 sha256，但会跳过哈希校验；仍核对 APK 包名、versionCode、versionName。非空哈希格式错误或与 APK 不匹配时拒绝安装。正式发布建议填真实 SHA-256。v2.0.44 仍要求有效哈希；v2.0.43 及更早没有更新器，首次需手动安装。

可选工具 `tools/publish_android_update.py` 仅作辅助；按既有流程直接维护源码内 JSON 即可。
