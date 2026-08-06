# 九霄问道 V2.0.3 CACHE95

构建号：`v2-0-3-cache95-equipment-worldnews3-schemafix1-pagesactions1`。

本包恢复项目在CACHE91使用的GitHub Pages Actions双作业部署：build构建 `.pages-site`，deploy发布唯一的 `github-pages` Artifact。

上传前请删除仓库中其他Pages部署工作流，只保留 `.github/workflows/deploy-pages.yml`；然后在 `Settings → Pages → Build and deployment → Source` 选择 **GitHub Actions**。不要再使用 `Deploy from a branch`。

数据库顺序：SQL229 → 部署并确认V2.0.3 → SQL230 → SQL231。
