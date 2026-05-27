$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $base '按省份低空侦测中标项目CSV_2023-2026'
$main = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_全量汇总.csv'
$rootCopy = Join-Path $base '低空侦测招投标案例库_按省份全量_2023-2026.csv'
$longPath = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_设备明细长表.csv'

$oldDeviceCols = @(
  '项目ID',
  '设备名称清单',
  '设备类型清单',
  '设备数量清单',
  '设备规格型号清单',
  '设备品牌清单',
  '设备明细完整度',
  '设备明细来源',
  '设备明细备注'
)

function Clean([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return '公开信息未披露' }
  return (($s -replace '\s+', ' ').Trim())
}

function New-EquipmentItem($name, $type, $qty, $unit, $brand, $model, $basis, $confidence) {
  [pscustomobject]@{
    设备名称   = $name
    设备类型   = $type
    数量     = $qty
    单位     = $unit
    品牌     = $brand
    规格型号   = $model
    明细依据   = $basis
    明细置信度 = $confidence
  }
}

function Add-EquipmentItem([System.Collections.ArrayList]$list, $item) {
  foreach ($existing in $list) {
    if ($existing.设备名称 -eq $item.设备名称) { return }
    if ($existing.设备名称.Contains($item.设备名称) -or $item.设备名称.Contains($existing.设备名称)) { return }
  }
  [void]$list.Add($item)
}

function Infer-EquipmentType([string]$name, [string]$text) {
  $combined = "$name $text"
  if ($combined -match '频谱|无线电侦测|射频|探测定位|侦测预警|无源侦测') { return '侦测探测设备' }
  if ($combined -match '雷达') { return '雷达探测设备' }
  if ($combined -match '光电|云台') { return '光电跟踪设备' }
  if ($combined -match '察打一体') { return '察打一体侦测反制设备' }
  if ($combined -match '固定式|阵地|主动防御') { return '固定式反制/防御设备' }
  if ($combined -match '便携|手持|反制枪|干扰枪|背负') { return '便携/手持反制设备' }
  if ($combined -match '平台|系统|管控|监管|前端|低空防御') { return '系统平台/管控软件' }
  if ($combined -match '侦测反制|反制设备|反制装备|反制器材|反制装置|防御反制|主动防御|低空反制') { return '侦测反制装备/设备' }
  if ($combined -match '无人机[^反制]|Mavic|Mini|穿越机') { return '配套无人机/训练靶机' }
  if ($combined -match '服务|租赁|运维|保障') { return '服务/租赁' }
  return '侦测反制装备/设备'
}

