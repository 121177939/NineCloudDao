# GitHub Desktop 更新到 V0.6.6

## 更新前

1. 先复制当前 GitHub 仓库目录作为本地备份。
2. 打开 GitHub Desktop，确认仓库为 `NineCloudDao`、分支为 `main`。
3. 点击 `Fetch origin`；如果出现 `Pull origin`，先点击并等待完成。

## 覆盖文件并发布

1. 解压 `NineCloudDao_GitHub_Upload_V0.6.6.zip`。
2. 进入能直接看到 `index.html`、`app.js` 和 `release_config.json` 的文件夹。
3. 在 GitHub Desktop 中点击 `Repository` → `Show in Explorer`。
4. 把更新包内全部文件复制到仓库根目录，选择“替换目标中的文件”。
5. 回到 GitHub Desktop，确认变更中包含 V0.6.6 文件，不包含 `.env`、数据库密码或其他私密文件。
6. Summary 填写：`Update game to V0.6.6`。
7. 点击 `Commit to main`，再点击 `Push origin`。
8. 打开仓库的 `Actions` 页面，等待部署工作流显示绿色对勾。
9. 打开 `https://121177939.github.io/NineCloudDao/?v=066`，确认页脚显示 `Web Alpha 0.6.6`。

## 本版数据库要求

本版不需要执行 Supabase SQL。数据库仍保持 40 张公共业务表、23 个数据库函数。
