param(
  [string]$Alias = "jiuxiao",
  [string]$Keystore = "jiuxiao-release.keystore"
)
Write-Host "将创建永久发布签名。请妥善保存，丢失后无法覆盖更新已安装APP。"
keytool -genkeypair -v -keystore $Keystore -alias $Alias -keyalg RSA -keysize 4096 -validity 10000
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path $Keystore)))
$base64 | Set-Content -NoNewline ANDROID_KEYSTORE_BASE64.txt
Write-Host "已生成 $Keystore 和 ANDROID_KEYSTORE_BASE64.txt。"
Write-Host "把Base64内容填入GitHub Secret ANDROID_KEYSTORE_BASE64，并另外配置别名与两个密码。"
