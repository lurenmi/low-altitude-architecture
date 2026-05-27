$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $base '按省份低空侦测中标项目CSV_2023-2026'
$outPath = Join-Path $base '侦测产品体系市场项目数据分析报告.html'

$projects = Import-Csv -LiteralPath (Join-Path $dataDir '全国_低空侦测反制中标项目_2023-2026_按需求分类.csv')
$provinceSummary = Import-Csv -LiteralPath (Join-Path $dataDir '省份汇总统计_2023-2026.csv')
$demandSummary = Import-Csv -LiteralPath (Join-Path $dataDir '需求类别汇总统计_2023-2026.csv')
$equipmentSummary = Import-Csv -LiteralPath (Join-Path $dataDir '设备类型汇总统计_2023-2026.csv')
$equipmentRows = Import-Csv -LiteralPath (Join-Path $dataDir '全国_低空侦测反制中标项目_2023-2026_设备明细长表.csv')
$majorActivity = Import-Csv -LiteralPath (Join-Path $dataDir '重大活动保障_显性及潜在打包项目.csv')

function ToNum($value) {
  if ([string]::IsNullOrWhiteSpace([string]$value)) { return 0.0 }
  $n = 0.0
  if ([double]::TryParse(([string]$value), [ref]$n)) { return $n }
  return 0.0
}

function Json($obj) {
  $obj | ConvertTo-Json -Depth 8 -Compress
}

function Html($value) {
  [System.Net.WebUtility]::HtmlEncode([string]$value)
}

function FormatMoney($value) {
  [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, '{0:0.00}', [double]$value)
}

$script:SourceLinkCache = @{}
function GetSourceLinkState($link) {
  $url = [string]$link
  if ([string]::IsNullOrWhiteSpace($url)) {
    return [pscustomobject]@{ 状态 = '暂打不开'; 类 = 'blocked'; 说明 = '未提供来源链接'; 可打开 = $false }
  }
  if ($url -match '公开信息未披露|待回溯|待核验|待进一步核验|未披露|^\s*\.\.\.\s*$|…') {
    return [pscustomobject]@{ 状态 = '暂打不开'; 类 = 'blocked'; 说明 = '链接文本为占位或待核验'; 可打开 = $false }
  }
  if ($script:SourceLinkCache.ContainsKey($url)) {
    return $script:SourceLinkCache[$url]
  }

  $state = [pscustomobject]@{ 状态 = '暂打不开'; 类 = 'blocked'; 说明 = '校核未通过'; 可打开 = $false }
  try {
    $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -Method Head -MaximumRedirection 5 -TimeoutSec 10 -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
    $code = [int]$resp.StatusCode
    if ($code -ge 200 -and $code -lt 400) {
      $state = [pscustomobject]@{ 状态 = '可打开'; 类 = 'open'; 说明 = "HTTP $code"; 可打开 = $true }
    }
  } catch {
    try {
      $resp = Invoke-WebRequest -UseBasicParsing -Uri $url -Method Get -MaximumRedirection 5 -TimeoutSec 12 -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
      $code = [int]$resp.StatusCode
      if ($code -ge 200 -and $code -lt 400) {
        $state = [pscustomobject]@{ 状态 = '可打开'; 类 = 'open'; 说明 = "HTTP $code"; 可打开 = $true }
      } elseif ($code -ge 400) {
        $state = [pscustomobject]@{ 状态 = '暂打不开'; 类 = 'blocked'; 说明 = "HTTP $code"; 可打开 = $false }
      }
    } catch {
      $msg = [string]$_.Exception.Message
      $state = [pscustomobject]@{ 状态 = '暂打不开'; 类 = 'blocked'; 说明 = if ($msg) { $msg } else { '请求失败' }; 可打开 = $false }
    }
  }

  $script:SourceLinkCache[$url] = $state
  return $state
}

$totalProjects = $projects.Count
$provinceCount = @($projects | Group-Object 省份).Count
$officialCount = @($projects | Where-Object { $_.来源等级 -match '^A' }).Count
$amountRows = @($projects | Where-Object { $_.金额万元 -ne '' })
$amountCount = $amountRows.Count
$amountTotal = [math]::Round((($amountRows | ForEach-Object { ToNum $_.金额万元 }) | Measure-Object -Sum).Sum, 2)
$amountAvg = if ($amountCount -gt 0) { [math]::Round($amountTotal / $amountCount, 2) } else { 0 }
$fullCount = @($projects | Where-Object { $_.字段完整度 -eq '完整' }).Count
$partialCount = @($projects | Where-Object { $_.字段完整度 -eq '较完整' }).Count
$reviewCount = @($projects | Where-Object { $_.字段完整度 -eq '待复核' }).Count
$equipmentLineCount = $equipmentRows.Count
$majorPoolCount = $majorActivity.Count
$explicitMajor = @($majorActivity | Where-Object { $_.活动保障识别层级 -eq '显性重大活动保障项目' }).Count
$highMajor = @($majorActivity | Where-Object { $_.活动保障识别层级 -eq '高概率活动保障打包项目' }).Count
$midMajor = @($majorActivity | Where-Object { $_.活动保障识别层级 -eq '中概率活动保障能力项目' }).Count

$allSourceLinks = @(
  $projects | ForEach-Object { [string]$_.来源链接 }
  $majorActivity | ForEach-Object { [string]$_.来源链接 }
) | Where-Object { $_ -and $_ -notmatch '^\s*$' } | Select-Object -Unique
foreach ($link in $allSourceLinks) { [void](GetSourceLinkState $link) }
$openLinkCount = @($allSourceLinks | Where-Object { (GetSourceLinkState $_).状态 -eq '可打开' }).Count
$blockedLinkCount = @($allSourceLinks | Where-Object { (GetSourceLinkState $_).状态 -eq '暂打不开' }).Count

function IsMissingBuyer($value) {
  $buyer = [string]$value
  return [string]::IsNullOrWhiteSpace($buyer) -or $buyer -match '公开信息未披露|^\.\.\.$|^--$|^\(略\)$|受业主委托|招标网|采招网|结果公示|成交公告|中标公告|采购结果公示|反馈'
}

function GetBuyerCategory($row) {
  $buyer = [string]$row.发包采购单位
  $title = [string]$row.项目名称
  $buyerKnown = -not (IsMissingBuyer $buyer)
  $text = "$buyer $title"

  if ([string]$row.项目ID -eq 'LA-2024-0039') { return '未披露/转载脱敏' }

  if ($text -match '公安|GAJ|特警|警官|边境管理|铁路公安|监狱|看守|监所') { return '公安司法与公共安全' }
  if ($text -match '某部|军分区|民兵|部队|某单位') { return '军队/涉密脱敏单位' }
  if ($text -match '机场|铁路|交通|港口|水库|电厂|核电|石化|电网|能源|煤田|边防|南方电网|东营机场|咸阳国际机场') { return '机场交通能源等敏感基础设施' }
  if ($buyerKnown -and $text -match '园区|物流|试验|示范基地|公司|合营|供应链|中国电信|中国移动|中国联通|铁塔|大学|学院|学校|工商大学|职业学院|运营') { return '企业园区/高校科研/运营主体' }
  if ((-not $buyerKnown) -and $title -match '园区|物流|试验|示范基地|大学|学院|学校|工商大学|职业学院|运营') { return '企业园区/高校科研/运营主体' }
  if ($text -match '应急|政府|管委会|体育|文体|无线电|监测站|事业') { return '政府部门及事业单位' }
  if ((IsMissingBuyer $buyer) -or $text -match '公开信息未披露|^\.{3}$|^--$|^\(略\)$|受业主委托|招标网|采招网|结果公示|成交公告|中标公告|采购结果公示|反馈') { return '未披露/转载脱敏' }
  return '其他可识别主体'
}

function IsPlatformProject($row) {
  $text = "{0} {1} {2} {3} {4} {5}" -f $row.项目名称, $row.项目类型, $row.软硬件属性, $row.设备名称清单, $row.设备类型清单, $row.核验备注
  return $text -match '平台|系统|管控|指控|显控|低空云|智联|融合|信息化|数字孪生|态势|服务平台'
}

function NormalizeKey($value) {
  $text = [string]$value
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  $text = $text.Trim()
  $text = $text -replace '\s+', ''
  $text = $text -replace '[\p{P}\p{S}]', ''
  return $text.ToLowerInvariant()
}

function GetProjectDisplayName($row) {
  if ([string]$row.项目ID -eq 'LA-2024-0039') { return '太湖之鹰无人机及反制设备采购项目' }

  $text = [string]$row.项目名称
  if ([string]::IsNullOrWhiteSpace($text)) { return '' }
  $text = $text.Trim()
  $text = $text -replace '\s+', ''
  $text = $text -replace '[\p{P}\p{S}]', ''
  $text = $text -replace '(中标结果公告|中标公告|成交公告|结果公告|结果公示|采购结果公示|中标成交结果公告|招标公告|合同公告|采购结果公告|中标结果|成交结果公告|成交结果|采购结果公示)$', ''
  $text = $text -replace '(?:采招网|招标网|中标公告|结果公告|成交公告|结果公示|采购结果公示|反馈|公告)$', ''
  $text = $text -replace '\d{4}年\d{1,2}月\d{1,2}日$', ''
  return $text
}

function GetProjectGroupKey($row) {
  $province = NormalizeKey $row.省份
  $buyer = NormalizeKey $row.发包采购单位
  $title = NormalizeKey (GetProjectDisplayName $row)
  $year = NormalizeKey $row.年份
  return "$province|$buyer|$title|$year"
}

function GetDateScore($value) {
  $text = [string]$value
  if ($text -match '(?<y>\d{4})[年/-](?<m>\d{1,2})[月/-](?<d>\d{1,2})') {
    return [datetime]::new([int]$Matches.y, [int]$Matches.m, [int]$Matches.d)
  }
  return [datetime]::MaxValue
}

function GetProjectScore($row) {
  $score = 0
  switch ([string]$row.字段完整度) {
    '完整' { $score += 300 }
    '较完整' { $score += 200 }
    '待复核' { $score += 100 }
  }
  if ([string]$row.来源等级 -match '^A') { $score += 40 }
  elseif ([string]$row.来源等级 -match '^B') { $score += 20 }
  if ($row.金额万元 -ne '') { $score += 15 }
  if ($row.承建中标单位 -and $row.承建中标单位 -notmatch '公开信息未披露') { $score += 10 }
  if ($row.发包采购单位 -and $row.发包采购单位 -notmatch '公开信息未披露|^\.\.\.$|^\(略\)$') { $score += 5 }
  return $score
}

function FirstNonEmpty($rows, $property) {
  foreach ($row in $rows) {
    $value = [string]$row.$property
    if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '公开信息未披露|^\.\.\.$|^\(略\)$') {
      return $value
    }
  }
  return [string]$rows[0].$property
}

function JoinUniqueValues($rows, $property) {
  $values = @(
    $rows | ForEach-Object {
      $value = [string]($_.$property)
      if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '公开信息未披露|^\.\.\.$|^\(略\)$') {
        $value.Trim()
      }
    } | Where-Object { $_ }
  )
  $values = @($values | Select-Object -Unique)
  return ($values -join '；')
}

function GetMergedDateText($rows) {
  $dates = @(
    $rows | ForEach-Object {
      $value = [string]$_.中标公告时间
      if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '公开信息未披露') {
        $value.Trim()
      }
    } | Where-Object { $_ }
  )
  $dates = @($dates | Select-Object -Unique | Sort-Object { GetDateScore $_ })
  if ($dates.Count -eq 0) { return [string]$rows[0].中标公告时间 }
  if ($dates.Count -le 3) { return ($dates -join ' / ') }
  return "$($dates[0]) / $($dates[-1])"
}

function GetMergedYearText($rows) {
  $years = @(
    $rows | ForEach-Object {
      $value = [string]$_.年份
      if (-not [string]::IsNullOrWhiteSpace($value)) { $value.Trim() }
    } | Where-Object { $_ }
  )
  $years = @($years | Select-Object -Unique | Sort-Object)
  if ($years.Count -eq 0) { return [string]$rows[0].年份 }
  if ($years.Count -le 2) { return ($years -join '/') }
  return "$($years[0])/$($years[-1])"
}

