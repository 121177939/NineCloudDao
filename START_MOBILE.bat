@echo off
setlocal
cd /d "%~dp0"
title NineCloudDao - Mobile Test - Port 8787
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start-server.ps1" -Port 8787 -ConfigureFirewall
if errorlevel 1 pause
endlocal
