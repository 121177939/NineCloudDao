# GitHub Desktop 更新到 V0.12.0 FIX1

1. 先在Supabase执行FIX1预检查、主SQL和检查SQL，确认27项全部PASS。
2. 解压 `NineCloudDao_GitHub_Upload_V0.12.0_FIX1.zip`。
3. 将解压后的全部文件覆盖到本地GitHub仓库根目录。
4. 在GitHub Desktop中确认旧的V0.12.0初稿SQL已被删除，新的 `202607260830_v0120_fix1_*` 文件已经出现。
5. Commit summary填写：`Upgrade market casino to V0.12.0 FIX1`。
6. Push origin，等待GitHub Actions成功。
7. 关闭旧PWA，重新访问 `?v=0120fix1`。