$projectGroups = $projects |
  Group-Object { GetProjectGroupKey $_ } |
  ForEach-Object {
    $rows = @($_.Group)
    $orderedRows = $rows | Sort-Object @{ Expression = { GetDateScore $_.中标公告时间 }; Ascending = $true }, @{ Expression = { GetProjectScore $_ }; Descending = $true }
    $rep = $orderedRows | Select-Object -First 1
    $displayName = GetProjectDisplayName $rep
    if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = [string]$rep.项目名称 }
    $dateText = GetMergedDateText $rows
    $yearText = GetMergedYearText $rows
    $amountRow = $rows | Where-Object { $_.金额万元 -ne '' } | Sort-Object { ToNum $_.金额万元 } -Descending | Select-Object -First 1
    $sourceLevels = @($rows | ForEach-Object { [string]$_.来源等级 } | Where-Object { $_ } | Select-Object -Unique)
    $sourceLinks = @($rows | ForEach-Object { [string]$_.来源链接 } | Where-Object { $_ -and $_ -notmatch '^\s*$' } | Select-Object -Unique)
    $sourceState = if ($sourceLinks.Count -gt 0) { GetSourceLinkState $sourceLinks[0] } else { GetSourceLinkState '' }
    $sortDate = GetDateScore ([string]$orderedRows[0].中标公告时间)
    [pscustomobject]@{
      项目ID = $rep.项目ID
      省份 = $rep.省份
      省内城市区域 = $rep.省内城市区域
      项目名称 = $displayName
      主需求类别 = $rep.主需求类别
      兼具需求类别 = $rep.兼具需求类别
      软硬件属性 = $rep.软硬件属性
      项目类型 = $rep.项目类型
      项目阶段 = $rep.项目阶段
      发包采购单位 = FirstNonEmpty $rows '发包采购单位'
      项目金额 = if ($amountRow) { $amountRow.项目金额 } else { $rep.项目金额 }
      金额万元 = if ($amountRow) { $amountRow.金额万元 } else { $rep.金额万元 }
      承建中标单位 = if ($amountRow -and $amountRow.承建中标单位) { $amountRow.承建中标单位 } else { FirstNonEmpty $rows '承建中标单位' }
      中标公告时间 = $dateText
      年份 = $yearText
      来源等级 = ($sourceLevels -join '、')
      字段完整度 = $orderedRows[0].字段完整度
      设备名称清单 = JoinUniqueValues $rows '设备名称清单'
      设备类型清单 = JoinUniqueValues $rows '设备类型清单'
      设备数量清单 = JoinUniqueValues $rows '设备数量清单'
      来源链接 = if ($sourceLinks.Count -gt 0) { $sourceLinks[0] } else { [string]$rep.来源链接 }
      来源链接状态 = $sourceState.状态
      来源链接说明 = $sourceState.说明
      核验备注 = if ($rows.Count -gt 1) { (($rep.核验备注, "同项目合并（$($rows.Count)条公告）") -join '；') } else { [string]$rep.核验备注 }
      同组公告数 = $rows.Count
      同组来源数 = $sourceLinks.Count
      排序日期 = $sortDate
      排序日期文本 = if ($sortDate -ne [datetime]::MaxValue) { $sortDate.ToString('yyyy-MM-dd') } else { '' }
    }
  } |
  Sort-Object 排序日期, 省份, 项目名称

$displayProjectCount = $projectGroups.Count

$platformGroups = $projectGroups | Where-Object { IsPlatformProject $_ }
$platformAmountRows = @($platformGroups | Where-Object { $_.金额万元 -ne '' })
$platformProjectCount = $platformGroups.Count
$platformAmountTotal = [math]::Round((($platformAmountRows | ForEach-Object { ToNum $_.金额万元 }) | Measure-Object -Sum).Sum, 2)
$platformYearSummary = $platformAmountRows |
  Group-Object {
    if ($_.排序日期 -and $_.排序日期 -ne [datetime]::MaxValue) { $_.排序日期.Year.ToString() }
    else { ([string]$_.年份).Split('/')[0] }
  } |
  Sort-Object Name |
  ForEach-Object {
    [pscustomobject]@{
      年份 = $_.Name
      项目数 = $_.Count
      合同额万元 = [math]::Round((($_.Group | ForEach-Object { ToNum $_.金额万元 }) | Measure-Object -Sum).Sum, 2)
    }
  }
$platformTopSummary = $platformAmountRows |
  Sort-Object { ToNum $_.金额万元 } -Descending |
  Select-Object -First 8 |
  ForEach-Object {
    [pscustomobject]@{
      项目名称 = $_.项目名称
      年份 = $_.年份
      省份 = $_.省份
      合同额万元 = [math]::Round((ToNum $_.金额万元), 2)
      承建中标单位 = $_.承建中标单位
    }
  }
$platformPeak = $platformYearSummary | Sort-Object 合同额万元 -Descending | Select-Object -First 1
$platformShareOfTotal = if ($amountTotal -gt 0) { [math]::Round(($platformAmountTotal / $amountTotal * 100), 1) } else { 0 }
$platformAmountCount = $platformAmountRows.Count
$platformAvgAmount = if ($platformAmountCount -gt 0) { [math]::Round($platformAmountTotal / $platformAmountCount, 2) } else { 0 }

$platformTopRowsHtml = if ($platformTopSummary.Count -gt 0) {
  ($platformTopSummary | Select-Object -First 6 | ForEach-Object {
    $year = Html $_.年份
    $name = Html $_.项目名称
    $province = Html $_.省份
    $supplier = Html $_.承建中标单位
    $amount = FormatMoney $_.合同额万元
    "<div class=`"platform-item`"><div class=`"platform-item-head`"><span class=`"badge`">$year</span><strong>$name</strong></div><div class=`"platform-item-meta`">$amount 万元 · $province</div><div class=`"mini`">$supplier</div></div>"
  }) -join "`n"
} else {
  '<div class="mini">暂无可解析金额样本。</div>'
}

$buyerTagged = $projects | ForEach-Object {
  $cat = GetBuyerCategory $_
  [pscustomobject]@{
    发包主体类别 = $cat
    发包采购单位 = $_.发包采购单位
    省份 = $_.省份
    项目名称 = $_.项目名称
    项目金额 = $_.项目金额
    金额万元 = $_.金额万元
  }
}

$buyerCategorySummary = $buyerTagged |
  Group-Object 发包主体类别 |
  Sort-Object Count -Descending |
  ForEach-Object {
    [pscustomobject]@{
      主体类别 = $_.Name
      项目数 = $_.Count
      可解析金额万元 = [math]::Round((($_.Group | Where-Object { $_.金额万元 -ne '' } | ForEach-Object { ToNum $_.金额万元 }) | Measure-Object -Sum).Sum, 2)
      代表发包单位 = (($_.Group | Where-Object { $_.发包采购单位 -and $_.发包采购单位 -notmatch '公开信息未披露|^\.{3}$|^--$|^\(略\)$' } | Select-Object -ExpandProperty 发包采购单位 -Unique | Select-Object -First 3) -join '、')
    }
  }

$buyerCategoryDetail = $buyerTagged |
  Group-Object 发包主体类别 |
  ForEach-Object {
    $unitList = @(
      $_.Group |
        Where-Object { $_.发包采购单位 -and $_.发包采购单位 -notmatch '公开信息未披露|^\.{3}$|^--$|^\(略\)$' } |
        Select-Object -ExpandProperty 发包采购单位 -Unique |
        Sort-Object
    )
    $projectList = @(
      $_.Group |
        Select-Object -ExpandProperty 项目名称 -Unique |
        Sort-Object |
        Select-Object -First 6
    )
    [pscustomobject]@{
      主体类别 = $_.Name
      项目数 = $_.Count
      单位数 = $unitList.Count
      单位列表 = $unitList
      项目示例 = $projectList
    }
  }

$buyerTopSummary = $projects |
  Where-Object { $_.发包采购单位 -and $_.发包采购单位 -notmatch '公开信息未披露|^\.{3}$|^--$|^\(略\)$|受业主委托|反馈|招标网|采招网|结果公示|成交公告|中标公告|采购结果公示' } |
  Group-Object 发包采购单位 |
  Sort-Object Count -Descending |
  Select-Object -First 12 |
  ForEach-Object {
    [pscustomobject]@{
      发包采购单位 = $_.Name
      项目数 = $_.Count
      省份 = (($_.Group | Select-Object -ExpandProperty 省份 -Unique) -join '、')
      代表项目 = ($_.Group | Select-Object -First 1 | Select-Object -ExpandProperty 项目名称)
    }
  }

$capabilitySummary = $projects |
  Group-Object 软硬件属性 |
  Sort-Object Count -Descending |
  ForEach-Object {
    [pscustomobject]@{
      能力形态 = $_.Name
      项目数 = $_.Count
      可解析金额万元 = [math]::Round((($_.Group | Where-Object { $_.金额万元 -ne '' } | ForEach-Object { ToNum $_.金额万元 }) | Measure-Object -Sum).Sum, 2)
    }
  }

$buyerPublicCount = [int](($buyerCategorySummary | Where-Object { $_.主体类别 -eq '公安司法与公共安全' } | Select-Object -First 1).项目数)
$buyerMilitaryCount = [int](($buyerCategorySummary | Where-Object { $_.主体类别 -eq '军队/涉密脱敏单位' } | Select-Object -First 1).项目数)
$buyerInfraCount = [int](($buyerCategorySummary | Where-Object { $_.主体类别 -eq '机场交通能源等敏感基础设施' } | Select-Object -First 1).项目数)
$buyerHiddenCount = [int](($buyerCategorySummary | Where-Object { $_.主体类别 -eq '未披露/转载脱敏' } | Select-Object -First 1).项目数)

$yearSummary = $projects |
  Group-Object 年份 |
  Sort-Object Name |
  ForEach-Object {
    [pscustomobject]@{
      年份 = $_.Name
      项目数 = $_.Count
      可解析金额万元 = [math]::Round((($_.Group | Where-Object { $_.金额万元 -ne '' } | ForEach-Object { ToNum $_.金额万元 }) | Measure-Object -Sum).Sum, 2)
    }
  }

$platform2025Row = $platformYearSummary | Where-Object { $_.年份 -eq '2025' } | Select-Object -First 1
$platform2026Row = $platformYearSummary | Where-Object { $_.年份 -eq '2026' } | Select-Object -First 1
$platform2023Row = $platformYearSummary | Where-Object { $_.年份 -eq '2023' } | Select-Object -First 1
$platform2024Row = $platformYearSummary | Where-Object { $_.年份 -eq '2024' } | Select-Object -First 1
$year2023Row = $yearSummary | Where-Object { $_.年份 -eq '2023' } | Select-Object -First 1
$year2024Row = $yearSummary | Where-Object { $_.年份 -eq '2024' } | Select-Object -First 1
$year2025Row = $yearSummary | Where-Object { $_.年份 -eq '2025' } | Select-Object -First 1
$year2026Row = $yearSummary | Where-Object { $_.年份 -eq '2026' } | Select-Object -First 1
$platform2023Share = if ($platform2023Row -and $year2023Row -and $year2023Row.可解析金额万元 -gt 0) { [math]::Round(($platform2023Row.合同额万元 / $year2023Row.可解析金额万元 * 100), 1) } else { 0 }
$platform2024Share = if ($platform2024Row -and $year2024Row -and $year2024Row.可解析金额万元 -gt 0) { [math]::Round(($platform2024Row.合同额万元 / $year2024Row.可解析金额万元 * 100), 1) } else { 0 }
$platform2025Share = if ($platform2025Row -and $year2025Row -and $year2025Row.可解析金额万元 -gt 0) { [math]::Round(($platform2025Row.合同额万元 / $year2025Row.可解析金额万元 * 100), 1) } else { 0 }
$platform2026Share = if ($platform2026Row -and $year2026Row -and $year2026Row.可解析金额万元 -gt 0) { [math]::Round(($platform2026Row.合同额万元 / $year2026Row.可解析金额万元 * 100), 1) } else { 0 }
$platform2024To2025Growth = if ($platform2024Row -and $platform2024Row.合同额万元 -gt 0 -and $platform2025Row) { [math]::Round((($platform2025Row.合同额万元 - $platform2024Row.合同额万元) / $platform2024Row.合同额万元 * 100), 1) } else { 0 }
$platform2023To2024Growth = if ($platform2023Row -and $platform2023Row.合同额万元 -gt 0 -and $platform2024Row) { [math]::Round((($platform2024Row.合同额万元 - $platform2023Row.合同额万元) / $platform2023Row.合同额万元 * 100), 1) } else { 0 }

