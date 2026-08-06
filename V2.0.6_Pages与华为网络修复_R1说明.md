# V2.0.6 CACHE98：Pages与华为网络修复基线

本版本继承V2.0.5 R2已经完成的两项修复，并使用新的正式版本号重新发布：

1. 网页仍使用同一仓库、同一GitHub Actions Pages Artifact流程。工作流在新部署前清理旧的卡住部署，并校验Pages发布源为GitHub Actions。
2. Android本地资源继续通过Supabase域的WebViewAssetLoader同源映射运行，保留华为/EMUI网络兼容处理。
3. APP没有右下角浮动按钮。只有检测到更高versionCode时，才弹出“发现新版本，是否立即更新”。
4. 当前APP版本：`2.0.6-cache98`（`2000698`），默认Release标签：`v2.0.6-cache98`。
5. 游戏玩法、GM与数据库均未修改，不需要执行SQL。
