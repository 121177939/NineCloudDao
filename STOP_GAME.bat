@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$ids=@(Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique); foreach($id in $ids){ try{$p=Get-CimInstance Win32_Process -Filter ('ProcessId = '+$id); if($p.CommandLine -match 'start-server\.ps1|static-server\.ps1|NineCloudDao_Game_V0\.'){Stop-Process -Id $id -Force -ErrorAction SilentlyContinue}}catch{}}"
echo NineCloudDao server on port 8787 was stopped if it was running.
timeout /t 2 >nul
endlocal
