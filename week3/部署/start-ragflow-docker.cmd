@echo off
setlocal

cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-RAGFlow-Docker.ps1" %*

if errorlevel 1 (
  echo.
  echo RAGFlow Docker startup failed. See the messages above.
  pause
  exit /b %errorlevel%
)

echo.
echo Press any key to close this window. RAGFlow keeps running in Docker.
pause >nul
