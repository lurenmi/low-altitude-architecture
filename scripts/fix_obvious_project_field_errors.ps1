$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $base '按省份低空侦测中标项目CSV_2023-2026'

$corrections = @{
  'LA-2026-0078' = @{
    '省内城市区域' = '西安咸阳'
    '项目名称' = '西安咸阳国际机场股份有限公司无人机反制车租赁项目'
    '发包采购单位' = '西安咸阳国际机场股份有限公司'
    '承建中标单位' = '公开信息未披露'
    '证据摘要' = '采招网转载结果公示显示：西安咸阳国际机场股份有限公司无人机反制车租赁项目，发布时间2026年1月5日；公开摘要未披露中标单位和金额。'
    '核验备注' = '修正：原承建中标单位字段误入“中国采招网于2026年01月05日发布...”平台发布语，已改为公开信息未披露'
  }
  'LA-2026-0024' = @{
    '项目名称' = '贵阳市公安局无人机反制设备采购项目'
    '发包采购单位' = '贵阳市公安局'
    '证据摘要' = '公开转载结果页摘要显示项目为无人机反制设备采购，中标结果发布时间2026年5月7日，采购主体可识别为贵阳市公安局；金额和中标单位未披露。'
    '核验备注' = '修正：原发包采购单位字段误入整段转载摘要，按摘要中明确采购主体更正；具体分局待回溯官方原文'
  }
  'LA-2026-0048' = @{
    '项目名称' = '崇仁县公安局无人机反制设备采购项目'
    '发包采购单位' = '崇仁县公安局'
    '证据摘要' = '销邦招标平台转载结果显示：关于无人机反制设备采购项目中选结果的公告，在线选取采购单位为崇仁县公安局，发布时间2026年4月1日。'
    '核验备注' = '修正：原发包采购单位字段误入整段转载摘要，按摘要中“崇仁县公安局”更正'
  }
  'LA-2023-0061' = @{
    '省内城市区域' = '山亭'
    '项目名称' = '山亭公安分局无人机反制装备项目'
    '发包采购单位' = '山亭公安分局'
    '证据摘要' = '采招网转载结果页显示无人机反制装备中标结果，发布时间2023年12月22日，摘要可识别采购主体为山亭公安分局。'
    '核验备注' = '修正：原发包采购单位字段误入转载标题和关注语，按摘要可识别主体更正'
  }
  'LA-2024-0062' = @{
    '项目名称' = '东营机场无人机反制设备采购项目'
    '发包采购单位' = '东营机场'
    '证据摘要' = '山东招标网转载成交公告显示：项目名称为东营机场无人机反制设备采购项目，项目编号SDYT2024-089#，公告日期2024年12月9日。'
    '核验备注' = '修正：原发包采购单位字段误入整段转载摘要，按项目名称和摘要中明确主体更正'
  }
  'LA-2024-0063' = @{
    '发包采购单位' = '济南市公安局特巡警支队'
    '证据摘要' = '公开转载中标公告显示：济南市公安局特巡警支队无人机反制设备项目，公告日期2024年7月18日。'
    '核验备注' = '修正：原发包采购单位字段重复拼入项目标题，已保留明确采购主体'
  }
  'LA-2024-0064' = @{
    '省内城市区域' = '禹城'
    '项目名称' = '禹城市公安局无人机反制设备采购项目'
    '发包采购单位' = '禹城市公安局'
    '证据摘要' = '采招网转载中标结果摘要显示：项目名称为禹城市公安局无人机反制设备采购项目，发布时间2024年12月6日，中标单位为山东品美信息科技有限公司。'
    '核验备注' = '修正：原发包采购单位字段误入整段采招网转载摘要，按摘要中明确采购主体更正'
  }
  'LA-2024-0109' = @{
    '项目名称' = '乌什县公安局购买无人机反制装备采购项目（二次）'
    '发包采购单位' = '乌什县公安局'
    '证据摘要' = '公开转载合同/结果摘要显示：乌什县公安局购买无人机反制装备采购项目（二次），公告日期2024年9月27日。'
    '核验备注' = '修正：原发包采购单位字段误入项目标题和转载摘要，按明确采购主体更正'
  }
  'LA-2025-0114' = @{
    '项目名称' = '克州GAJ（特警支队）无人机反制侦测相关设备采购项目'
    '发包采购单位' = '克州GAJ（特警支队）'
    '证据摘要' = '新疆招标网转载合同摘要显示：克州GAJ（特警支队）无人机反制侦测相关设备采购项目合同，供应商为新疆尚维飞创电子科技有限公司。'
    '核验备注' = '修正：原发包采购单位字段误入整段合同摘要，保留可识别采购主体和供应商'
  }
  'LA-2025-0116' = @{
    '项目名称' = '无人机反制系统及无人机机场式巡逻系统采购项目'
    '发包采购单位' = '兵团第二单位'
    '证据摘要' = '公开转载结果页摘要显示：无人机反制系统及无人机机场式巡逻系统采购项目，中标（成交）结果公告，发布时间2025年10月30日，采购主体摘要为兵团第二单位。'
    '核验备注' = '修正：原发包采购单位字段误入整段转载摘要，按摘要可识别主体更正；具体单位全称待回溯官方原文'
  }
  'LA-2025-0123' = @{
    '发包采购单位' = '某部'
    '核验备注' = '修正：原发包采购单位字段误入“网易订阅/框架招标项目”转载栏目名，按项目标题更正为某部'
  }
  'LA-2025-0031' = @{
    '项目名称' = '某部无人机及反制设备采购项目'
    '发包采购单位' = '某部'
    '证据摘要' = '黑龙江招标网转载结果公示显示：某部无人机及反制设备采购项目，中标结果公示发布时间2025年7月31日；中标单位公开摘要未披露。'
    '核验备注' = '修正：原发包采购单位字段误入“受业主委托”平台语，按项目标题更正为某部'
  }
  'LA-2025-0052' = @{
    '发包采购单位' = '公开信息未披露'
    '核验备注' = '修正：原发包采购单位字段误入评审确认语，公开摘要未识别采购主体'
  }
  'LA-2025-0074' = @{
    '省内城市区域' = '未识别'
    '项目名称' = '无人机反制设备采购结果公告（2025-JKFDLB-W3023）'
    '项目金额' = '26.4900 万元'
    '金额万元' = '26.49'
    '承建中标单位' = '天津云翔无人机科技有限公司'
    '证据摘要' = '公开转载结果公告显示：项目名称为无人机反制设备采购，项目编号2025-JKFDLB-W3023，第一名天津云翔无人机科技有限公司，最终报价264900元。'
    '核验备注' = '修正：原省内城市区域误取供应商所在地“天津”，改为未识别；补入公开摘要披露的第一名供应商和报价'
  }
  'LA-2024-0108' = @{
    '发包采购单位' = '公开信息未披露'
    '核验备注' = '修正：原发包采购单位为“--”，规范为公开信息未披露'
  }
}

