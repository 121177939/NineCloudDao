TwoPhoneRemote A/B GitHub 在线更新发布说明（v2.0.45）

仓库： https://github.com/121177939/NineCloudDao
目标目录： update/android/
默认分支： main

文件对应关系：
- 控制A.apk + update_a.json -> com.example.remotea（远程助手 A · 控制端）
- 控制B.apk + update_b.json -> com.example.remoteb（远程助手 B · 执行端）

首次上线步骤：
1. 先在 Android Studio 中构建 A/B 的正式 release APK。必须使用与设备上已安装版本完全相同的签名密钥；不能用 debug 签名覆盖正式版。
2. 在完整源码包根目录运行（把路径换成实际已签名 APK 的路径）：
   python3 tools/publish_android_update.py --apk-a "/path/to/signed-control-a.apk" --apk-b "/path/to/signed-control-b.apk"
   脚本会在源码根目录的 release/github_update/android/ 生成 APK 和带真实 SHA-256 的两个 JSON 清单；不会覆盖源码目录中的模板或版本校验清单。
3. 在 GitHub 的 main 分支创建 update/android/（如果尚不存在）。从 release/github_update/android/ 先上传 控制A.apk、控制B.apk。
4. 上传后先验证两个原始下载链接可以正常下载 APK，再从 release/github_update/android/ 上传 update_a.json、update_b.json。JSON 必须最后上传，避免客户端先读到新版本号但 APK 尚未完整发布。
5. 安装这版 v2.0.45 后，后续每次更新都把 A/B 的 versionName/versionCode 同步递增、重新构建并用脚本生成新 APK 和清单，再按第 3-4 步发布。

客户端在线地址：
- A 清单：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/update_a.json
- B 清单：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/update_b.json
- A APK：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/%E6%8E%A7%E5%88%B6A.apk
- B APK：https://raw.githubusercontent.com/121177939/NineCloudDao/main/update/android/%E6%8E%A7%E5%88%B6B.apk

重要限制：
- 当前 v2.0.43 旧 APK 尚未包含在线更新代码，所以第一次必须手动安装含在线更新器的新版（当前源码为 v2.0.45）；之后才会自动检查 GitHub 更新。
- 此目录中的 update_a.json / update_b.json 是模板，sha256 为空。正式发布仍建议运行脚本生成带真实 APK 哈希的清单；客户端同时兼容历史清单缺少/为空 SHA-256 的情况，但这会降低文件完整性校验保障。不要直接上传模板清单。
- 过渡注意：v2.0.44 已安装客户端仍要求有效 SHA-256，因此发布 v2.0.45 作为在线更新时，必须用发布脚本生成带真实哈希的 update_a.json / update_b.json；安装 v2.0.45 后，后续版本才兼容缺少/空 SHA-256 的清单。
- 更新采用 Android 系统安装界面，不会静默安装；首次安装更新时，Android 可能要求允许本应用安装未知应用。
- 本脚本只复制 APK 并生成清单，不负责签名。签名不一致时 Android 会拒绝覆盖安装。
- GitHub raw 地址只有在仓库文件上传到 main 分支后才可访问；本轮没有替用户向 GitHub 推送文件。


v2.0.46 测试提醒：本目录的 JSON 是空 SHA-256 兼容测试模板，不可直接作为正式发布清单；正式 APK 构建后运行 tools/publish_android_update.py 生成真实哈希，再先上传 APK、验证 raw 下载，最后上传 JSON。
