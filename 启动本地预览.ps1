param(
  [int]$Port = 8090,
  [switch]$Static
)

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

if (-not $Static) {
  Write-Host "Starting full-stack app at http://localhost:$Port/"
  if (-not (Test-Path ".\start_fullstack.cmd")) {
    Write-Host "Missing start_fullstack.cmd in project root."
    exit 1
  }
  & .\start_fullstack.cmd $Port
  exit
}

Write-Host "Starting static preview at http://localhost:5173/"
if (-not (Test-Path ".\start_static_preview.cmd")) {
  Write-Host "Missing start_static_preview.cmd in project root."
  exit 1
}
& .\start_static_preview.cmd
