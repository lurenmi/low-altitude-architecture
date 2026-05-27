@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

if /I "%~1"=="-Static" (
  call start_static_preview.cmd
  exit /b %errorlevel%
)

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8090"

call start_fullstack.cmd %PORT%
exit /b %errorlevel%
