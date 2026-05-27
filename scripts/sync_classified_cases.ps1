$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $base '按省份低空侦测中标项目CSV_2023-2026'
$mainPath = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_全量汇总.csv'
$classifiedPath = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_按需求分类.csv'

function CleanText([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '' }
  return (($s -replace '\s+', '').Trim())
}

function GetPrimaryDemand($row) {
  $text = "$($row.项目名称) $($row.发包采购单位) $($row.证据摘要)"
  if ($text -match '机场|机场公安|监狱|电厂|核电|石化|水库|边境|铁路|港口|机场管理') { return '敏感目标防护需求' }
  if ($text -match '示范基地|园区|基地|平台|管理服务|应用集成|数字警务|智能管控|综合管理|空域管理|飞行应用|态势感知|巡检|警务|警戒|实战|防御|低空安全') { return '日常巡防需求' }
  if ($text -match '物流|起降点|运营|共建|共享') { return '园区运营需求' }
  return '日常巡防需求'
}

function GetCompatibleDemand($row) {
  $text = "$($row.项目名称) $($row.发包采购单位)"
  if ($text -match '机场|监狱|电厂|核电|石化|水库|边境|铁路|港口') { return '敏感目标防护需求' }
  if ($text -match '园区|基地|运营|共建|共享') { return '园区运营需求' }
  return '无明显兼具类别'
}

function GetHardwareAttr($row) {
  $text = "$($row.项目名称) $($row.项目类型) $($row.承建中标单位) $($row.证据摘要)"
  if ($text -match '服务|租赁') { return '服务类/软硬件结合' }
  if ($text -match '平台|系统|建设|应用|管理|管控|实战|警务|防御|巡防') { return '软硬件综合/系统平台' }
  return '硬件设备/装备'
}

function GetClassNote($row) {
  $text = "$($row.项目名称) $($row.证据摘要)"
  if ($text -match '机场|监狱|核电|电厂|石化') { return '高优先级敏感目标或场景样本' }
  if ($text -match '平台|管理服务|应用集成|数字警务|智能管控|态势感知') { return '平台型低空治理/警务样本' }
  if ($text -match '服务|租赁') { return '服务/租赁型样本' }
  return '项目名称深度检索补入'
}

$mainRows = @(Import-Csv -LiteralPath $mainPath)
$classifiedRows = @(Import-Csv -LiteralPath $classifiedPath)

$mainMap = @{}
foreach ($row in $mainRows) {
  $key = CleanText $row.项目名称
  if ($key) { $mainMap[$key] = $row }
}

$result = New-Object System.Collections.Generic.List[object]
$seen = @{}

foreach ($row in $classifiedRows) {
  $key = CleanText $row.项目名称
  if (-not $key) { continue }
  if ($mainMap.ContainsKey($key)) {
    $src = $mainMap[$key]
    $row.项目ID = $src.项目ID
    $row.省份 = $src.省份
    $row.省内城市区域 = $src.省内城市区域
    $row.项目名称 = $src.项目名称
    $row.项目类型 = $src.项目类型
    $row.项目阶段 = $src.项目阶段
    $row.是否直接侦测反制相关 = $src.是否直接侦测反制相关
    $row.发包采购单位 = $src.发包采购单位
    $row.项目金额 = $src.项目金额
    $row.金额万元 = $src.金额万元
    $row.承建中标单位 = $src.承建中标单位
    $row.中标公告时间 = $src.中标公告时间
    $row.年份 = $src.年份
    $row.来源等级 = $src.来源等级
    $row.字段完整度 = $src.字段完整度
    $row.来源链接 = $src.来源链接
    $row.证据摘要 = $src.证据摘要
    $row.核验备注 = $src.核验备注
    foreach ($col in @('设备名称清单','设备类型清单','设备数量清单','设备规格型号清单','设备品牌清单','设备明细完整度','设备明细来源','设备明细备注')) {
      if ($row.PSObject.Properties.Name -contains $col) {
        $row.$col = $src.$col
      }
    }
  }
  [void]$result.Add($row)
  $seen[$key] = $true
}

foreach ($row in $mainRows) {
  $key = CleanText $row.项目名称
  if (-not $key -or $seen.ContainsKey($key)) { continue }
  $classRow = [ordered]@{
    主需求类别 = GetPrimaryDemand $row
    兼具需求类别 = GetCompatibleDemand $row
    软硬件属性 = GetHardwareAttr $row
    分类依据 = GetClassNote $row
    分类置信度 = if ($row.来源等级 -match '^A') { '高' } else { '中' }
    项目ID = $row.项目ID
    省份 = $row.省份
    省内城市区域 = $row.省内城市区域
    项目名称 = $row.项目名称
    项目类型 = $row.项目类型
    项目阶段 = $row.项目阶段
    是否直接侦测反制相关 = $row.是否直接侦测反制相关
    发包采购单位 = $row.发包采购单位
    项目金额 = $row.项目金额
    金额万元 = $row.金额万元
    承建中标单位 = $row.承建中标单位
    中标公告时间 = $row.中标公告时间
    年份 = $row.年份
    来源等级 = $row.来源等级
    字段完整度 = $row.字段完整度
    来源链接 = $row.来源链接
    证据摘要 = $row.证据摘要
    核验备注 = $row.核验备注
    设备名称清单 = $row.设备名称清单
    设备类型清单 = $row.设备类型清单
    设备数量清单 = $row.设备数量清单
    设备规格型号清单 = $row.设备规格型号清单
    设备品牌清单 = $row.设备品牌清单
    设备明细完整度 = $row.设备明细完整度
    设备明细来源 = $row.设备明细来源
    设备明细备注 = $row.设备明细备注
  }
  [void]$result.Add([pscustomobject]$classRow)
}

$result | Export-Csv -LiteralPath $classifiedPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
  主库行数 = $mainRows.Count
  分类表行数 = $result.Count
  新增补齐行数 = ($result.Count - $classifiedRows.Count)
}
