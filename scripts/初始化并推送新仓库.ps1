param(
  [Parameter(Mandatory=$true)][string]$RepositoryUrl
)
$ErrorActionPreference = "Stop"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "未找到git。请先安装GitHub Desktop或Git for Windows。"
}
Set-Location (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path ".git")) { git init }
git add .
$changes = git status --porcelain
if ($changes) { git commit -m "Initial clean V2.0.7 CACHE99 repository" }
git branch -M main
$remote = git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0) { git remote set-url origin $RepositoryUrl } else { git remote add origin $RepositoryUrl }
git push -u origin main
Write-Host "上传完成。下一步：GitHub仓库 Settings -> Pages -> Source -> GitHub Actions"
