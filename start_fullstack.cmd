@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"

set "PORT=%~1"
if "%PORT%"=="" set "PORT=8090"

set "PY_CMD="
where python >nul 2>nul && set "PY_CMD=python"
if "%PY_CMD%"=="" (
  where py >nul 2>nul && set "PY_CMD=py -3"
)

if "%PY_CMD%"=="" (
  echo [ERROR] Python not found. Please install Python 3 first.
  echo [TIP] You can install from https://www.python.org/downloads/
  exit /b 1
)

echo [1/2] Init database...
call %PY_CMD% la_platform\backend\init_db.py
if not %errorlevel%==0 (
  echo [ERROR] Database init failed.
  exit /b 1
)

echo [2/2] Start server at http://localhost:%PORT%/
call %PY_CMD% la_platform\backend\api_server.py --port %PORT%

endlocal
