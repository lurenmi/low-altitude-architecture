param(
  [int]$Port = 8096
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Get-PythonCommand {
  $python = Get-Command python -ErrorAction SilentlyContinue
  if ($python) {
    return @{ Exe = $python.Source; Prefix = @() }
  }
  $py = Get-Command py -ErrorAction SilentlyContinue
  if ($py) {
    return @{ Exe = $py.Source; Prefix = @("-3") }
  }
  throw "Python not found. Please install Python 3."
}

function Add-Check([System.Collections.Generic.List[object]]$List, [string]$Name, [bool]$Passed, [string]$Detail) {
  $List.Add([pscustomobject]@{
    Name = $Name
    Passed = $Passed
    Detail = $Detail
  }) | Out-Null
}

function Invoke-JsonGet([string]$Url) {
  return Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 20
}

function Invoke-JsonPost([string]$Url, [hashtable]$Body) {
  $json = $Body | ConvertTo-Json -Depth 10
  return Invoke-RestMethod -Uri $Url -Method Post -ContentType "application/json" -Body $json -TimeoutSec 20
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$pyCmd = Get-PythonCommand

Write-Host "[1/4] Initialize database..."
& $pyCmd.Exe @($pyCmd.Prefix + @("la_platform\backend\init_db.py"))
if ($LASTEXITCODE -ne 0) {
  throw "Database initialization failed."
}

Write-Host "[2/4] Start service and wait for health..."
$proc = Start-Process -FilePath $pyCmd.Exe -ArgumentList @($pyCmd.Prefix + @("la_platform\backend\api_server.py", "--port", "$Port")) -PassThru -WindowStyle Hidden
try {
  $base = "http://127.0.0.1:$Port"
  $ready = $false
  for ($i = 0; $i -lt 40; $i++) {
    try {
      $health = Invoke-JsonGet "$base/api/health"
      if ($health.ok -eq $true) {
        $ready = $true
        break
      }
    } catch {}
    Start-Sleep -Milliseconds 500
  }
  if (-not $ready) {
    throw "Service failed to start on port $Port."
  }

  Write-Host "[3/4] Run API and page structure checks..."

  $health = Invoke-JsonGet "$base/api/health"
  Add-Check $checks "Health" ($health.ok -eq $true) "ok=$($health.ok)"

  $mapSummary = Invoke-JsonGet "$base/api/v1/map/summary"
  Add-Check $checks "Map Summary" ($mapSummary.summary.routes -ge 1) "routes=$($mapSummary.summary.routes)"

  $mapLayers = Invoke-JsonGet "$base/api/v1/map/layers"
  Add-Check $checks "Map Layers" (($mapLayers.items | Measure-Object).Count -ge 3) "layers=$(($mapLayers.items | Measure-Object).Count)"

  $mapObjects = Invoke-JsonGet "$base/api/v1/map/objects"
  Add-Check $checks "Map Objects" (($mapObjects.items | Measure-Object).Count -ge 1) "objects=$(($mapObjects.items | Measure-Object).Count)"

  $plans = Invoke-JsonGet "$base/api/v1/flight/plans"
  $planCount = ($plans.items | Measure-Object).Count
  Add-Check $checks "Flight Plans" ($planCount -ge 1) "plans=$planCount"

  $rules = Invoke-JsonGet "$base/api/v1/flight/approval-rules"
  $hasRules = ($rules.active_rule -ne $null) -and ($rules.active_rule.config -ne $null)
  Add-Check $checks "Approval Rules" $hasRules "rule_code=$($rules.active_rule.rule_code)"

  if ($planCount -ge 1) {
    $planId = [int]$plans.items[0].id
    $risk = Invoke-JsonPost "$base/api/v1/flight/plans/$planId/risk-check" @{}
    Add-Check $checks "Risk Check" ($risk.ok -eq $true) "plan_id=$planId risk_level=$($risk.risk_level)"

    $replay = Invoke-JsonGet "$base/api/v1/flight/plans/$planId/replay"
    $points = ($replay.points | Measure-Object).Count
    Add-Check $checks "Replay Load" ($points -ge 1) "plan_id=$planId points=$points"

    $regen = Invoke-JsonPost "$base/api/v1/flight/plans/$planId/replay/generate" @{}
    Add-Check $checks "Replay Regenerate" ($regen.ok -eq $true) "generated=$($regen.generated_points)"
  } else {
    Add-Check $checks "Risk Check" $false "no plan available"
    Add-Check $checks "Replay Load" $false "no plan available"
    Add-Check $checks "Replay Regenerate" $false "no plan available"
  }

  $visual = Invoke-JsonGet "$base/api/v1/airspace/visualization"
  $zones = ($visual.zones | Measure-Object).Count
  $grids = ($visual.grids | Measure-Object).Count
  $facilities = ($visual.facilities | Measure-Object).Count
  $weather = ($visual.weather | Measure-Object).Count
  Add-Check $checks "Airspace Visualization" (($zones -ge 1) -and ($grids -ge 1) -and ($facilities -ge 1) -and ($weather -ge 1)) "zones=$zones grids=$grids facilities=$facilities weather=$weather"

  $capacity = Invoke-JsonGet "$base/api/v1/airspace/capacity"
  $capOk = $capacity.capacity -ne $null -and $capacity.capacity.occupancy_percent -ne $null
  Add-Check $checks "Airspace Capacity" $capOk "occupancy=$($capacity.capacity.occupancy_percent)%"

  $homeHtml = Invoke-WebRequest -Uri "$base/" -Method Get -TimeoutSec 20 -UseBasicParsing
  $htmlOk = ($homeHtml.Content -match 'id="map-canvas"') -and ($homeHtml.Content -match 'id="plan-form"') -and ($homeHtml.Content -match 'id="airspace-canvas"')
  Add-Check $checks "Page Structure" $htmlOk "map-canvas + plan-form + airspace-canvas"

  $appJs = Invoke-WebRequest -Uri "$base/app.js" -Method Get -TimeoutSec 20 -UseBasicParsing
  $jsOk = ($appJs.Content -match "ensurePopupNode") -and ($appJs.Content -match "WebGLRenderer") -and ($appJs.Content -match "replay-generate")
  Add-Check $checks "Frontend Logic Hooks" $jsOk "popup + 3D + replay controls"

  Write-Host "[4/4] Print check results..."
  foreach ($item in $checks) {
    $tag = if ($item.Passed) { "PASS" } else { "FAIL" }
    Write-Host ("[{0}] {1} => {2}" -f $tag, $item.Name, $item.Detail)
  }

  $failed = @($checks | Where-Object { -not $_.Passed })
  $passedCount = @($checks | Where-Object { $_.Passed }).Count
  Write-Host ""
  Write-Host ("SUMMARY: {0}/{1} checks passed." -f $passedCount, $checks.Count)
  if ($failed.Count -gt 0) {
    exit 1
  }
  exit 0
}
finally {
  if ($proc -and -not $proc.HasExited) {
    Stop-Process -Id $proc.Id -Force
  }
}