$platformYearMax = if ($platformYearSummary.Count -gt 0) { ($platformYearSummary | Measure-Object 合同额万元 -Maximum).Maximum } else { 0 }
$platformTrendRowsHtml = if ($platformYearSummary.Count -gt 0) {
  ($platformYearSummary | ForEach-Object {
    $width = if ($platformYearMax -gt 0) { [math]::Round(($_.合同额万元 / $platformYearMax * 100), 1) } else { 0 }
    $share = switch ($_.年份) {
      '2023' { $platform2023Share }
      '2024' { $platform2024Share }
      '2025' { $platform2025Share }
      '2026' { $platform2026Share }
      default { 0 }
    }
    $year = Html $_.年份
    $count = [int]$_.项目数
    $amount = FormatMoney $_.合同额万元
    $note = if ($_.年份 -eq '2026') { '截至当前样本截面' } else { "占当年可解析金额 ${share}%" }
    "<div class=`"trend-row`"><div class=`"trend-meta`"><strong>$year</strong><span>$count 个项目 · $note</span></div><div class=`"bar-track`"><div class=`"bar-fill violet`" style=`"width:${width}%`"></div></div><div class=`"trend-value`">$amount 万元</div></div>"
  }) -join "`n"
} else {
  '<div class="mini">暂无可解析金额样本。</div>'
}

$topAmount = $projects |
  Where-Object { $_.金额万元 -ne '' } |
  Sort-Object { ToNum $_.金额万元 } -Descending |
  Select-Object -First 12 省份,省内城市区域,项目名称,主需求类别,项目金额,金额万元,承建中标单位,中标公告时间,来源等级,设备名称清单,来源链接

$topProvinceByAmount = $provinceSummary |
  Sort-Object { ToNum $_.可解析金额合计万元 } -Descending |
  Select-Object -First 18

$zhejiangCases = $projects |
  Where-Object { $_.省份 -eq '浙江' } |
  Sort-Object 年份,省内城市区域,项目名称 |
  Select-Object 省内城市区域,项目名称,主需求类别,项目金额,承建中标单位,中标公告时间,设备名称清单,来源等级

$luzhouCases = $projects |
  Where-Object { $_.项目名称 -match '泸州|成都世运会|成都市公安局无人机反制装备' } |
  Sort-Object 年份,项目名称 |
  Select-Object 省内城市区域,项目名称,主需求类别,项目金额,承建中标单位,中标公告时间,设备名称清单,来源等级

$supplierSummary = $projects |
  Where-Object { $_.承建中标单位 -and $_.承建中标单位 -notmatch '公开信息未披露|确认，本项目|社会信用代码|点击查看' } |
  Group-Object 承建中标单位 |
  Sort-Object Count -Descending |
  Select-Object -First 20 |
  ForEach-Object {
    [pscustomobject]@{
      中标单位 = $_.Name
      项目数 = $_.Count
      金额万元 = [math]::Round((($_.Group | Where-Object { $_.金额万元 -ne '' } | ForEach-Object { ToNum $_.金额万元 }) | Measure-Object -Sum).Sum, 2)
      涉及省份 = (($_.Group | Select-Object -ExpandProperty 省份 -Unique) -join '、')
    }
  }

$priceBands = @(
  [pscustomobject]@{区间='50万元以下'; 项目数=@($amountRows | Where-Object { (ToNum $_.金额万元) -lt 50 }).Count}
  [pscustomobject]@{区间='50-100万元'; 项目数=@($amountRows | Where-Object { (ToNum $_.金额万元) -ge 50 -and (ToNum $_.金额万元) -lt 100 }).Count}
  [pscustomobject]@{区间='100-200万元'; 项目数=@($amountRows | Where-Object { (ToNum $_.金额万元) -ge 100 -and (ToNum $_.金额万元) -lt 200 }).Count}
  [pscustomobject]@{区间='200-500万元'; 项目数=@($amountRows | Where-Object { (ToNum $_.金额万元) -ge 200 -and (ToNum $_.金额万元) -lt 500 }).Count}
  [pscustomobject]@{区间='500万元以上'; 项目数=@($amountRows | Where-Object { (ToNum $_.金额万元) -ge 500 }).Count}
)

$meta = [pscustomobject]@{
  totalProjects = $totalProjects
  provinceCount = $provinceCount
  officialCount = $officialCount
  amountCount = $amountCount
  amountTotal = $amountTotal
  amountAvg = $amountAvg
  fullCount = $fullCount
  partialCount = $partialCount
  reviewCount = $reviewCount
  equipmentLineCount = $equipmentLineCount
  majorPoolCount = $majorPoolCount
  explicitMajor = $explicitMajor
  highMajor = $highMajor
  midMajor = $midMajor
  sourceLinkOpenCount = $openLinkCount
  sourceLinkBlockedCount = $blockedLinkCount
  generatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm')
}

$projectsSlim = $projectGroups | Sort-Object @{ Expression = { $_.排序日期 }; Descending = $true }, 省份, 项目名称 | Select-Object 项目ID,省份,省内城市区域,项目名称,主需求类别,兼具需求类别,软硬件属性,项目类型,项目阶段,发包采购单位,项目金额,金额万元,承建中标单位,中标公告时间,年份,来源等级,字段完整度,设备名称清单,设备类型清单,设备数量清单,来源链接,来源链接状态,来源链接说明,排序日期文本,核验备注,同组公告数,同组来源数
$majorActivitySlim = $majorActivity | Select-Object @{Name='展示分组';Expression={
    if ($_.活动保障识别层级 -eq '显性重大活动保障项目') { '文本显性样本' }
    elseif ($_.活动保障识别层级 -eq '高概率活动保障打包项目') { '服务/租赁相关样本' }
    else { '装备/平台相关样本' }
  }},原主需求类别,原兼具需求类别,软硬件属性,省份,省内城市区域,项目名称,发包采购单位,项目金额,金额万元,承建中标单位,中标公告时间,年份,来源等级,字段完整度,来源链接,证据摘要,@{Name='来源链接状态';Expression={ (GetSourceLinkState $_.来源链接).状态 }},@{Name='来源链接说明';Expression={ (GetSourceLinkState $_.来源链接).说明 }}

function FindProjectRow([string[]]$patterns) {
  foreach ($pattern in $patterns) {
    $match = $projectGroups | Where-Object { $_.项目名称 -match $pattern } | Sort-Object { ToNum $_.金额万元 } -Descending | Select-Object -First 1
    if ($match) { return $match }
  }
  return $null
}

function BuildCaseCard($row, [string]$tag, [string]$fallbackName, [string]$note) {
  if (-not $row) {
    return '<div class="case-card"><div class="tag">' + (Html $tag) + '</div><h4>' + (Html $fallbackName) + '</h4><p>' + (Html $note) + '</p></div>'
  }
  $name = Html $row.项目名称
  $amount = Html ($row.项目金额 -replace '\s+', '')
  $supplier = Html ($row.承建中标单位 -replace '\s+', '')
  return '<div class="case-card"><div class="tag">' + (Html $tag) + '</div><h4>' + $name + '</h4><p>成交/中标金额' + $amount + '，中标单位' + $supplier + '。' + (Html $note) + '</p></div>'
}

$caseCardsHtml = @(
  BuildCaseCard (FindProjectRow @('杭州市低空综合管理服务平台2\.0交通综合监管和飞行服务与审批开发服务采购项目|杭州市低空综合管理服务平台2\.0公共安防管理端开发服务采购项目')) '浙江平台 · 最新' '杭州市低空综合管理服务平台2.0项目' '城市级低空平台、交通监管和飞行服务审批模块已进入真实中标样本，说明平台型需求正在扩张。'
  BuildCaseCard (FindProjectRow @('杭州市临安区JW无人机低空安全保障服务项目')) '浙江安全 · 服务' '杭州市临安区JW无人机低空安全保障服务项目' '适合对外沟通浙江本地低空安全运营服务的价格和交付方式。'
  BuildCaseCard (FindProjectRow @('准格尔旗公安低空数字警务项目（2026年采购）|准格尔旗公安低空数字警务项目')) '数字警务 · 2026' '准格尔旗公安低空数字警务项目' '2026年重采样本应优先展示最新中标单位和平台化组合能力；2025年历史中标样本可保留在底层库作对照。'
  BuildCaseCard (FindProjectRow @('昌都市公安局采购低空安全反无人机系统项目')) '边疆公安 · 官方' '昌都市公安局采购低空安全反无人机系统项目' '体现边疆公安低空安全场景对侦测、预警和处置一体化能力的需求。'
  BuildCaseCard (FindProjectRow @('广东省茂名监狱低空域智能警戒巡防系统采购项目')) '敏感目标 · 监所' '广东省茂名监狱低空域智能警戒巡防系统采购项目' '监狱、核电、石化等敏感目标的低空警戒巡防已进入系统化采购阶段。'
  BuildCaseCard (FindProjectRow @('南昌市公安局低空安全及反制设备采购项目')) '公安装备 · 官方' '南昌市公安局低空安全及反制设备采购项目' '单点设备采购仍然存在，是县市级公安切入的典型价格带。'
  BuildCaseCard (FindProjectRow @('中国铁塔股份有限公司遂宁市分公司2025年低空安全态势感知监管平台服务与无人机监测反制设备采购项目')) '运营商 · 平台服务' '中国铁塔股份有限公司遂宁市分公司2025年低空安全态势感知监管平台服务与无人机监测反制设备采购项目' '运营商参与低空监管平台和反制设备采购的路径正在变得清晰。'
  BuildCaseCard (FindProjectRow @('横琴粤澳深度合作区公安局重大活动安保无人机防控服务政府采购项目')) '重大活动 · 官方' '横琴重大活动安保无人机防控服务' '赛事、会展、活动安保场景更适合以服务包而非一次性硬件形态表达。'
) -join "`n"

