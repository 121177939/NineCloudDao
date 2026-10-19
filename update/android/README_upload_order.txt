TwoPhoneRemote A/B GitHub 在线更新发布说明（v2.0.46）

仓库：https://github.com/121177939/NineCloudDao
目标目录：update/android/
默认分支：main

文件对应关系：
- 控制A.apk + update_a.json -> com.example.remotea（远程助手 A · 控制端）
- 控制B.apk + update_b.json -> com.example.remoteb（远程助手 B · 执行端）

重要：`update_a.json` 和 `update_b.json` 已经直接放在完整源码包的 `update/android/` 目录里。**正常发布不需要生成 JSON 清单，也不必运行发布脚本。** 直接编辑这两个现成文件，再上传即可。`tools/publish_android_update.py` 仅作为可选辅助工具保留。

每次发布步骤：
1. 在 Android Studio 中分别构建 A/B 正式 release APK。必须使用与设备上已安装版本兼容的签名密钥；不能用 debug 签名覆盖正式版。
2. 将生成的 APK 文件名改为 `控制A.apk`、`控制B.apk`。
3. 直接编辑本目录已有的 `update_a.json`、`update_b.json`：同步更新 `versionName`、`versionCode`、`apkUrl`、`description`；`applicationId` 保持 A=`com.example.remotea`、B=`com.example.remoteb`。本版客户端允许 `sha256` 缺失或为空，但这会跳过文件哈希校验；若填写非空值，必须是 APK 的真实 64 位 SHA-256，否则更新会被拒绝。
4. 在 GitHub 的 `main/update/android/` 目录先上传 `控制A.apk`、`控制B.apk`。确认两个 raw APK 链接可正常下载后，再上传编辑好的 `update_a.json`、`update_b.json`。JSON 必须最后上传，避免客户端先读到新版本号而 APK 尚未完整发布。
5. 在设备上打开带在线更新器的应用，确认弹出新版本提示，下载后由 Android 系统显示安装确认。

客户端在线地址：
- A 清单：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/update_a.json
- B 清单：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/update_b.json
- A APK：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/%E6%8E%A7%E5%88%B6A.apk
- B APK：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/%E6%8E%A7%E5%88%B6B.apk

版本兼容边界：
- v2.0.45 及更新版本：可接受清单缺少/空白 SHA-256，但会跳过哈希校验；仍校验 APK 包名和版本号。
- v2.0.44：仍要求有效 SHA-256；若要从 v2.0.44 在线升级，清单必须填入实际 APK 哈希。
- v2.0.43 及更早：没有在线更新代码，首次必须手动安装含在线更新器的新版。
- 更新使用 Android 系统安装界面，不会静默安装；首次可能需要允许本应用安装未知应用。
- GitHub raw 地址只有在文件上传到 main 分支后才可访问；本轮没有替用户向 GitHub 推送文件。

可选工具说明：`tools/publish_android_update.py` 可以从已签名 APK 复制文件并生成含真实 SHA-256 的清单，但不是发布必需步骤；若按用户现有习惯直接维护源码包内的 JSON，请不要运行该脚本。
