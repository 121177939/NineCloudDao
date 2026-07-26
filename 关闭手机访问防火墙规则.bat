@echo off
setlocal
net session >nul 2>&1
if not "%errorlevel%"=="0" (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
netsh.exe advfirewall firewall delete rule name="NineCloudDao Mobile Test" >nul 2>&1
echo Mobile test firewall rule removed.
timeout /t 2 >nul
endlocal
