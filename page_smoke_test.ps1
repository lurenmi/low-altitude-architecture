param(
  [int]$Port = 8091,
  [int]$DebugPort = 9222
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path $Edge)) {
  throw "Edge not found at $Edge"
}

$shot = Join-Path $Root "page_smoke_airspace.png"
if (Test-Path $shot) { Remove-Item $shot -Force }

$args = @(
  "--headless=new",
  "--disable-gpu",
  "--no-first-run",
  "--no-default-browser-check",
  "--user-data-dir=$env:TEMP\edge-cdp-smoke",
  "--remote-debugging-address=127.0.0.1",
  "--remote-debugging-port=$DebugPort",
  "--remote-allow-origins=*",
  "--window-size=1920,1080",
  "http://127.0.0.1:$Port/"
)

$proc = Start-Process -FilePath $Edge -ArgumentList $args -PassThru -WindowStyle Hidden
try {
  Start-Sleep -Seconds 3
  $version = $null
  for ($i = 0; $i -lt 20; $i++) {
    try {
      $version = Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/version"
      break
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  if (-not $version) {
    throw "Could not reach Edge DevTools on port $DebugPort"
  }

  $ws = [System.Net.WebSockets.ClientWebSocket]::new()
  try { $ws.Options.Proxy = $null } catch {}
  try { $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(15) } catch {}
  try { $ws.Options.SetRequestHeader("Origin", "http://127.0.0.1:$DebugPort") } catch {}
  $targets = $null
  for ($i = 0; $i -lt 20; $i++) {
    try {
      $targets = Invoke-RestMethod "http://127.0.0.1:$DebugPort/json/list"
      break
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }
  $targetWs = $targets | Where-Object { $_.type -eq "page" } | Select-Object -First 1
  if (-not $targetWs) {
    $targetWs = $targets | Select-Object -First 1
  }
  if (-not $targetWs) {
    $targetWs = @{ webSocketDebuggerUrl = $version.webSocketDebuggerUrl }
  }
  $wsUrl = $targetWs.webSocketDebuggerUrl
  $ws.ConnectAsync([Uri]$wsUrl, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
  $msgId = 0

  function Send-Command {
    param(
      [string]$Method,
      [hashtable]$Params = @{}
    )
    $script:msgId++
    $payload = @{
      id = $script:msgId
      method = $Method
      params = $Params
    } | ConvertTo-Json -Depth 20 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $seg = [System.ArraySegment[byte]]::new($bytes)
    $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult() | Out-Null
    return $script:msgId
  }

  function Receive-Message {
    $buffer = New-Object byte[] 65536
    $segments = New-Object System.Collections.Generic.List[byte]
    do {
      $seg = [System.ArraySegment[byte]]::new($buffer)
      $result = $ws.ReceiveAsync($seg, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
      if ($result.Count -gt 0) {
        for ($i = 0; $i -lt $result.Count; $i++) { $segments.Add($buffer[$i]) }
      }
    } while (-not $result.EndOfMessage)
    $json = [System.Text.Encoding]::UTF8.GetString($segments.ToArray())
    return $json | ConvertFrom-Json
  }

  Send-Command "Page.enable" | Out-Null
  Send-Command "Runtime.enable" | Out-Null
  Send-Command "Page.navigate" @{ url = "http://127.0.0.1:$Port/" } | Out-Null

  $loaded = $false
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline -and -not $loaded) {
    $msg = Receive-Message
    if ($msg.method -eq "Page.loadEventFired") {
      $loaded = $true
    }
  }

  Send-Command "Runtime.evaluate" @{
    expression = "document.querySelector('.tab[data-tab=""airspace""]').click(); 'ok';"
    awaitPromise = $false
    returnByValue = $true
  } | Out-Null

  Start-Sleep -Seconds 2

  $result = Send-Command "Runtime.evaluate" @{
    expression = @'
(() => {
  const pick = (sel) => document.querySelector(sel);
  return JSON.stringify({
    title: document.title,
    mapSummary: pick('#map-summary') ? pick('#map-summary').textContent.trim() : '',
    planRows: document.querySelectorAll('#plan-table tr').length,
    airspaceZones: document.querySelectorAll('#zone-table tr').length,
    airspaceGrids: document.querySelectorAll('#grid-table tr').length,
    airspaceFacilities: document.querySelectorAll('#facility-table tr').length,
    airCanvas: !!pick('#airspace-canvas'),
    airCanvasInner: pick('#airspace-canvas') ? pick('#airspace-canvas').innerHTML.slice(0, 120) : '',
    popupText: pick('#airspace-popup') ? pick('#airspace-popup').textContent.trim() : ''
  });
})()
'@
    returnByValue = $true
  }

  $reply = Receive-Message
  $payload = $reply.result.result.value | ConvertFrom-Json

  Send-Command "Page.captureScreenshot" @{
    format = "png"
    captureBeyondViewport = $true
  } | Out-Null
  $shotReply = Receive-Message
  [IO.File]::WriteAllBytes($shot, [Convert]::FromBase64String($shotReply.result.data))

  Write-Host ("PAGE_TITLE=" + $payload.title)
  Write-Host ("MAP_SUMMARY=" + $payload.mapSummary)
  Write-Host ("PLAN_ROWS=" + $payload.planRows)
  Write-Host ("AIRSPACE_ZONES=" + $payload.airspaceZones)
  Write-Host ("AIRSPACE_GRIDS=" + $payload.airspaceGrids)
  Write-Host ("AIRSPACE_FACILITIES=" + $payload.airspaceFacilities)
  Write-Host ("AIR_CANVAS_PRESENT=" + $payload.airCanvas)
  Write-Host ("AIR_POPUP_TEXT=" + $payload.popupText)
  Write-Host ("SCREENSHOT=" + $shot)
}
finally {
  if ($proc -and -not $proc.HasExited) {
    $proc.Kill()
  }
}