function Get-EquipmentItems($row) {
  $text = Clean "$($row.项目名称) $($row.项目类型) $($row.发包采购单位) $($row.证据摘要) $($row.核验备注)"
  $items = New-Object System.Collections.ArrayList

  if ($row.项目名称 -match '泸州军分区民兵反无人机排装备器材采购项目') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机频谱侦测设备' '侦测探测设备' '2' '套' '安则' 'An-Wscan-S' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem '固定式无人机反制设备' '固定式反制/防御设备' '2' '套' '安则' 'An-Jam-03G' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem '察打一体无人机反制设备' '察打一体侦测反制设备' '1' '套' '安则' 'An-DJS' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem '便携式察打一体反制设备' '察打一体侦测反制设备' '2' '套' '安则' 'An-DJ' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem '手持式无人机反制设备' '便携/手持反制设备' '4' '套' '安则' 'Auav-b01' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem '无人机智能管控平台' '系统平台/管控软件' '1' '套' '安则' 'AZMS-V1' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem '终端' '配套计算/显示终端' '3' '台' 'Inspur 浪潮' 'NF5280M5' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem '无人机1' '配套无人机/训练靶机' '2' '台' 'DJI' 'Mavic 3 Pro' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem '无人机2' '配套无人机/训练靶机' '2' '台' 'DJI' 'Mini 4 Pro' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    Add-EquipmentItem $items (New-EquipmentItem 'DIY穿越机' '配套无人机/训练靶机' '2' '台' '光烨' '定制' '四川公共资源交易/四川政府采购中标公告主要标的信息' '高')
    return $items.ToArray()
  }

  if ($row.项目名称 -match '克州GAJ|特警支队.*反制侦测相关设备') {
    Add-EquipmentItem $items (New-EquipmentItem '手持无人机侦测设备' '侦测探测设备' '4' '套' '锐盾' 'RD-H2L' '证据摘要披露“手持无人机侦测设备 锐盾 RD-H2L 4”' '中')
  }
  if ($row.项目名称 -match '黄山市公安局黄山分局H2LPro') {
    Add-EquipmentItem $items (New-EquipmentItem 'H2LPro手持式无人机探测定位设备' '侦测探测设备' '公开信息未披露' '公开信息未披露' '华诺星空' 'H2LPro' '项目名称与证据摘要披露设备名称/型号' '中')
  }
  if ($row.项目名称 -match '宣城市公安局低空安全管控装备租赁服务') {
    Add-EquipmentItem $items (New-EquipmentItem '低空安全管控装备租赁服务' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '成交公告项目名称及需求摘要；具体设备数量未披露' '中')
  }
  if ($row.项目名称 -match '长宁公安分局无人机侦测反制设备租赁') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机侦测反制设备租赁服务' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '中国政府采购网成交公告主要标的信息；具体设备数量未披露' '中')
  }
  if ($row.项目名称 -match '成都世运会无人机无线电反制设备管控服务') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机无线电反制设备管控服务' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '四川公共资源交易/四川政府采购中标公告主要标的信息；具体设备数量未披露' '中')
  }
  if ($row.项目名称 -match '延安市公安局采购无人机反制枪及租赁无人机反制阵地') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机反制枪' '便携/手持反制设备' '公开信息未披露' '公开信息未披露' '公开信息未披露' '公开信息未披露' '项目名称披露设备名称；数量未披露' '中')
    Add-EquipmentItem $items (New-EquipmentItem '无人机反制阵地租赁' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '项目名称披露阵地租赁；按项目服务包口径' '中')
  }
  if ($row.项目名称 -match '浙江工商大学文体中心亚运手球馆') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机反制预警设备租赁服务' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '项目名称披露租赁服务；具体设备数量未披露' '中')
  }
  if ($row.项目名称 -match '青浦分局无人机反制阵地系统租赁服务') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机反制阵地系统租赁服务' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '项目名称披露阵地系统租赁服务；具体设备数量未披露' '中')
  }
  if ($row.项目名称 -match '2026年无人机反制设备租赁服务') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机反制设备租赁服务' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '项目名称披露租赁服务；具体设备数量未披露' '中')
  }
  if ($row.项目名称 -match '横琴.*重大活动安保无人机防控服务') {
    Add-EquipmentItem $items (New-EquipmentItem '重大活动安保无人机防控服务' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '政府采购结果公告披露服务项目；具体设备数量未披露' '中')
  }
  if ($row.项目名称 -match '南方电网.*固定式无人机主动防御系统.*便携式无人机反制装置') {
    Add-EquipmentItem $items (New-EquipmentItem '固定式无人机主动防御系统' '固定式反制/防御设备' '公开信息未披露' '框架采购' '公开信息未披露' '公开信息未披露' '南方电网供应链平台标的名称披露' '中')
    Add-EquipmentItem $items (New-EquipmentItem '便携式无人机反制装置' '便携/手持反制设备' '公开信息未披露' '框架采购' '公开信息未披露' '公开信息未披露' '南方电网供应链平台标的名称披露' '中')
  }
  if ($row.项目名称 -match '大亚湾.*天海地一体化综合防控系统') {
    Add-EquipmentItem $items (New-EquipmentItem '低空防御雷达显控软件' '系统平台/管控软件' '公开信息未披露' '公开信息未披露' '公开信息未披露' '公开信息未披露' '证据摘要披露标的内容' '中')
    Add-EquipmentItem $items (New-EquipmentItem '无人机防御察打一体机' '察打一体侦测反制设备' '公开信息未披露' '公开信息未披露' '公开信息未披露' '公开信息未披露' '证据摘要披露标的内容' '中')
  }
  if ($row.项目名称 -match '无人机领域综合科研专项') {
    Add-EquipmentItem $items (New-EquipmentItem '低空防御管控平台' '系统平台/管控软件' '公开信息未披露' '公开信息未披露' '公开信息未披露' '公开信息未披露' '证据摘要披露设备内容' '中')
    Add-EquipmentItem $items (New-EquipmentItem '无人机管制干扰枪' '便携/手持反制设备' '公开信息未披露' '公开信息未披露' '公开信息未披露' '公开信息未披露' '证据摘要披露设备内容' '中')
  }
  if ($row.项目名称 -match '西安市公安局4G无人机侦测反制设备采购项目') {
    Add-EquipmentItem $items (New-EquipmentItem '无线电反制设备' '侦测反制装备/设备' '1' '项' '瑞达恩' 'RDN-428' '陕西省政府采购网中标（成交）结果公告主要标的信息' '高')
    return $items.ToArray()
  }
  if ($row.项目名称 -match '反无人机系统设备采购项目$') {
    Add-EquipmentItem $items (New-EquipmentItem '反无人机系统设备' '侦测反制装备/设备' '1' '套' '上海特金' 'RF-200M' '黄山市公共资源交易中标结果公告主要标的信息' '高')
    return $items.ToArray()
  }
  if ($row.项目名称 -match '银川市公安局WRJGZ装备项目') {
    Add-EquipmentItem $items (New-EquipmentItem 'WRJGZ装备' '侦测反制装备/设备' '1' '项' '公开信息未披露' '详见附件' '宁夏回族自治区政府采购网中标公告披露中标供应商为杰能科世智能安全科技（杭州）有限公司；主要标的信息未细化披露' '中')
    return $items.ToArray()
  }
  if ($row.项目名称 -match '林西县公安局特种指挥车辆及无人机反制设备') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机反制设备（一）' '侦测反制装备/设备' '1' '项' 'D2C JM1' 'TDD-DCMX1-AB-HEN2A，JM1' '内蒙古政府采购中标（成交）明细披露制造商为上海特金信息科技有限公司' '高')
    Add-EquipmentItem $items (New-EquipmentItem '无人机反制设备（二）' '侦测反制装备/设备' '1' '项' 'H1D' 'TDD-DCPX1-AB-HHN1A' '内蒙古政府采购中标（成交）明细披露制造商为上海特金信息科技有限公司' '高')
    return $items.ToArray()
  }
  if ($row.项目名称 -match '萧山区行政中心低空防御建设项目') {
    Add-EquipmentItem $items (New-EquipmentItem '低空防御建设项目' '系统平台/管控软件' '1' '项' '公开信息未披露' '公开信息未披露' '招标公告线索仅明确项目名称、采购人和预算，暂未确认中标结果' '低')
    return $items.ToArray()
  }
  if ($row.项目名称 -match '安徽省公安厅机场公安局无人机侦测反制设备采购项目|机场公安局无人机侦测反制设备采购项目') {
    Add-EquipmentItem $items (New-EquipmentItem '车载无人机侦测解码设备' '侦测探测设备' '2' '套' '观曜科技' 'OMAT-AL100' '安徽省政府采购网中标结果公告主要标的信息披露车载无人机侦测解码设备、品牌和型号' '高')
    Add-EquipmentItem $items (New-EquipmentItem '车载无人机定向反制设备' '侦测反制装备/设备' '1' '套' '观曜科技' '公开信息未披露' '同一结果公告披露车载定向反制设备；具体型号未在公开摘要中完整展开' '中')
    return $items.ToArray()
  }
  if ($row.项目名称 -match '杭州市低空综合管理服务平台2\.0') {
    Add-EquipmentItem $items (New-EquipmentItem '低空综合管理服务平台2.0公共安防管理端开发服务' '系统平台/管控软件' '1' '项服务' '公开信息未披露' '公开信息未披露' '众合科技公开中标信息披露合同金额458万元，项目为平台公共安防管理端开发服务' '高')
    return $items.ToArray()
  }
  if ($row.项目名称 -match '甘肃省公安厅机场公安局无人机无源侦测反制系统升级及硬件设备采购项目') {
    Add-EquipmentItem $items (New-EquipmentItem '无人机无源侦测反制系统升级' '系统平台/管控软件' '1' '项' '公开信息未披露' '公开信息未披露' '结果公告标题直接披露系统升级；中标单位为杰能科世智能安全科技（杭州）有限公司' '高')
    Add-EquipmentItem $items (New-EquipmentItem '无人机无源侦测反制硬件设备' '侦测反制装备/设备' '1' '项' '公开信息未披露' '公开信息未披露' '结果公告标题直接披露硬件设备采购；具体设备名在公开摘要中未完整展开' '高')
    return $items.ToArray()
  }
  if ($row.项目名称 -match '兰州新区低空飞行设施设备建设项目') {
    Add-EquipmentItem $items (New-EquipmentItem '低空安全监管平台' '系统平台/管控软件' '1' '项' '公开信息未披露' '公开信息未披露' '中标候选人公示标题直接披露低空安全监管平台项目；中标单位为杰能科世智能安全科技（杭州）有限公司' '高')
    return $items.ToArray()
  }

  $patterns = @(
    '无人机频谱侦测设备',
    '固定式无人机反制设备',
    '察打一体无人机反制设备',
    '便携式察打一体反制设备',
    '手持式无人机反制设备',
    '无人机智能管控平台',
    '手持式无人机探测定位设备',
    '手持无人机侦测设备',
    '固定式无人机侦测反制设备',
    '无人机侦测反制设备',
    '无人机侦测打击系统',
    '无人机低空反制设备',
    '无人机反制设备',
    '无人机反制系统',
    '无人机反制装备',
    '无人机反制枪',
    '反制枪',
    '无人机管控前端系统',
    '低空安全管控装备',
    '低空防御系统',
    '低空防御服务',
    '无人机探测与反制实训系统',
    '监狱无人机探测与反制实训系统',
    '无人机教培、警务应用及反制项目',
    '固定式无人机主动防御系统',
    '便携式无人机反制装置',
    '无人机反制装置零部件',
    '无人机反制器材',
    '无人机反制车',
    '车载式无人机反制系统',
    '车载无人机反制系统',
    '无人机防御反制设备',
    '便携式无人机防御反制设备',
    '反无人机主动防御系统',
    '无人机反制阵地系统租赁服务',
    '无人机反制设备租赁服务',
    '无人机反制租赁服务',
    '无人机反制服务',
    '低空管控服务',
    '低空安全防控无人机反制服务租赁'
  )
  foreach ($pattern in $patterns) {
    if ($pattern -eq '反制枪' -and $text -match '无人机反制枪') { continue }
    if ($text -match [regex]::Escape($pattern)) {
      Add-EquipmentItem $items (New-EquipmentItem $pattern (Infer-EquipmentType $pattern $text) '公开信息未披露' '公开信息未披露' '公开信息未披露' '公开信息未披露' '项目名称/证据摘要关键词抽取；公开信息未见数量' '低')
    }
  }

  if ($items.Count -eq 0) {
    if ($row.项目类型 -match '服务|租赁') {
      Add-EquipmentItem $items (New-EquipmentItem '无人机侦测反制/低空管控服务' '服务/租赁' '1' '项服务' '公开信息未披露' '公开信息未披露' '按项目类型推断服务包；具体设备未披露' '低')
    } elseif ($row.项目类型 -match '系统|平台') {
      Add-EquipmentItem $items (New-EquipmentItem '无人机侦测反制系统/平台' '系统平台/管控软件' '公开信息未披露' '公开信息未披露' '公开信息未披露' '公开信息未披露' '按项目类型推断；具体设备未披露' '低')
    } else {
      Add-EquipmentItem $items (New-EquipmentItem '无人机侦测反制设备/装备' '侦测反制装备/设备' '公开信息未披露' '公开信息未披露' '公开信息未披露' '公开信息未披露' '按项目名称/项目类型推断；具体设备未披露' '低')
    }
  }

  return $items.ToArray()
}

