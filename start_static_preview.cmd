@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

set "PY_CMD="
where python >nul 2>nul && set "PY_CMD=python"
if "%PY_CMD%"=="" (
  where py >nul 2>nul && set "PY_CMD=py -3"
)

if "%PY_CMD%"=="" (
  echo [ERROR] Python not found. Please install Python 3 first.
  pause
  exit /b 1
)

echo Static preview at http://localhost:5173/
call %PY_CMD% -m http.server 5173 --directory "%cd%"

endlocal
