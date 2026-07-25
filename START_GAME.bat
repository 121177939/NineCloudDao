@echo off
setlocal
cd /d "%~dp0"
title NineCloudDao - Computer - Port 8787
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start-server.ps1" -Port 8787 -LocalOnly
if errorlevel 1 pause
endlocal
