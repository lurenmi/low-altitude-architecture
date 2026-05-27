param(
  [int]$Port = 8090
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

Write-Host "[1/2] 初始化数据库..."
python .\backend\init_db.py
if ($LASTEXITCODE -ne 0) {
  Write-Host "数据库初始化失败"
  exit 1
}

Write-Host "[2/2] 启动平台服务: http://localhost:$Port"
python .\backend\api_server.py --port $Port
