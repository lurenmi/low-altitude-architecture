$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $base '按省份低空侦测中标项目CSV_2023-2026'
$mainPath = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_全量汇总.csv'
$classifiedPath = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_按需求分类.csv'
$longPath = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_设备明细长表.csv'

$projects = Import-Csv -LiteralPath $mainPath
$classified = Import-Csv -LiteralPath $classifiedPath
$long = Import-Csv -LiteralPath $longPath

function To-Amount($v) {
  if ([string]::IsNullOrWhiteSpace($v)) { return $null }
  $s = "$v".Trim()
  $n = 0.0
  if ([double]::TryParse($s, [ref]$n)) { return $n }
  return $null
}

function Count-Where($rows, [scriptblock]$predicate) {
  return @($rows | Where-Object $predicate).Count
}

function Sum-Amount($rows) {
  $sum = 0.0
  $count = 0
  foreach ($row in $rows) {
    $amount = To-Amount $row.金额万元
    if ($null -ne $amount) {
      $sum += $amount
      $count++
    }
  }
  return [pscustomobject]@{ Count = $count; Sum = [math]::Round($sum, 4) }
}

$provinceSummary = foreach ($group in ($projects | Group-Object 省份 | Sort-Object -Property Count -Descending)) {
  $rows = @($group.Group)
  $amount = Sum-Amount $rows
  [pscustomobject]@{
    省份 = $group.Name
    中标项目数 = $rows.Count
    完整记录数 = Count-Where $rows { $_.字段完整度 -eq '完整' }
    较完整记录数 = Count-Where $rows { $_.字段完整度 -eq '较完整' }
    待复核记录数 = Count-Where $rows { $_.字段完整度 -eq '待复核' }
    官方来源记录数 = Count-Where $rows { $_.来源等级 -match '^A-' }
    可解析金额项目数 = $amount.Count
    可解析金额合计万元 = $amount.Sum
    设备明细较完整项目数 = Count-Where $rows { $_.设备明细完整度 -eq '明细较完整' }
    设备部分明细项目数 = Count-Where $rows { $_.设备明细完整度 -eq '部分明细' }
    设备仅项目级推断项目数 = Count-Where $rows { $_.设备明细完整度 -eq '仅项目级推断' }
  }
}
$provinceSummary | Export-Csv -LiteralPath (Join-Path $outDir '省份汇总统计_2023-2026.csv') -NoTypeInformation -Encoding UTF8

$demandSummary = foreach ($group in ($classified | Group-Object 主需求类别 | Sort-Object -Property Count -Descending)) {
  if ([string]::IsNullOrWhiteSpace($group.Name)) { continue }
  $rows = @($group.Group)
  $amount = Sum-Amount $rows
  $topProvince = ($rows | Group-Object 省份 | Sort-Object -Property Count -Descending | Select-Object -First 5 | ForEach-Object { "$($_.Name)($($_.Count))" }) -join '、'
  [pscustomobject]@{
    需求类别 = $group.Name
    项目数 = $rows.Count
    官方来源记录数 = Count-Where $rows { $_.来源等级 -match '^A-' }
    可解析金额项目数 = $amount.Count
    可解析金额合计万元 = $amount.Sum
    主要省份 = $topProvince
  }
}
$demandSummary | Export-Csv -LiteralPath (Join-Path $outDir '需求类别汇总统计_2023-2026.csv') -NoTypeInformation -Encoding UTF8

$equipmentSummary = foreach ($group in ($long | Group-Object 设备类型 | Sort-Object -Property Count -Descending)) {
  if ([string]::IsNullOrWhiteSpace($group.Name)) { continue }
  [pscustomobject]@{
    设备类型 = $group.Name
    明细行数 = $group.Count
    涉及项目数 = @($group.Group | Select-Object -ExpandProperty 项目ID -Unique).Count
  }
}
$equipmentSummary | Export-Csv -LiteralPath (Join-Path $outDir '设备类型汇总统计_2023-2026.csv') -NoTypeInformation -Encoding UTF8

$softSummary = foreach ($group in ($classified | Group-Object 软硬件属性 | Sort-Object -Property Count -Descending)) {
  [pscustomobject]@{
    软硬件属性 = $group.Name
    项目数 = $group.Count
  }
}
$softSummary | Export-Csv -LiteralPath (Join-Path $outDir '软硬件属性汇总统计_2023-2026.csv') -NoTypeInformation -Encoding UTF8

$detailSummary = foreach ($group in ($projects | Group-Object 设备明细完整度 | Sort-Object -Property Count -Descending)) {
  [pscustomobject]@{
    设备明细完整度 = $group.Name
    项目数 = $group.Count
  }
}
$detailSummary | Export-Csv -LiteralPath (Join-Path $outDir '设备明细完整度统计_2023-2026.csv') -NoTypeInformation -Encoding UTF8

$confidenceSummary = foreach ($group in ($long | Group-Object 明细置信度 | Sort-Object -Property Count -Descending)) {
  [pscustomobject]@{
    明细置信度 = $group.Name
    明细行数 = $group.Count
  }
}
$confidenceSummary | Export-Csv -LiteralPath (Join-Path $outDir '设备明细置信度统计_2023-2026.csv') -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
  项目数 = $projects.Count
  可解析金额项目数 = (Sum-Amount $projects).Count
  可解析金额合计万元 = (Sum-Amount $projects).Sum
  省份数 = @($projects | Group-Object 省份).Count
  设备明细行 = $long.Count
}