$rows = Import-Csv -LiteralPath $main
$enriched = @()
$long = @()
$index = 0
foreach ($row in $rows) {
  $index++
  $projectId = 'LA-{0}-{1:D4}' -f $row.年份, $index
  $items = @(Get-EquipmentItems $row)
  $names = ($items | ForEach-Object { $_.设备名称 } | Select-Object -Unique) -join '；'
  $types = ($items | ForEach-Object { $_.设备类型 } | Select-Object -Unique) -join '；'
  $quantities = ($items | ForEach-Object {
      if ($_.数量 -eq '公开信息未披露') { "$($_.设备名称)：公开信息未披露" } else { "$($_.设备名称)：$($_.数量)$($_.单位)" }
    }) -join '；'
  $models = ($items | Where-Object { $_.规格型号 -ne '公开信息未披露' } | ForEach-Object { "$($_.设备名称)：$($_.规格型号)" }) -join '；'
  if ([string]::IsNullOrWhiteSpace($models)) { $models = '公开信息未披露' }
  $brands = ($items | Where-Object { $_.品牌 -ne '公开信息未披露' } | ForEach-Object { "$($_.设备名称)：$($_.品牌)" }) -join '；'
  if ([string]::IsNullOrWhiteSpace($brands)) { $brands = '公开信息未披露' }
  $confidenceValues = @($items | ForEach-Object { $_.明细置信度 })
  $detailLevel = if ($confidenceValues -contains '高') {
    if ($confidenceValues -contains '低') { '部分明细' } else { '明细较完整' }
  } elseif ($confidenceValues -contains '中') {
    '部分明细'
  } else {
    '仅项目级推断'
  }
  $source = ($items | ForEach-Object { $_.明细依据 } | Select-Object -Unique) -join '；'

  $project = [ordered]@{ 项目ID = $projectId }
  foreach ($prop in $row.PSObject.Properties) {
    if ($oldDeviceCols -notcontains $prop.Name) {
      $project[$prop.Name] = $prop.Value
    }
  }
  $project['设备名称清单'] = $names
  $project['设备类型清单'] = $types
  $project['设备数量清单'] = $quantities
  $project['设备规格型号清单'] = $models
  $project['设备品牌清单'] = $brands
  $project['设备明细完整度'] = $detailLevel
  $project['设备明细来源'] = $source
  $project['设备明细备注'] = '数量仅在公告/证据明确披露时填写；未披露的不按金额或经验倒推'
  $enriched += [pscustomobject]$project

  $sequence = 0
  foreach ($item in $items) {
    $sequence++
    $long += [pscustomobject]@{
      项目ID     = $projectId
      省份       = $row.省份
      省内城市区域   = $row.省内城市区域
      项目名称     = $row.项目名称
      发包采购单位   = $row.发包采购单位
      承建中标单位   = $row.承建中标单位
      中标公告时间   = $row.中标公告时间
      年份       = $row.年份
      设备序号     = $sequence
      设备名称     = $item.设备名称
      设备类型     = $item.设备类型
      数量       = $item.数量
      单位       = $item.单位
      品牌       = $item.品牌
      规格型号     = $item.规格型号
      明细依据     = $item.明细依据
      明细置信度    = $item.明细置信度
      来源链接     = $row.来源链接
    }
  }
}

$enriched | Export-Csv -LiteralPath $main -NoTypeInformation -Encoding UTF8
$enriched | Export-Csv -LiteralPath $rootCopy -NoTypeInformation -Encoding UTF8
$long | Export-Csv -LiteralPath $longPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
  项目数       = $enriched.Count
  设备明细行数    = $long.Count
  明细较完整项目数  = @($enriched | Where-Object { $_.设备明细完整度 -eq '明细较完整' }).Count
  部分明细项目数   = @($enriched | Where-Object { $_.设备明细完整度 -eq '部分明细' }).Count
  仅项目级推断项目数 = @($enriched | Where-Object { $_.设备明细完整度 -eq '仅项目级推断' }).Count
}