$html = @"
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>侦测产品体系市场项目数据分析报告</title>
  <style>
    :root {
      --bg: #0b0e0d;
      --panel: #121817;
      --panel2: #17201e;
      --line: rgba(159, 229, 199, .22);
      --text: #eef8f3;
      --muted: #9db0aa;
      --cyan: #4fd7ff;
      --mint: #55e6a5;
      --amber: #f5c15d;
      --coral: #ff746d;
      --violet: #b99cff;
      --white: #ffffff;
      --shadow: 0 18px 60px rgba(0,0,0,.35);
      --radius: 8px;
    }
    * { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    body {
      margin: 0;
      background:
        linear-gradient(180deg, rgba(19,34,32,.92), rgba(11,14,13,.98) 36%, #0b0e0d),
        repeating-linear-gradient(90deg, rgba(85,230,165,.035) 0 1px, transparent 1px 88px),
        repeating-linear-gradient(0deg, rgba(79,215,255,.025) 0 1px, transparent 1px 88px);
      color: var(--text);
      font-family: "Microsoft YaHei", "PingFang SC", "Segoe UI", Arial, sans-serif;
      letter-spacing: 0;
    }
    a { color: var(--cyan); text-decoration: none; }
    .topbar {
      position: sticky; top: 0; z-index: 30;
      height: 56px; display: flex; align-items: center; justify-content: space-between;
      padding: 0 28px; background: rgba(11,14,13,.78); backdrop-filter: blur(14px);
      border-bottom: 1px solid var(--line);
    }
    .brand { display: flex; align-items: center; gap: 10px; font-weight: 700; }
    .brand-mark { width: 22px; height: 22px; border: 2px solid var(--mint); transform: rotate(45deg); box-shadow: 0 0 22px rgba(85,230,165,.5); }
    .nav { display: flex; gap: 18px; font-size: 13px; color: var(--muted); }
    .nav a { color: var(--muted); }
    .hero {
      position: relative; min-height: 640px; overflow: hidden;
      display: grid; grid-template-columns: minmax(0, 1.05fr) minmax(420px, .95fr); gap: 36px;
      padding: 84px 6vw 56px;
      border-bottom: 1px solid var(--line);
    }
    .hero::after {
      content: ""; position: absolute; inset: auto 0 0 0; height: 220px;
      background: linear-gradient(180deg, transparent, rgba(11,14,13,.8));
      pointer-events: none;
    }
    .hero > * { position: relative; z-index: 2; }
    h1 { font-size: clamp(40px, 5vw, 76px); line-height: 1.04; margin: 0 0 24px; letter-spacing: 0; }
    .eyebrow { color: var(--mint); font-size: 13px; font-weight: 700; text-transform: uppercase; margin-bottom: 14px; }
    .subtitle { color: #c9d8d3; max-width: 880px; line-height: 1.78; font-size: 17px; }
    .hero-actions { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 28px; }
    .pill {
      border: 1px solid var(--line); padding: 9px 12px; border-radius: 999px;
      background: rgba(18,24,23,.72); color: #d9eee6; font-size: 13px;
    }
    .city-panel { min-height: 420px; align-self: center; }
    .city-svg { width: 100%; height: 100%; min-height: 420px; filter: drop-shadow(0 18px 50px rgba(0,0,0,.45)); }
    .section { padding: 68px 6vw; border-bottom: 1px solid rgba(159,229,199,.12); scroll-margin-top: 72px; }
    .section-head { display: flex; justify-content: space-between; align-items: start; gap: 24px; margin-bottom: 28px; }
    h2 { margin: 0; font-size: clamp(26px, 3vw, 42px); }
    .lead { color: var(--muted); line-height: 1.75; max-width: 980px; }
    .kpi-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; margin-top: 32px; }
    .kpi, .panel, .case-card, .insight, .activity-card {
      background: linear-gradient(180deg, rgba(23,32,30,.92), rgba(18,24,23,.92));
      border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow);
      min-width: 0;
    }
    .kpi { padding: 18px; min-height: 128px; }
    .kpi.drillable { cursor: pointer; transition: transform .15s ease, border-color .15s ease, box-shadow .15s ease; }
    .kpi.drillable:hover { transform: translateY(-1px); border-color: rgba(85,230,165,.42); }
    .kpi.drillable.active { border-color: rgba(85,230,165,.56); box-shadow: 0 0 0 1px rgba(85,230,165,.16), var(--shadow); }
    .kpi .label { color: var(--muted); font-size: 13px; }
    .kpi .value { font-size: 34px; font-weight: 800; margin: 12px 0 6px; }
    .kpi .note { color: #b9c9c4; font-size: 12px; line-height: 1.55; }
    .grid-2 { display: grid; grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); gap: 18px; align-items: start; }
    .grid-3 { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 18px; align-items: start; }
    .panel { padding: 20px; overflow: hidden; }
    .panel h3 { margin: 0 0 14px; font-size: 18px; }
    .mini { color: var(--muted); font-size: 12px; margin-bottom: 14px; line-height: 1.6; }
    .bar-row { display: grid; grid-template-columns: 150px 1fr 70px; align-items: center; gap: 12px; margin: 11px 0; font-size: 13px; }
    .bar-track { height: 10px; background: rgba(255,255,255,.06); border-radius: 999px; overflow: hidden; }
    .bar-fill { height: 100%; border-radius: 999px; background: linear-gradient(90deg, var(--mint), var(--cyan)); }
    .bar-fill.amber { background: linear-gradient(90deg, var(--amber), var(--coral)); }
    .bar-fill.violet { background: linear-gradient(90deg, var(--violet), var(--cyan)); }
    .matrix { display: grid; grid-template-columns: repeat(auto-fit, minmax(132px, 1fr)); gap: 10px; }
    .province-cell {
      min-height: 88px; padding: 12px; border: 1px solid rgba(255,255,255,.08); border-radius: 8px;
      background: rgba(255,255,255,.035); display: flex; flex-direction: column; justify-content: space-between;
    }
    .province-cell.drillable { cursor: pointer; transition: background .15s ease, transform .15s ease, border-color .15s ease; }
    .province-cell.drillable:hover { background: rgba(85,230,165,.08); border-color: rgba(85,230,165,.24); transform: translateY(-1px); }
    .province-cell.drillable.active { background: rgba(85,230,165,.14); border-color: rgba(85,230,165,.38); }
    .province-cell strong { font-size: 15px; line-height: 1.15; }
    .province-cell span { color: var(--muted); font-size: 12px; line-height: 1.45; }
    .case-grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 14px; }
    .case-card { padding: 16px; min-height: 190px; }
    .case-card .tag { color: var(--mint); font-size: 12px; margin-bottom: 10px; }
    .case-card h4 { margin: 0 0 10px; font-size: 16px; line-height: 1.45; }
    .case-card p { color: #bfd0cb; line-height: 1.58; font-size: 13px; margin: 0; }
    .insight { padding: 18px; }
    .insight b { color: var(--amber); }
    .trend-row { display: grid; grid-template-columns: 180px 1fr 110px; gap: 12px; align-items: center; margin: 12px 0; }
    .trend-meta strong { display: block; font-size: 15px; color: #f6fff9; }
    .trend-meta span { display: block; font-size: 12px; color: var(--muted); line-height: 1.45; margin-top: 4px; }
    .trend-value { text-align: right; font-size: 13px; color: #dfece7; white-space: nowrap; }
    .platform-item { padding: 14px 0; border-bottom: 1px solid rgba(255,255,255,.08); }
    .platform-item:last-child { border-bottom: 0; padding-bottom: 0; }
    .platform-item-head { display: flex; align-items: flex-start; gap: 10px; }
    .platform-item-head strong { font-size: 14px; line-height: 1.45; }
    .platform-item-meta { color: #d7e4df; font-size: 13px; line-height: 1.5; margin: 8px 0 4px; }
    .bar-row { border-radius: 6px; padding: 4px 6px; margin: 7px -6px; transition: background .15s ease, transform .15s ease; }
    .bar-row.drillable { cursor: pointer; }
    .bar-row.drillable:hover { background: rgba(85,230,165,.06); transform: translateX(1px); }
    .bar-row.drillable.active { background: rgba(85,230,165,.1); }
    .drill-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; margin-bottom: 14px; }
    .drill-head h3 { margin: 0; font-size: 18px; }
    .drill-grid { display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(0, .9fr); gap: 18px; }
    .chip-list { display: flex; flex-wrap: wrap; gap: 10px; }
    .chip { display: inline-flex; align-items: center; min-height: 30px; padding: 4px 10px; border-radius: 999px; border: 1px solid rgba(79,215,255,.28); background: rgba(79,215,255,.08); color: #e7fbff; font-size: 12px; line-height: 1.3; }
    .drill-list { margin: 0; padding-left: 18px; color: #dfece7; line-height: 1.6; font-size: 13px; }
    .drill-list li + li { margin-top: 8px; }
    .click-hint { display: inline-flex; align-items: center; min-height: 22px; padding: 2px 7px; border-radius: 999px; border: 1px solid rgba(79,215,255,.28); background: rgba(79,215,255,.08); color: #9eeaff; font-size: 12px; line-height: 1.2; white-space: nowrap; }
    .table-tools { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 14px; position: relative; z-index: 12; }
    .input, .select {
      background: rgba(8, 18, 17, .96); color: #f4fffb; border: 1px solid rgba(159,229,199,.42);
      border-radius: 6px; height: 40px; padding: 0 12px; box-shadow: inset 0 0 0 1px rgba(255,255,255,.035);
      outline: none;
    }
    .input::placeholder { color: #b9cbc5; opacity: 1; }
    .input:focus, .select:focus { border-color: var(--mint); box-shadow: 0 0 0 3px rgba(85,230,165,.14); }
    .select option { background: #f7fffb; color: #10201c; }
    .input { min-width: 300px; }
    table { width: 100%; min-width: 1280px; border-collapse: collapse; font-size: 13px; table-layout: fixed; }
    th:nth-child(1) { width: 92px; }
    th:nth-child(2) { width: 270px; }
    th:nth-child(3) { width: 148px; }
    th:nth-child(4) { width: 118px; }
    th:nth-child(5) { width: 190px; }
    th:nth-child(6) { width: 118px; }
    th:nth-child(7) { width: 250px; }
    th:nth-child(8) { width: 122px; }
    th, td { padding: 11px 10px; border-bottom: 1px solid rgba(255,255,255,.08); vertical-align: top; }
    th { position: sticky; top: 0; background: #111715; color: #f2fff9; text-align: left; z-index: 5; box-shadow: 0 1px 0 rgba(159,229,199,.24), 0 10px 20px rgba(0,0,0,.22); }
    td { color: #dce9e5; line-height: 1.55; }
    td { overflow-wrap: anywhere; }
    .table-main { font-weight: 700; color: #f4fffb; line-height: 1.45; }
    .table-muted { color: var(--muted); font-size: 12px; line-height: 1.45; margin-top: 5px; }
    .table-tag { display: inline-flex; align-items: center; max-width: 100%; min-height: 22px; padding: 2px 7px; border-radius: 6px; background: rgba(255,255,255,.055); color: #cbded8; border: 1px solid rgba(255,255,255,.09); font-size: 12px; line-height: 1.25; }
    .table-wrap { max-height: 720px; overflow: auto; border: 1px solid var(--line); border-radius: var(--radius); background: rgba(8,13,12,.36); position: relative; z-index: 1; }
    .badge { display: inline-block; padding: 3px 7px; border-radius: 999px; background: rgba(85,230,165,.12); color: #aef7d5; border: 1px solid rgba(85,230,165,.28); font-size: 12px; }
    .source-cell { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; min-width: 0; }
    .source-pill { display: inline-flex; align-items: center; justify-content: center; height: 24px; padding: 0 7px; border-radius: 6px; font-size: 12px; line-height: 1; white-space: nowrap; border: 1px solid rgba(255,255,255,.12); background: rgba(255,255,255,.06); color: #dce9e5; }
    .source-pill.official { border-color: rgba(85,230,165,.34); background: rgba(85,230,165,.12); color: #aef7d5; }
    .source-pill.reprint { border-color: rgba(245,193,93,.34); background: rgba(245,193,93,.12); color: #ffe2a3; }
    .source-pill.hidden { border-color: rgba(185,156,255,.28); background: rgba(185,156,255,.1); color: #d8caff; }
    .source-link { display: inline-flex; align-items: center; justify-content: center; height: 24px; padding: 0 7px; border-radius: 6px; border: 1px solid rgba(79,215,255,.32); background: rgba(79,215,255,.08); color: #9eeaff; font-size: 12px; white-space: nowrap; }
    .source-link.open { border-color: rgba(85,230,165,.34); background: rgba(85,230,165,.1); color: #aef7d5; }
    .source-link.open:hover { background: rgba(85,230,165,.18); color: #ddfff0; }
    .source-link.blocked { border-color: rgba(255,116,109,.28); background: rgba(255,116,109,.08); color: #ffb9b5; cursor: not-allowed; }
    .source-link:hover { background: rgba(79,215,255,.16); color: #d6f8ff; }
    .source-link.blocked:hover { background: rgba(255,116,109,.08); color: #ffb9b5; }
    .link-legend { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; margin: -4px 0 12px; color: var(--muted); font-size: 12px; line-height: 1.5; }
    .source-count { color: var(--muted); font-size: 12px; white-space: nowrap; }
    .quality { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
    #activity .panel { padding: 24px; }
    #activity .drill-head { align-items: center; margin-bottom: 18px; }
    #activity .drill-head h3 { font-size: 20px; }
    .activity-drill { display: grid; gap: 18px; }
    .activity-summary {
      display: flex; align-items: center; justify-content: space-between; gap: 16px;
      padding: 12px 14px; border: 1px solid rgba(79,215,255,.16); border-radius: 8px;
      background: rgba(79,215,255,.045);
    }
    .activity-summary .mini { margin: 0; color: #d7e4df; font-size: 13px; }
    .activity-list { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
    .activity-card {
      padding: 15px; border: 1px solid rgba(255,255,255,.1); border-radius: 8px;
      background: rgba(255,255,255,.045);
    }
    .activity-card:hover { border-color: rgba(85,230,165,.26); background: rgba(85,230,165,.055); }
    .activity-title { color: #f7fffb; font-size: 15px; font-weight: 800; line-height: 1.45; margin-bottom: 9px; }
    .activity-meta { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 9px; }
    .activity-meta span {
      display: inline-flex; align-items: center; min-height: 22px; padding: 2px 7px;
      border-radius: 6px; background: rgba(255,255,255,.06); color: #d9e8e3; font-size: 12px;
      border: 1px solid rgba(255,255,255,.08);
    }
    .activity-org, .activity-reason { color: #c7d5d0; font-size: 13px; line-height: 1.55; }
    .activity-reason { margin-top: 6px; color: #aebfba; }
    .activity-actions { margin-top: 10px; }
    #region .lead { color: #dcebe6; font-size: 15px; line-height: 1.82; max-width: 1120px; }
    #region .panel h3 { font-size: 20px; }
    #region .mini { color: #c7d5d0; font-size: 13px; line-height: 1.7; }
    #region .matrix { grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 12px; }
    #region .province-cell {
      min-height: 102px; padding: 14px; background: rgba(255,255,255,.06);
      border-color: rgba(255,255,255,.12);
    }
    #region .province-cell strong { font-size: 17px; font-weight: 800; color: #f7fffb; line-height: 1.2; }
    #region .province-cell span { color: #d7e4df; font-size: 13px; line-height: 1.5; }
    #region .bar-row { grid-template-columns: 160px 1fr 82px; gap: 14px; font-size: 14px; }
    #region .bar-row > div:first-child { color: #f6fff9; font-weight: 700; }
    #region .bar-row > div:last-child { color: #f2faf5; font-weight: 700; text-align: right; }
    #region .bar-track { height: 12px; background: rgba(255,255,255,.08); }
    #region .grid-2 { grid-template-columns: minmax(0, 1.08fr) minmax(0, .92fr); align-items: start; }
    #suppliers .grid-2, #platform .grid-2 { align-items: start; }
    #suppliers .bar-row { grid-template-columns: minmax(220px, 240px) 1fr 42px; gap: 10px; margin: 9px 0; font-size: 12.5px; }
    #suppliers .bar-row > div:first-child {
      line-height: 1.35; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
    }
    #suppliers .quality .kpi { min-height: 0; padding: 16px; }
    #suppliers .quality .kpi .value { font-size: 28px; margin-top: 10px; }
    #platform .panel { padding: 18px; }
    #platform .platform-item { padding: 11px 0; }
    #platform .platform-item-head strong {
      font-size: 13px; line-height: 1.35; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
    }
    #platform .platform-item-meta { margin: 6px 0 2px; font-size: 12.5px; }
    #platform .mini { margin-bottom: 12px; }
    .footnote { color: var(--muted); font-size: 12px; line-height: 1.7; margin-top: 24px; }
    .footer { padding: 34px 6vw; color: var(--muted); font-size: 12px; }
    @media (max-width: 1100px) {
      .hero { grid-template-columns: 1fr; }
      .kpi-grid, .case-grid { grid-template-columns: repeat(2, minmax(0,1fr)); }
      .activity-list { grid-template-columns: 1fr; }
      .grid-2, .grid-3 { grid-template-columns: 1fr; }
      .matrix { grid-template-columns: repeat(4, minmax(0,1fr)); }
      .nav { display: none; }
    }
    @media (max-width: 640px) {
      .section, .hero { padding-left: 18px; padding-right: 18px; }
      .kpi-grid, .case-grid { grid-template-columns: 1fr; }
      .matrix { grid-template-columns: repeat(2, minmax(0,1fr)); }
      .bar-row { grid-template-columns: 110px 1fr 48px; }
      .input { min-width: 100%; }
    }
  </style>
</head>
<body>
  <header class="topbar">
    <div class="brand"><span class="brand-mark"></span><span>低空侦测市场数据报告</span></div>
    <nav class="nav">
      <a href="#overview">总览</a>
      <a href="#demand">需求</a>
      <a href="#region">区域</a>
      <a href="#equipment">设备</a>
      <a href="#platform">平台</a>
      <a href="#cases">案例</a>
      <a href="#buyers">发包单位</a>
      <a href="#table">明细</a>
    </nav>
  </header>

  <section class="hero" id="overview">
    <div>
      <div class="eyebrow">Market Intelligence · 2023-2026 · Public Bidding Samples</div>
      <h1>侦测产品体系市场项目数据分析报告</h1>
      <p class="subtitle">基于公开招投标、中标公告、成交公告和合同信息整理的低空侦测反制项目样本库，系统分析需求场景、区域分布、设备形态、重大活动保障、价格锚点和中标单位格局，为浙大启真低空安全运营产品体系提供市场证据。</p>
      <div class="hero-actions">
        <span class="pill">样本口径：中标/成交/合同</span>
        <span class="pill">不倒推未披露数量</span>
        <span class="pill">官方来源与转载来源分级标注</span>
        <span class="pill">生成时间：$($meta.generatedAt)</span>
      </div>
      <div class="kpi-grid">
        <div class="kpi"><div class="label">结构化项目样本</div><div class="value">$totalProjects</div><div class="note">2023-2026年公开可检索中标、成交和合同记录</div></div>
        <div class="kpi"><div class="label">覆盖省级区域</div><div class="value">$provinceCount</div><div class="note">含脱敏未识别样本，独立留痕不强行归省</div></div>
        <div class="kpi"><div class="label">可解析金额合计</div><div class="value">$amountTotal</div><div class="note">万元，$amountCount 条可解析金额，均值约 $amountAvg 万元</div></div>
        <div class="kpi"><div class="label">设备明细行</div><div class="value">$equipmentLineCount</div><div class="note">按设备名称、类型、数量、品牌、型号拆分</div></div>
      </div>
    </div>
    <div class="city-panel" aria-label="未来城市低空安全示意图">
      <svg class="city-svg" viewBox="0 0 760 520" role="img">
        <defs>
          <linearGradient id="beam" x1="0" x2="1">
            <stop offset="0" stop-color="#55e6a5" stop-opacity=".9"/>
            <stop offset="1" stop-color="#4fd7ff" stop-opacity=".25"/>
          </linearGradient>
        </defs>
        <rect x="0" y="0" width="760" height="520" fill="rgba(8,13,12,.25)"/>
        <g stroke="rgba(85,230,165,.18)" stroke-width="1">
          <path d="M40 420 C180 300 320 490 500 330 S710 250 740 180" fill="none"/>
          <path d="M20 120 C200 210 380 70 720 150" fill="none"/>
          <path d="M80 260 H700"/>
          <path d="M120 70 V470 M240 50 V470 M360 30 V470 M480 50 V470 M600 80 V470"/>
        </g>
        <g fill="rgba(85,230,165,.12)" stroke="rgba(85,230,165,.45)">
          <rect x="70" y="315" width="72" height="145"/><rect x="160" y="250" width="88" height="210"/>
          <rect x="270" y="340" width="55" height="120"/><rect x="345" y="205" width="92" height="255"/>
          <rect x="460" y="285" width="74" height="175"/><rect x="552" y="230" width="110" height="230"/>
        </g>
        <g stroke="url(#beam)" stroke-width="2" fill="none">
          <circle cx="380" cy="252" r="72"/><circle cx="380" cy="252" r="132" opacity=".65"/><circle cx="380" cy="252" r="198" opacity=".35"/>
        </g>
        <g fill="#4fd7ff">
          <circle cx="222" cy="152" r="4"/><circle cx="598" cy="118" r="4"/><circle cx="500" cy="304" r="4"/>
        </g>
        <g stroke="#f5c15d" stroke-width="2" fill="none">
          <path d="M222 152 l20 -8 l-10 24 z"/><path d="M598 118 l22 6 l-20 16 z"/>
        </g>
        <g fill="rgba(255,255,255,.9)" font-size="18" font-family="Arial">
          <text x="42" y="44">Low Altitude Security Grid</text>
          <text x="406" y="252" font-size="13" fill="#aef7d5">Fusion Center</text>
        </g>
      </svg>
    </div>
  </section>

  <section class="section" id="conclusions">
    <div class="section-head">
      <div>
        <h2>核心判断</h2>
        <p class="lead">公开项目样本显示，低空侦测反制市场已经进入订单验证期。采购对象从单点硬件，扩展为系统平台、租赁服务、重大活动保障、敏感目标防护和城市级低空治理能力。</p>
      </div>
    </div>
    <div class="grid-3">
      <div class="insight"><b>判断一：</b>常态巡防是基本盘。公安、特警、分局、警用装备、低空管控前端等项目构成最大样本，占据项目数量主体。</div>
      <div class="insight"><b>判断二：</b>重大活动样本需分层查看。当前库中显性重大活动项目为12条，另有18条服务、租赁、装备或平台相关记录；后者只作为相关样本保留，不直接推断采购动机或实际用途。</div>
      <div class="insight"><b>判断三：</b>系统和服务正在抬头。系统平台/管控软件涉及36个项目，服务/租赁涉及13个项目，说明客户正在购买持续能力而非一次性设备。</div>
    </div>
  </section>

  <section class="section" id="demand">
    <div class="section-head">
      <div>
        <h2>需求类别结构</h2>
        <p class="lead">按业务场景划分为日常巡防、重大活动保障、园区运营、敏感目标防护和应急处置。分类采用主需求+兼具需求口径，避免把复合型采购误判为单一场景，点击条形可下钻到项目明细。</p>
      </div>
    </div>
    <div class="grid-2">
      <div class="panel">
        <h3>项目数量分布</h3>
        <div class="mini">日常巡防为底座，敏感目标防护为刚需，重大活动保障具有强宣传和快速成交属性。</div>
        <div id="demandBars"></div>
      </div>
      <div class="panel">
        <h3>金额分布</h3>
        <div class="mini">仅统计可解析金额项目，未披露金额不作估算。</div>
        <div id="demandAmountBars"></div>
      </div>
    </div>
    <div class="panel" style="margin-top:18px;">
      <div class="drill-head">
        <div>
          <h3>需求类别下钻</h3>
          <div class="mini">点击左侧数量条或右侧金额条，查看该需求类别对应的项目明细、地区分布和代表项目。</div>
        </div>
        <div class="badge" id="demandDrillBadge">等待选择</div>
      </div>
      <div id="demandDrilldown" class="mini">先点任一需求类别，我会把该场景下的项目展开给你看。</div>
    </div>
  </section>

  <section class="section" id="region">
    <div class="section-head">
      <div>
        <h2>区域热力与市场优先级</h2>
        <p class="lead">省份分析优先看可解析金额总量，项目数只作辅助参考。浙江、四川、广东、内蒙古、江苏等地在金额表现上更突出；未识别样本多来自脱敏军警或转载平台，不强行归省，点击省份格子或条形可下钻。</p>
      </div>
    </div>
    <div class="grid-2">
      <div class="panel">
        <h3>省份项目热力矩阵</h3>
        <div class="mini">颜色越亮代表可解析金额越高，格内同时保留项目数作为辅助信息。</div>
        <div class="matrix" id="provinceMatrix"></div>
      </div>
      <div class="panel">
        <h3>TOP金额省份</h3>
        <div id="provinceBars"></div>
      </div>
    </div>
    <div class="panel" style="margin-top:18px;">
      <div class="drill-head">
        <div>
          <h3>区域热力下钻</h3>
          <div class="mini">点击省份格子或金额条，查看该区域的项目数、金额、需求结构和代表项目。</div>
        </div>
        <div class="badge" id="regionDrillBadge">等待选择</div>
      </div>
      <div id="regionDrilldown" class="mini">先点任一省份，我会展开该省的项目明细。</div>
    </div>
  </section>

  <section class="section" id="equipment">
    <div class="section-head">
      <div>
        <h2>设备与能力形态</h2>
        <p class="lead">设备明细不对未披露台套数做经验倒推。租赁和保障项目按1项服务记录，具体设备数量以采购文件或响应文件为准；点击设备类型或能力形态可下钻。</p>
      </div>
    </div>
    <div class="grid-2">
      <div class="panel">
        <h3>设备类型结构</h3>
        <div class="mini">按设备类型统计项目数，点击可查看对应项目清单。</div>
        <div id="equipmentBars"></div>
      </div>
      <div class="panel">
        <h3>能力形态结构</h3>
        <div class="mini">按软硬件属性统计项目数，展示采购更偏硬件、平台还是服务。</div>
        <div id="capabilityBars"></div>
      </div>
    </div>
    <div class="panel" style="margin-top:18px;">
      <div class="drill-head">
        <div>
          <h3>设备与能力下钻</h3>
          <div class="mini">点击设备类型或能力形态，查看该形态对应的项目明细、区域分布和代表项目。</div>
        </div>
        <div class="badge" id="equipmentDrillBadge">等待选择</div>
      </div>
      <div id="equipmentDrilldown" class="mini">先点任一设备类型或能力形态，我会把对应项目列出来。</div>
    </div>
  </section>

  <section class="section" id="platform">
    <div class="section-head">
      <div>
        <h2>信息化平台项目历年合同额趋势</h2>
        <p class="lead">以“平台、系统、管控、指控、显控、低空云、智联、融合、信息化、数字孪生、态势、服务平台”为关键词筛选的平台类项目共${platformProjectCount}条，其中${platformAmountCount}条披露金额，合计${platformAmountTotal}万元，占全部可解析金额的${platformShareOfTotal}%。2025年是明显放量拐点，2026年仅为截至当前样本截面，不宜与完整年度直接对比。</p>
      </div>
    </div>
    <div class="kpi-grid">
      <div class="kpi"><div class="label">平台类项目</div><div class="value">$platformProjectCount</div><div class="note">关键词口径筛选后的项目总数</div></div>
      <div class="kpi"><div class="label">可解析金额项目</div><div class="value">$platformAmountCount</div><div class="note">披露金额并可用于趋势统计</div></div>
      <div class="kpi"><div class="label">合同额合计</div><div class="value">$platformAmountTotal</div><div class="note">万元，均值约 $platformAvgAmount 万元/项</div></div>
      <div class="kpi"><div class="label">2024-2025增幅</div><div class="value">${platform2024To2025Growth}%</div><div class="note">2025年相较2024年出现明显放量</div></div>
    </div>
    <div class="grid-2" style="margin-top:18px;">
      <div class="panel">
        <h3>年度合同额走势</h3>
        <div class="mini">按可解析金额项目统计，2026年仅为当前样本截面。</div>
        $platformTrendRowsHtml
      </div>
      <div class="panel">
        <h3>代表性平台项目</h3>
        <div class="mini">按金额排序，便于识别高金额项目和供应商结构。</div>
        $platformTopRowsHtml
      </div>
    </div>
    <div class="grid-3" style="margin-top:18px;">
      <div class="insight"><b>阶段一：</b>2023年平台类项目只有1个、102.10万元，还是起步期。</div>
      <div class="insight"><b>阶段二：</b>2024年升至4个、237.44万元，较2023年增长约${platform2023To2024Growth}%。</div>
      <div class="insight"><b>阶段三：</b>2025年跳升至11个、1500.66万元，较2024年增长约${platform2024To2025Growth}%，平台化采购明显加速。</div>
      <div class="insight"><b>阶段四：</b>2026年已有3个、671.98万元，但样本仍是截面数据，不能直接按全年比较。</div>
      <div class="insight"><b>判断：</b>信息化平台类项目的合同额演变，比纯设备采购更像“先试点、后集成、再放量”的曲线。</div>
      <div class="insight"><b>提示：</b>若后续继续扩样，平台项目的增长更可能来自系统联动、管控软件和城市级运营平台，而不只是单一硬件。</div>
    </div>
  </section>

  <section class="section" id="activity">
    <div class="section-head">
      <div>
        <h2>重大活动保障相关样本</h2>
        <p class="lead">本区只展示公开项目字段、证据摘要和来源链接状态。显性样本与相关装备服务样本分开查看；相关样本不等同于实际用于重大活动，也不据此推断采购动机。</p>
      </div>
    </div>
    <div class="kpi-grid">
      <div class="kpi drillable active" role="button" tabindex="0" data-major-target="all" title="点击查看全部样本"><div class="label">相关样本记录</div><div class="value">$majorPoolCount</div><div class="note">仅作样本清单展示 <span class="click-hint">点击查看</span></div></div>
      <div class="kpi drillable" role="button" tabindex="0" data-major-target="文本显性样本" title="点击查看文本显性样本"><div class="label">文本显性样本</div><div class="value">$explicitMajor</div><div class="note">标题或正文直接出现活动/赛事/场馆等信息 <span class="click-hint">点击查看</span></div></div>
      <div class="kpi drillable" role="button" tabindex="0" data-major-target="服务/租赁相关样本" title="点击查看服务/租赁相关样本"><div class="label">服务/租赁相关</div><div class="value">$highMajor</div><div class="note">按原表字段保留，不外推用途 <span class="click-hint">点击查看</span></div></div>
      <div class="kpi drillable" role="button" tabindex="0" data-major-target="装备/平台相关样本" title="点击查看装备/平台相关样本"><div class="label">装备/平台相关</div><div class="value">$midMajor</div><div class="note">按原表字段保留，不外推用途 <span class="click-hint">点击查看</span></div></div>
    </div>
    <div class="panel" style="margin-top:18px;">
      <div class="drill-head">
        <div>
          <h3>活动保障样本下钻</h3>
          <div class="mini">点击上方任一指标即可切换。这里只展示公开记录字段和证据摘要，不额外归纳项目用途。</div>
        </div>
        <div class="badge" id="majorDrillBadge">等待选择</div>
      </div>
      <div id="majorDrilldown" class="mini">点击上方标签，查看项目字段和证据摘要。</div>
    </div>
  </section>

  <section class="section" id="cases">
    <div class="section-head">
      <div>
        <h2>代表项目案例</h2>
        <p class="lead">以下案例按最新项目库重选，用于理解价格锚点、设备组合、服务采购、城市平台和浙江本地市场机会。</p>
      </div>
    </div>
    <div class="case-grid">
      $caseCardsHtml
    </div>
  </section>

  <section class="section" id="suppliers">
    <div class="section-head">
      <div>
        <h2>中标单位格局</h2>
        <p class="lead">公开样本显示，中标方既包括专业低空安全厂商，也包括运营商、系统集成商、本地科技公司。大量项目因脱敏或转载源限制未披露供应商，需持续回溯官方原文。</p>
      </div>
    </div>
    <div class="grid-2">
      <div class="panel">
        <h3>可识别中标单位TOP</h3>
        <div id="supplierBars"></div>
      </div>
      <div class="panel">
        <h3>数据质量</h3>
        <div class="quality">
          <div class="kpi"><div class="label">完整记录</div><div class="value">$fullCount</div><div class="note">省份、采购人、金额、供应商、时间、链接较完整</div></div>
          <div class="kpi"><div class="label">较完整记录</div><div class="value">$partialCount</div><div class="note">关键字段较完整但仍有缺项</div></div>
          <div class="kpi"><div class="label">待复核记录</div><div class="value">$reviewCount</div><div class="note">脱敏、转载或关键字段不足</div></div>
        </div>
      </div>
    </div>
  </section>

  <section class="section" id="buyers">
    <div class="section-head">
      <div>
        <h2>发包单位分析</h2>
        <p class="lead">样本不是单一总盘，而是公安条线、涉密单位、机场能源、园区高校和大量转载脱敏信息交织形成的碎片化市场。不同发包主体的采购语言差异很大，决定了产品包装方式也不能一刀切。</p>
      </div>
    </div>
    <div class="kpi-grid">
      <div class="kpi"><div class="label">公安司法与公共安全</div><div class="value">$buyerPublicCount</div><div class="note">市局、分局、特警、边境、铁路公安、监所等</div></div>
      <div class="kpi"><div class="label">军队/涉密脱敏单位</div><div class="value">$buyerMilitaryCount</div><div class="note">某部、军分区、民兵和涉密脱敏条目</div></div>
      <div class="kpi"><div class="label">基础设施类主体</div><div class="value">$buyerInfraCount</div><div class="note">机场、电力、核电、石化、交通等敏感设施</div></div>
      <div class="kpi"><div class="label">未披露/转载脱敏</div><div class="value">$buyerHiddenCount</div><div class="note">公开摘要不足，需回溯官方原文</div></div>
    </div>
    <div class="grid-2" style="margin-top:18px;">
      <div class="panel">
        <h3>发包主体类型</h3>
        <div class="mini">按发包采购单位与项目标题综合归类。<span class="click-hint">点击条形展开具体单位和代表项目</span></div>
        <div id="buyerCategoryBars"></div>
      </div>
      <div class="panel">
        <h3>重点发包单位</h3>
        <div class="mini">按公开可识别主体统计，反映高频采购组织者。<span class="click-hint">点击条形查看该单位项目清单</span></div>
        <div id="buyerTopBars"></div>
      </div>
    </div>
    <div class="panel" style="margin-top:18px;">
      <div class="drill-head">
        <div>
          <h3>单位下钻</h3>
          <div class="mini">点击左侧“发包主体类型”或右侧“重点发包单位”查看具体单位清单。</div>
        </div>
        <div class="badge" id="buyerDrillBadge">等待选择</div>
      </div>
      <div id="buyerDrilldown" class="mini">先点左侧或右侧对应条形，我会把该类发包单位和代表项目展开。</div>
    </div>
  </section>

  <section class="section" id="strategy">
    <div class="section-head">
      <div>
        <h2>对浙大启真的产品启示</h2>
        <p class="lead">市场样本更像是在提醒：这不是一个可以用单一方案概括的市场。不同采购人关心的东西并不一样，有的先看能不能发现，有的先看能不能管住，有的先看能不能快交付，浙大启真最好把这些差异当成产品设计的起点，而不是先套一个统一口径。</p>
      </div>
    </div>
    <div class="grid-3">
      <div class="insight"><b>先分场景，再定产品形态。</b>公安巡防、重大活动、园区运营、敏感目标和应急处置，采购目标差别很大，不能先假定一个“标准版”能覆盖全部。</div>
      <div class="insight"><b>先解决能稳定交付的部分。</b>发现、告警、留痕、工单这些基础链路更适合先固化，反制、联动和深度运营可以按场景单独扩展。</div>
      <div class="insight"><b>先把服务能力做出来。</b>不少样本买的不是纯设备，而是租赁、值守、管控和保障，说明客户愿意为持续运行买单。</div>
      <div class="insight"><b>先把客户语言翻译清楚。</b>公安重秩序和闭环，机场重边界和净空，园区重体验和可复用，涉密单位重权限和留痕，表达方式要跟着变。</div>
      <div class="insight"><b>先保留组合空间。</b>设备、平台、运营不要一开始就捆死，后续是否自建、合建、租赁或外包，应该留给项目条件决定。</div>
      <div class="insight"><b>先验证收入结构。</b>如果一次性建设占比过高，而运维、演练、报表和活动保障没有单列，项目后续很容易回到交付导向。</div>
    </div>
  </section>

  <section class="section" id="table">
    <div class="section-head">
      <div>
        <h2>项目明细检索</h2>
        <p class="lead">内嵌${totalProjects}条原始样本，按同项目合并后展示${displayProjectCount}条项目记录，默认按中标/成交时间倒序排列。可按关键词、需求类别、省份、年份筛选；金额、设备数量、供应商等未披露字段均按公开信息原样留痕。</p>
      </div>
    </div>
    <div class="panel">
      <div class="table-tools">
        <input class="input" id="searchInput" placeholder="搜索项目、采购单位、中标单位、设备名称">
        <select class="select" id="provinceFilter"><option value="">全部省份</option></select>
        <select class="select" id="demandFilter"><option value="">全部需求类别</option></select>
        <select class="select" id="yearFilter"><option value="">全部年份</option></select>
      </div>
      <div class="link-legend">
        <span>来源链接校核：$openLinkCount 个可打开，$blockedLinkCount 个当前暂打不开。</span>
        <span class="source-link open">可打开</span>
        <span class="source-link blocked">暂打不开</span>
      </div>
      <div class="table-wrap">
        <table>
          <thead><tr><th>省份</th><th>项目名称</th><th>需求类别</th><th>金额</th><th>中标单位</th><th>时间</th><th>设备/服务</th><th>来源</th></tr></thead>
          <tbody id="projectTable"></tbody>
        </table>
      </div>
      <div class="footnote">数据口径：公开中标、成交、合同样本。表格默认按时间倒序和同项目合并展示，重复公告、不同转载源或合同/中标结果的同项目条目会归并到同一行，原始${totalProjects}条样本保留在底层数据；未披露金额和数量不做推算。</div>
    </div>
  </section>

  <footer class="footer">
    数据文件：全国_低空侦测反制中标项目_2023-2026_全量汇总.csv、按需求分类.csv、设备明细长表.csv、重大活动保障_显性及潜在打包项目.csv。报告为离线单文件，可直接打开审阅。
  </footer>

  <script>
    const META = $(Json $meta);
    const PROJECTS = $(Json $projectsSlim);
    const PROVINCES = $(Json $topProvinceByAmount);
    const DEMANDS = $(Json $demandSummary);
    const EQUIPMENT = $(Json $equipmentSummary);
    const CAPABILITIES = $(Json $capabilitySummary);
    const YEARS = $(Json $yearSummary);
    const PRICE_BANDS = $(Json $priceBands);
    const SUPPLIERS = $(Json $supplierSummary);
    const BUYER_CATEGORIES = $(Json $buyerCategorySummary);
    const BUYER_CATEGORY_DETAILS = $(Json $buyerCategoryDetail);
    const BUYER_TOPS = $(Json $buyerTopSummary);
    const TOP_AMOUNT = $(Json $topAmount);
    const MAJOR_ACTIVITY = $(Json $majorActivitySlim);
    const BUYER_DETAIL_CATEGORIES = ['企业园区/高校科研/运营主体', '政府部门及事业单位'];

    function num(v) { const n = Number(v || 0); return Number.isFinite(n) ? n : 0; }
    function maxOf(arr, key) { return Math.max(1, ...arr.map(x => num(x[key]))); }
    function esc(v) {
      return String(v || '').replace(/[&<>"']/g, function(ch) {
        return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]);
      });
    }
    function sourceMeta(level) {
      const text = String(level || '');
      if (text.startsWith('A')) return {label:'A 官方', cls:'official'};
      if (text.startsWith('B')) return {label:'B 转载', cls:'reprint'};
      return {label:'未披露', cls:'hidden'};
    }
    function dateScore(x) {
      const text = String(x.排序日期文本 || x.中标公告时间 || '');
      const m = text.match(/(\d{4})[年/-](\d{1,2})[月/-](\d{1,2})/);
      if (!m) return 0;
      return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).getTime();
    }
    function sourceLinkHtml(x, fullLabel = false) {
      const url = String(x.来源链接 || '').trim();
      const state = String(x.来源链接状态 || '');
      const reason = esc(x.来源链接说明 || '');
      if (!url) return '<span class="source-link blocked" title="未提供来源链接">无链接</span>';
      if (state === '可打开') {
        return '<a class="source-link open" href="' + esc(url) + '" target="_blank" rel="noopener">' + (fullLabel ? '打开来源' : '打开') + '</a>';
      }
      return '<span class="source-link blocked" title="' + reason + '">暂打不开</span>';
    }
    function barRows(el, arr, labelKey, valueKey, opts = {}) {
      const max = maxOf(arr, valueKey);
      el.innerHTML = arr.map((x, i) => {
        const value = num(x[valueKey]);
        const cls = opts.palette === 'warm' ? 'amber' : opts.palette === 'violet' ? 'violet' : '';
        const rowClass = 'bar-row' + (opts.drillable ? ' drillable' : '');
        return '<div class="' + rowClass + '" data-label="' + esc(x[labelKey]) + '"><div title="' + esc(x[labelKey]) + '">' + esc(x[labelKey]) +
          '</div><div class="bar-track"><div class="bar-fill ' + cls + '" style="width:' +
          Math.max(3, value / max * 100) + '%"></div></div><div>' +
          (opts.money ? value.toFixed(1) : value) + '</div></div>';
      }).join('');
    }
    function groupStats(rows, key) {
      const map = new Map();
      rows.forEach(x => {
        const label = String(x[key] || '未披露');
        const item = map.get(label) || {label: label, count: 0, amount: 0};
        item.count += 1;
        item.amount += num(x.金额万元);
        map.set(label, item);
      });
      return [...map.values()].sort((a, b) => b.count - a.count || b.amount - a.amount || String(a.label).localeCompare(String(b.label), 'zh-CN'));
    }
    function chipsHtml(rows, key, limit = 4, emptyText = '未披露') {
      const items = groupStats(rows, key).slice(0, limit);
      return items.length ? items.map(x => '<span class="chip">' + esc(x.label) + ' · ' + x.count + '项</span>').join('') : '<span class="chip">' + esc(emptyText) + '</span>';
    }
    function projectListHtml(rows, limit = 6) {
      return rows.slice(0, limit).map(x => (
        '<li><strong>' + esc(x.项目名称) + '</strong><div class="table-muted">' +
        esc(x.省份) + ' · ' + esc(x.中标公告时间) + ' · ' + esc(x.项目金额) + ' · ' + esc(x.承建中标单位) + '</div></li>'
      )).join('');
    }
    function sumAmount(rows) {
      return rows.reduce((sum, x) => sum + num(x.金额万元), 0);
    }
    function bindRowDrilldown(containerSelector, onActivate) {
      document.querySelectorAll(containerSelector + ' .bar-row').forEach(row => {
        const label = row.dataset.label || row.querySelector('div')?.textContent?.trim();
        if (!label) return;
        row.classList.add('drillable');
        row.setAttribute('role', 'button');
        row.setAttribute('tabindex', '0');
        const activate = () => onActivate(label, row);
        row.addEventListener('click', activate);
        row.addEventListener('keydown', e => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            activate();
          }
        });
      });
    }
    function bindCellDrilldown(containerSelector, onActivate) {
      document.querySelectorAll(containerSelector + ' .province-cell').forEach(cell => {
        const label = cell.dataset.label || cell.querySelector('strong')?.textContent?.trim();
        if (!label) return;
        cell.classList.add('drillable');
        cell.setAttribute('role', 'button');
        cell.setAttribute('tabindex', '0');
        const activate = () => onActivate(label, cell);
        cell.addEventListener('click', activate);
        cell.addEventListener('keydown', e => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            activate();
          }
        });
      });
    }
    function renderBuyerDetail(category) {
      const panel = document.getElementById('buyerDrilldown');
      const badge = document.getElementById('buyerDrillBadge');
      const item = BUYER_CATEGORY_DETAILS.find(x => x.主体类别 === category);
      if (!item) {
        panel.innerHTML = '先点左侧或右侧对应条形，我会把该类发包单位和代表项目展开。';
        badge.textContent = '等待选择';
        document.querySelectorAll('#buyerCategoryBars .bar-row').forEach(row => row.classList.remove('active'));
        return;
      }
      const units = (item.单位列表 || []).map(u => '<span class="chip">' + esc(u) + '</span>').join('');
      const examples = (item.项目示例 || []).map(p => '<li>' + esc(p) + '</li>').join('');
      panel.innerHTML = '<div class="drill-grid">' +
        '<div><div class="mini">具体单位</div><div class="chip-list">' + units + '</div></div>' +
        '<div><div class="mini">代表项目</div><ul class="drill-list">' + examples + '</ul></div>' +
      '</div>';
      badge.textContent = item.主体类别 + ' · ' + num(item.单位数) + ' 个单位';
      document.querySelectorAll('#buyerCategoryBars .bar-row').forEach(row => {
        row.classList.toggle('active', row.dataset.label === category);
      });
      document.querySelectorAll('#buyerTopBars .bar-row').forEach(row => row.classList.remove('active'));
    }
    function renderBuyerUnitDetail(unit) {
      const panel = document.getElementById('buyerDrilldown');
      const badge = document.getElementById('buyerDrillBadge');
      const rows = PROJECTS.filter(x => x.发包采购单位 === unit);
      if (!rows.length) {
        panel.innerHTML = '先点左侧或右侧对应条形，我会把该类发包单位和代表项目展开。';
        badge.textContent = '等待选择';
        document.querySelectorAll('#buyerTopBars .bar-row').forEach(row => row.classList.remove('active'));
        return;
      }
      const provinces = [...new Set(rows.map(x => x.省份).filter(Boolean))].slice(0, 4);
      const examples = rows.slice(0, 6).map(x => (
        '<li><strong>' + esc(x.项目名称) + '</strong><div class="table-muted">' +
        esc(x.省份) + ' · ' + esc(x.项目金额) + ' · ' + esc(x.中标公告时间) + '</div></li>'
      )).join('');
      const amount = rows.reduce((sum, x) => sum + num(x.金额万元), 0).toFixed(2);
      panel.innerHTML = '<div class="drill-grid">' +
        '<div><div class="mini">覆盖省份</div><div class="chip-list">' + (provinces.length ? provinces.map(v => '<span class="chip">' + esc(v) + '</span>').join('') : '<span class="chip">未披露</span>') + '</div></div>' +
        '<div><div class="mini">代表项目</div><ul class="drill-list">' + examples + '</ul></div>' +
      '</div>';
      badge.textContent = unit + ' · ' + rows.length + ' 项 · ' + amount + ' 万元';
      document.querySelectorAll('#buyerTopBars .bar-row').forEach(row => {
        row.classList.toggle('active', row.dataset.label === unit);
      });
      document.querySelectorAll('#buyerCategoryBars .bar-row').forEach(row => row.classList.remove('active'));
    }
    function renderDemandDetail(category) {
      const panel = document.getElementById('demandDrilldown');
      const badge = document.getElementById('demandDrillBadge');
      const rows = PROJECTS.filter(x => x.主需求类别 === category).slice().sort((a, b) => dateScore(b) - dateScore(a));
      if (!rows.length) {
        panel.innerHTML = '先点任一需求类别，我会把该场景下的项目展开给你看。';
        badge.textContent = '等待选择';
        document.querySelectorAll('#demandBars .bar-row, #demandAmountBars .bar-row').forEach(row => row.classList.remove('active'));
        return;
      }
      const amount = sumAmount(rows).toFixed(2);
      const provinces = chipsHtml(rows, '省份', 5);
      const examples = projectListHtml(rows, 6);
      panel.innerHTML = '<div class="drill-grid">' +
        '<div><div class="mini">覆盖省份</div><div class="chip-list">' + provinces + '</div></div>' +
        '<div><div class="mini">代表项目</div><ul class="drill-list">' + examples + '</ul></div>' +
      '</div>';
      badge.textContent = category + ' · ' + rows.length + ' 项 · ' + amount + ' 万元';
      document.querySelectorAll('#demandBars .bar-row, #demandAmountBars .bar-row').forEach(row => {
        row.classList.toggle('active', row.dataset.label === category);
      });
    }
    function renderRegionDetail(province) {
      const panel = document.getElementById('regionDrilldown');
      const badge = document.getElementById('regionDrillBadge');
      const rows = PROJECTS.filter(x => x.省份 === province).slice().sort((a, b) => dateScore(b) - dateScore(a));
      if (!rows.length) {
        panel.innerHTML = '先点任一省份，我会展开该省的项目明细。';
        badge.textContent = '等待选择';
        document.querySelectorAll('#provinceMatrix .province-cell, #provinceBars .bar-row').forEach(node => node.classList.remove('active'));
        return;
      }
      const amount = sumAmount(rows).toFixed(2);
      const demandChips = chipsHtml(rows, '主需求类别', 5);
      const examples = projectListHtml(rows, 6);
      panel.innerHTML = '<div class="drill-grid">' +
        '<div><div class="mini">主需求结构</div><div class="chip-list">' + demandChips + '</div></div>' +
        '<div><div class="mini">代表项目</div><ul class="drill-list">' + examples + '</ul></div>' +
      '</div>';
      badge.textContent = province + ' · ' + rows.length + ' 项 · ' + amount + ' 万元';
      document.querySelectorAll('#provinceMatrix .province-cell, #provinceBars .bar-row').forEach(node => {
        node.classList.toggle('active', (node.dataset.label || node.querySelector('strong')?.textContent?.trim()) === province);
      });
    }
    function renderEquipmentDetail(label, mode) {
      const panel = document.getElementById('equipmentDrilldown');
      const badge = document.getElementById('equipmentDrillBadge');
      const rows = PROJECTS.filter(x => {
        if (mode === '能力形态') return String(x.软硬件属性 || '') === label;
        return String(x.设备类型清单 || '').indexOf(label) !== -1;
      }).slice().sort((a, b) => dateScore(b) - dateScore(a));
      if (!rows.length) {
        panel.innerHTML = '先点任一设备类型或能力形态，我会把对应项目列出来。';
        badge.textContent = '等待选择';
        document.querySelectorAll('#equipmentBars .bar-row, #capabilityBars .bar-row').forEach(node => node.classList.remove('active'));
        return;
      }
      const amount = sumAmount(rows).toFixed(2);
      const provinceChips = chipsHtml(rows, '省份', 5);
      const examples = projectListHtml(rows, 6);
      panel.innerHTML = '<div class="drill-grid">' +
        '<div><div class="mini">覆盖省份</div><div class="chip-list">' + provinceChips + '</div></div>' +
        '<div><div class="mini">代表项目</div><ul class="drill-list">' + examples + '</ul></div>' +
      '</div>';
      badge.textContent = mode + ' · ' + label + ' · ' + rows.length + ' 项 · ' + amount + ' 万元';
      document.querySelectorAll('#equipmentBars .bar-row').forEach(node => {
        node.classList.toggle('active', (node.dataset.label || '') === label && mode !== '能力形态');
      });
      document.querySelectorAll('#capabilityBars .bar-row').forEach(node => {
        node.classList.toggle('active', (node.dataset.label || '') === label && mode === '能力形态');
      });
    }
    function bindBuyerDrilldown() {
      const rows = document.querySelectorAll('#buyerCategoryBars .bar-row');
      rows.forEach(row => {
        const label = row.dataset.label || row.querySelector('div')?.textContent?.trim();
        if (BUYER_DETAIL_CATEGORIES.includes(label)) {
          row.classList.add('drillable');
          row.setAttribute('role', 'button');
          row.setAttribute('tabindex', '0');
          row.title = '点击查看' + label + '的具体单位';
          const activate = () => renderBuyerDetail(label);
          row.addEventListener('click', activate);
          row.addEventListener('keydown', e => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault();
              activate();
            }
          });
        }
      });
    }
    function bindBuyerTopDrilldown() {
      const rows = document.querySelectorAll('#buyerTopBars .bar-row');
      rows.forEach(row => {
        const label = row.dataset.label || row.querySelector('div')?.textContent?.trim();
        if (label) {
          row.classList.add('drillable');
          row.setAttribute('role', 'button');
          row.setAttribute('tabindex', '0');
          row.title = '点击查看' + label + '的项目清单';
          const activate = () => renderBuyerUnitDetail(label);
          row.addEventListener('click', activate);
          row.addEventListener('keydown', e => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.preventDefault();
              activate();
            }
          });
        }
      });
    }
    function renderMajorDetail(target) {
      const panel = document.getElementById('majorDrilldown');
      const badge = document.getElementById('majorDrillBadge');
      const levelMap = {
        all: '全部相关样本',
        '文本显性样本': '文本显性样本',
        '服务/租赁相关样本': '服务/租赁相关样本',
        '装备/平台相关样本': '装备/平台相关样本'
      };
      const rows = (target === 'all' ? MAJOR_ACTIVITY : MAJOR_ACTIVITY.filter(x => x.展示分组 === target))
        .slice()
        .sort((a, b) => dateScore(b) - dateScore(a));
      if (!rows.length) {
        panel.innerHTML = '点击上方标签，查看项目字段和证据摘要。';
        badge.textContent = '等待选择';
        document.querySelectorAll('#activity .kpi.drillable').forEach(card => card.classList.remove('active'));
        return;
      }
      const cards = rows.slice(0, 8).map(x => {
        const amount = esc(x.项目金额 || '公开信息未披露');
        const org = esc(x.发包采购单位 || '公开信息未披露');
        const time = esc(x.中标公告时间 || '公开信息未披露');
        const source = esc(x.来源等级 || '未披露');
        const evidence = esc(x.证据摘要 || '公开信息未披露');
        const link = sourceLinkHtml(x, true);
        return '<article class="activity-card">' +
          '<div class="activity-title">' + esc(x.项目名称) + '</div>' +
          '<div class="activity-meta">' +
            '<span>' + esc(x.展示分组) + '</span>' +
            '<span>' + esc(x.省份) + '</span>' +
            '<span>' + esc(x.省内城市区域) + '</span>' +
            '<span>' + time + '</span>' +
          '</div>' +
          '<div class="activity-org">' + org + ' · ' + amount + ' · ' + source + '</div>' +
          '<div class="activity-reason">证据：' + evidence + '</div>' +
          '<div class="activity-actions">' + link + '</div>' +
        '</article>';
      }).join('');
      panel.innerHTML = '<div class="activity-drill">' +
        '<div class="activity-summary"><div class="mini">当前筛选 ' + rows.length + ' 条。卡片仅展示公开字段和证据摘要，不将相关样本写成实际用途。</div></div>' +
        '<div class="activity-list">' + cards + '</div>' +
      '</div>';
      badge.textContent = levelMap[target] + ' · ' + rows.length + ' 条';
      document.querySelectorAll('#activity .kpi.drillable').forEach(card => {
        card.classList.toggle('active', (card.dataset.majorTarget || 'all') === target);
      });
    }
    function initBars() {
      barRows(document.getElementById('demandBars'), DEMANDS, '需求类别', '项目数', {drillable:true});
      barRows(document.getElementById('demandAmountBars'), DEMANDS, '需求类别', '可解析金额合计万元', {money:true, palette:'warm', drillable:true});
      barRows(document.getElementById('provinceBars'), PROVINCES.slice(0, 12), '省份', '可解析金额合计万元', {palette:'violet', money:true, drillable:true});
      barRows(document.getElementById('equipmentBars'), EQUIPMENT, '设备类型', '明细行数', {drillable:true});
      barRows(document.getElementById('capabilityBars'), CAPABILITIES, '能力形态', '项目数', {palette:'warm', drillable:true});
      barRows(document.getElementById('supplierBars'), SUPPLIERS.slice(0, 12), '中标单位', '项目数', {palette:'violet'});
      barRows(document.getElementById('buyerCategoryBars'), BUYER_CATEGORIES, '主体类别', '项目数', {palette:'warm'});
      barRows(document.getElementById('buyerTopBars'), BUYER_TOPS, '发包采购单位', '项目数', {palette:'violet'});
      bindBuyerDrilldown();
      bindBuyerTopDrilldown();
      bindRowDrilldown('#demandBars', (label) => renderDemandDetail(label));
      bindRowDrilldown('#demandAmountBars', (label) => renderDemandDetail(label));
      bindRowDrilldown('#provinceBars', (label) => renderRegionDetail(label));
      bindRowDrilldown('#equipmentBars', (label) => renderEquipmentDetail(label, '设备类型'));
      bindRowDrilldown('#capabilityBars', (label) => renderEquipmentDetail(label, '能力形态'));
      renderDemandDetail(DEMANDS[0]?.['需求类别'] || DEMANDS[0]?.需求类别 || '');
      renderEquipmentDetail(EQUIPMENT[0]?.['设备类型'] || EQUIPMENT[0]?.设备类型 || '', '设备类型');
      renderMajorDetail('all');
    }
    function initMatrix() {
      const amountMax = maxOf(PROVINCES, '可解析金额合计万元');
      const matrix = document.getElementById('provinceMatrix');
      matrix.innerHTML = PROVINCES.map(p => {
        const v = num(p.中标项目数);
        const alpha = .08 + num(p.可解析金额合计万元) / amountMax * .55;
        return '<div class="province-cell" data-label="' + esc(p.省份) + '" style="background:rgba(85,230,165,' + alpha +
          '); border-color:rgba(85,230,165,' + (.16 + alpha) + ');"><strong>' + esc(p.省份) +
          '</strong><span>金额 ' + num(p.可解析金额合计万元).toFixed(1) + ' 万 · ' + v + ' 项</span></div>';
      }).join('');
      bindCellDrilldown('#provinceMatrix', (label) => renderRegionDetail(label));
      renderRegionDetail(PROVINCES[0]?.省份 || '');
    }
    function unique(arr, key) { return [...new Set(arr.map(x => x[key]).filter(Boolean))].sort(); }
    function fillFilters() {
      const province = document.getElementById('provinceFilter');
      const demand = document.getElementById('demandFilter');
      const year = document.getElementById('yearFilter');
      unique(PROJECTS, '省份').forEach(v => province.insertAdjacentHTML('beforeend', '<option value="' + esc(v) + '">' + esc(v) + '</option>'));
      unique(PROJECTS, '主需求类别').forEach(v => demand.insertAdjacentHTML('beforeend', '<option value="' + esc(v) + '">' + esc(v) + '</option>'));
      unique(PROJECTS, '年份').forEach(v => year.insertAdjacentHTML('beforeend', '<option value="' + esc(v) + '">' + esc(v) + '</option>'));
    }
    function renderTable() {
      const q = document.getElementById('searchInput').value.trim().toLowerCase();
      const p = document.getElementById('provinceFilter').value;
      const d = document.getElementById('demandFilter').value;
      const y = document.getElementById('yearFilter').value;
      const rows = PROJECTS.filter(x => {
        const text = [x.项目名称, x.发包采购单位, x.承建中标单位, x.设备名称清单, x.省份].join(' ').toLowerCase();
        return (!q || text.includes(q)) && (!p || x.省份 === p) && (!d || x.主需求类别 === d) && (!y || x.年份 === y);
      })
        .sort((a, b) => dateScore(b) - dateScore(a) || num(b.金额万元) - num(a.金额万元) || String(a.项目名称 || '').localeCompare(String(b.项目名称 || ''), 'zh-CN'))
        .slice(0, 260);
      document.getElementById('projectTable').innerHTML = rows.map(x => {
        const meta = sourceMeta(x.来源等级);
        const link = sourceLinkHtml(x);
        const groupBadge = num(x.同组公告数) > 1 ? '<span class="table-tag">同组' + num(x.同组公告数) + '条公告</span>' : '';
        const sourceCount = num(x.同组来源数) > 1 ? '<span class="source-count">+' + num(x.同组来源数) + '源</span>' : '';
        return '<tr>' +
          '<td><div class="table-main">' + esc(x.省份) + '</div><div class="table-muted">' + esc(x.省内城市区域) + '</div></td>' +
          '<td><div class="table-main">' + esc(x.项目名称) + '</div><div class="table-muted">' + esc(x.发包采购单位) + '</div>' + groupBadge + '</td>' +
          '<td><div>' + esc(x.主需求类别) + '</div><div class="table-muted">' + esc(x.软硬件属性) + '</div></td>' +
          '<td>' + esc(x.项目金额) + '</td>' +
          '<td>' + esc(x.承建中标单位) + '</td>' +
          '<td>' + esc(x.中标公告时间) + '</td>' +
          '<td><div>' + esc(x.设备名称清单) + '</div><div class="table-muted">' + esc(x.设备数量清单) + '</div></td>' +
          '<td title="' + esc(x.来源等级) + '"><div class="source-cell"><span class="source-pill ' + meta.cls + '">' + meta.label + '</span>' + link + sourceCount + '</div></td>' +
        '</tr>';
      }).join('');
    }
    initBars();
    initMatrix();
    fillFilters();
    renderTable();
    renderBuyerDetail(null);
    ['searchInput','provinceFilter','demandFilter','yearFilter'].forEach(id => {
      document.getElementById(id).addEventListener('input', renderTable);
      document.getElementById(id).addEventListener('change', renderTable);
    });
    document.querySelectorAll('#activity .kpi.drillable').forEach(card => {
      const target = card.dataset.majorTarget || 'all';
      card.addEventListener('click', () => renderMajorDetail(target));
      card.addEventListener('keydown', e => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          renderMajorDetail(target);
        }
      });
    });
  </script>
</body>
</html>
"@

$utf8 = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($outPath, $html, $utf8)
[pscustomobject]@{
  输出文件 = $outPath
  项目数 = $totalProjects
  设备明细行 = $equipmentLineCount
  重大活动能力池 = $majorPoolCount
  可解析金额万元 = $amountTotal
}