function Update-Row($row) {
  $id = $row.项目ID
  if (-not $id -or -not $corrections.ContainsKey($id)) { return $false }
  foreach ($key in $corrections[$id].Keys) {
    if ($row.PSObject.Properties.Name -contains $key) {
      $row.$key = $corrections[$id][$key]
    }
  }
  return $true
}

function Update-BySourceLink($row) {
  if (-not ($row.PSObject.Properties.Name -contains '来源链接')) { return $false }
  $changed = $false
  foreach ($id in $corrections.Keys) {
    $sourceRows = $script:mainRows | Where-Object { $_.项目ID -eq $id }
    if ($sourceRows.Count -eq 0) { continue }
    $link = $sourceRows[0].来源链接
    if ($link -and $row.来源链接 -eq $link) {
      foreach ($key in $corrections[$id].Keys) {
        if ($row.PSObject.Properties.Name -contains $key) {
          $row.$key = $corrections[$id][$key]
          $changed = $true
        }
      }
    }
  }
  return $changed
}

$utf8 = New-Object System.Text.UTF8Encoding($true)
$mainPath = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_全量汇总.csv'
$script:mainRows = Import-Csv -LiteralPath $mainPath
$changedMain = 0
foreach ($row in $script:mainRows) {
  if (Update-Row $row) { $changedMain++ }
}
$script:mainRows | Export-Csv -LiteralPath $mainPath -NoTypeInformation -Encoding UTF8
$script:mainRows | Export-Csv -LiteralPath (Join-Path $base '低空侦测招投标案例库_按省份全量_2023-2026.csv') -NoTypeInformation -Encoding UTF8

$csvFiles = @(
  Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_按需求分类.csv'
  Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_设备明细长表.csv'
  Join-Path $outDir '重大活动保障_显性及潜在打包项目.csv'
  Join-Path $outDir '数据质量审计_待复核与转载来源.csv'
)

$changedOther = @{}
foreach ($path in $csvFiles) {
  if (-not (Test-Path -LiteralPath $path)) { continue }
  $rows = Import-Csv -LiteralPath $path
  $count = 0
  foreach ($row in $rows) {
    $changed = $false
    if ($row.PSObject.Properties.Name -contains '项目ID') {
      $changed = Update-Row $row
    }
    if (-not $changed) {
      $changed = Update-BySourceLink $row
    }
    if ($changed) { $count++ }
  }
  $rows | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
  $changedOther[(Split-Path -Leaf $path)] = $count
}

foreach ($province in ($script:mainRows | Group-Object 省份)) {
  $safeName = ($province.Name -replace '[\\/:*?"<>|]', '_')
  $path = Join-Path $outDir "$safeName`_低空侦测反制中标项目_2023-2026.csv"
  $province.Group | Sort-Object 项目ID | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
}

[pscustomobject]@{
  主表修正记录数 = $changedMain
  同步文件修正 = ($changedOther.GetEnumerator() | ForEach-Object { "$($_.Key):$($_.Value)" }) -join '; '
}
