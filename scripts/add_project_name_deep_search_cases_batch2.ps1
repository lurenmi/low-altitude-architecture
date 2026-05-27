$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $base '按省份低空侦测中标项目CSV_2023-2026'
$mainPath = Join-Path $outDir '全国_低空侦测反制中标项目_2023-2026_全量汇总.csv'
$rootCopy = Join-Path $base '低空侦测招投标案例库_按省份全量_2023-2026.csv'
$cluePath = Join-Path $outDir '补充检索相关线索_未并入中标.csv'

$deviceCols = @('设备名称清单','设备类型清单','设备数量清单','设备规格型号清单','设备品牌清单','设备明细完整度','设备明细来源','设备明细备注')

function New-MainRow($s) {
  $row = [ordered]@{
    项目ID = ''
    省份 = $s.Province
    省内城市区域 = $s.City
    项目名称 = $s.Project
    项目类型 = $s.Type
    项目阶段 = '中标/成交结果'
    是否直接侦测反制相关 = '是'
    发包采购单位 = $s.Buyer
    项目金额 = $s.AmountText
    金额万元 = $s.AmountWan
    承建中标单位 = $s.Contractor
    中标公告时间 = $s.Date
    年份 = $s.Year
    来源等级 = $s.SourceLevel
    字段完整度 = $s.Completeness
    来源链接 = $s.Source
    证据摘要 = $s.Evidence
    核验备注 = $s.Note
  }
  foreach ($col in $deviceCols) { $row[$col] = '' }
  [pscustomobject]$row
}

function New-ClueRow($s) {
  [pscustomobject]@{
    省份 = $s.Province
    城市 = $s.City
    项目名称 = $s.Project
    线索阶段 = $s.Stage
    需求类别 = $s.Demand
    发包采购单位 = $s.Buyer
    预算或金额 = $s.Amount
    线索时间 = $s.Date
    来源链接 = $s.Source
    备注 = $s.Note
  }
}

$caseSpecs = @(
  [pscustomobject]@{ Province='湖北'; City='十堰'; Project='十堰市低空综合管理服务平台第一期建设项目'; Type='侦测反制系统/平台'; Buyer='十堰产城融合投资发展集团有限公司'; AmountText='公开信息未披露'; AmountWan=''; Contractor='鸢飞科技（上海）有限公司'; Date='2025-01-20'; Year='2025'; SourceLevel='A-官方公告/公共资源'; Completeness='较完整'; Source='https://www.hbbidcloud.cn/shiyan/jyxx/004005/004005001/20250120/d0905e3d-3bf5-4f55-9d78-409fa4bba3ad.html'; Evidence='湖北省电子招投标交易平台/十堰公共资源交易信息披露：十堰市低空综合管理服务平台第一期建设项目，中标人为鸢飞科技（上海）有限公司。'; Note='项目名称深度检索补入；城市级低空综合管理服务平台样本' }
  [pscustomobject]@{ Province='西藏'; City='昌都'; Project='昌都市公安局采购低空安全反无人机系统项目'; Type='侦测反制系统/平台'; Buyer='昌都市公安局'; AmountText='212.9000 万元'; AmountWan='212.9'; Contractor='中国电信集团有限公司昌都分公司'; Date='2025-01-29'; Year='2025'; SourceLevel='A-官方公告/公共资源'; Completeness='完整'; Source='https://www.ccgp-xizang.gov.cn/freecms/site/xizang/ggxx/info/2025/8a7eb882948a40300194bdc599a22e17.html'; Evidence='西藏自治区政府采购网结果公告披露：昌都市公安局采购低空安全反无人机系统项目，中标单位中国电信集团有限公司昌都分公司，中标金额212.9万元。'; Note='项目名称深度检索补入；低空安全反无人机系统直相关样本' }
  [pscustomobject]@{ Province='四川'; City='遂宁'; Project='中国铁塔股份有限公司遂宁市分公司2025年低空安全态势感知监管平台服务与无人机监测反制设备采购项目（标段1：平台服务）'; Type='侦测反制系统/平台'; Buyer='中国铁塔股份有限公司遂宁市分公司'; AmountText='公开信息未披露'; AmountWan=''; Contractor='四川泰睿通信工程有限公司'; Date='2025-12-05'; Year='2025'; SourceLevel='A-官方公告/公共资源'; Completeness='较完整'; Source='https://ebid.chinatowercom.cn/zgtt/gggs/003004/20251205/5a590d57-e9d9-47f9-868e-6cb6db3f4e96.html'; Evidence='中国铁塔电子采购平台成交结果公示披露：遂宁市分公司2025年低空安全态势感知监管平台服务与无人机监测反制设备采购项目标段1，成交供应商四川泰睿通信工程有限公司。'; Note='项目名称深度检索补入；低空安全态势感知监管平台服务样本' }
  [pscustomobject]@{ Province='四川'; City='遂宁'; Project='中国铁塔股份有限公司遂宁市分公司2025年低空安全态势感知监管平台服务与无人机监测反制设备采购项目（标段2：无人机监测反制设备）'; Type='侦测反制装备'; Buyer='中国铁塔股份有限公司遂宁市分公司'; AmountText='公开信息未披露'; AmountWan=''; Contractor='公开信息未披露'; Date='2025-12-05'; Year='2025'; SourceLevel='B-公开转载/行业平台'; Completeness='较完整'; Source='https://www.zchxzb.com/info/202512/7054297.html'; Evidence='公开成交结果公示标题披露：遂宁市分公司2025年低空安全态势感知监管平台服务与无人机监测反制设备采购项目标段2为无人机监测反制设备采购；供应商和金额待回溯官方原文。'; Note='项目名称深度检索补入；设备标段供应商字段待进一步核验' }
  [pscustomobject]@{ Province='内蒙古'; City='鄂尔多斯伊金霍洛旗'; Project='伊金霍洛旗公安局低空数字警务设备采购项目'; Type='侦测反制系统/平台'; Buyer='伊金霍洛旗公安局'; AmountText='394.8986 万元'; AmountWan='394.8986'; Contractor='公开信息未披露'; Date='2026-04-14'; Year='2026'; SourceLevel='A-官方公告/公共资源'; Completeness='较完整'; Source='https://www.ccgp-neimenggu.gov.cn/gpx-bid-file/ZF_JGBM_000001/150627/2026/2/19/402881e29f1bab8b019f2a3a764e1b5d/gpx-bidconfirm/402881d2a2e2034d01a329e464d50142.pdf?accessCode=f9e54e286d0c95a3ed97db6c0119d409'; Evidence='内蒙古政府采购中标（成交）明细披露：伊金霍洛旗公安局低空数字警务设备采购项目，中标金额394.8986万元；项目包含公安低空数字警务设备及相关平台/装备。'; Note='项目名称深度检索补入；官方PDF中供应商字段需进一步回溯正文确认' }
  [pscustomobject]@{ Province='内蒙古'; City='鄂尔多斯鄂托克旗'; Project='鄂托克旗公安局低空数字警务装备采购项目'; Type='侦测反制系统/平台'; Buyer='鄂托克旗公安局'; AmountText='273.9268 万元'; AmountWan='273.9268'; Contractor='内蒙古迅力智能科技有限公司'; Date='2026-04-14'; Year='2026'; SourceLevel='A-官方公告/公共资源'; Completeness='完整'; Source='https://www.ccgp-neimenggu.gov.cn/gpx-bid-file/ZF_JGBM_000001/150624/2026/2/9/402881e29e8f7417019eef0b02d114dd/gpx-bidconfirm/402881d2a2e2034d01a2ee6ee102015d.pdf?accessCode=8485d3a9c882f5d7750c2e09061f22e3'; Evidence='内蒙古政府采购中标（成交）明细披露：鄂托克旗公安局低空数字警务装备采购项目，内蒙古迅力智能科技有限公司中标，中标金额273.9268万元。'; Note='项目名称深度检索补入；公安低空数字警务装备样本' }
  [pscustomobject]@{ Province='内蒙古'; City='鄂尔多斯准格尔旗'; Project='准格尔旗公安低空数字警务项目（2026年采购）'; Type='侦测反制系统/平台'; Buyer='准格尔旗公安局'; AmountText='485.8614 万元'; AmountWan='485.8614'; Contractor='公开信息未披露'; Date='2026-04-09'; Year='2026'; SourceLevel='B-公开转载/行业平台'; Completeness='较完整'; Source='https://www.qianlima.com/bid-654635432.html'; Evidence='公开结果信息披露：准格尔旗公安低空数字警务项目2026年采购，中标金额485.8614万元，标的含低空数字智慧平台、By.tech低空数字智慧平台等内容；供应商被转载平台脱敏。'; Note='项目名称深度检索补入；同名项目与2025年采购分年保留，供应商待官方原文核验' }
  [pscustomobject]@{ Province='江西'; City='南昌'; Project='南昌市公安局低空安全及反制设备采购项目'; Type='侦测反制装备'; Buyer='南昌市公安局'; AmountText='124.6600 万元'; AmountWan='124.66'; Contractor='江西浩德实业有限公司'; Date='2024-09-12'; Year='2024'; SourceLevel='A-官方公告/公共资源'; Completeness='完整'; Source='https://ccgp-jiangxi.gov.cn/web/jyxx/002006/002006006/20240912/0ef6daf0-bd09-42e4-b230-ea89b23c316e.html'; Evidence='江西省政府采购网结果公告披露：南昌市公安局低空安全及反制设备采购项目，江西浩德实业有限公司中标，中标金额124.66万元。'; Note='项目名称深度检索补入；低空安全及反制设备直相关样本' }
  [pscustomobject]@{ Province='广东'; City='茂名'; Project='广东省茂名监狱低空域智能警戒巡防系统采购项目'; Type='侦测反制系统/平台'; Buyer='广东省茂名监狱'; AmountText='425.5200 万元'; AmountWan='425.52'; Contractor='中国电信股份有限公司广东分公司'; Date='2025-05-22'; Year='2025'; SourceLevel='A-官方公告/公共资源'; Completeness='完整'; Source='https://gdgpo.czt.gd.gov.cn/freecms/site/gd/ggxx/info/2025/8a7e6fc396d4b9610196e214d7bf710f.html'; Evidence='广东政府采购智慧云平台结果公告披露：广东省茂名监狱低空域智能警戒巡防系统采购项目，中国电信股份有限公司广东分公司中标，中标金额425.52万元。'; Note='项目名称深度检索补入；司法监狱低空域智能警戒巡防系统样本' }
  [pscustomobject]@{ Province='广东'; City='广州'; Project='广东警官学院无人机数智低空警务工程实训教学平台建设项目(二次)'; Type='侦测反制系统/平台'; Buyer='广东警官学院'; AmountText='135.0069 万元'; AmountWan='135.0069'; Contractor='广州成至智能机器科技有限公司'; Date='2025-03-10'; Year='2025'; SourceLevel='A-官方公告/公共资源'; Completeness='完整'; Source='https://gdgpo.czt.gd.gov.cn/freecms/site/gd/ggxx/info/2025/8a7edac09573cf4201957ae65f634c5f.html'; Evidence='广东政府采购智慧云平台结果公告披露：广东警官学院无人机数智低空警务工程实训教学平台建设项目（二次），广州成至智能机器科技有限公司中标，中标金额135.0069万元。'; Note='项目名称深度检索补入；低空警务实训平台样本' }
  [pscustomobject]@{ Province='四川'; City='成都高新'; Project='高新公安分局2025年度低空警务实战场景应用建设项目'; Type='侦测反制系统/平台'; Buyer='成都市公安局高新技术产业开发区分局'; AmountText='324.3180 万元'; AmountWan='324.318'; Contractor='四川中移通信技术工程有限公司'; Date='2025-08-18'; Year='2025'; SourceLevel='A-官方公告/公共资源'; Completeness='完整'; Source='https://jy.scltzb.com/html/eltzb/jiaoyixinxi/jieguogonggao/1957344575933603842.html'; Evidence='联投E采在线交易平台结果公告披露：高新公安分局2025年度低空警务实战场景应用建设项目，四川中移通信技术工程有限公司中标，中标金额324.318万元。'; Note='项目名称深度检索补入；低空警务实战场景应用样本' }
  [pscustomobject]@{ Province='云南'; City='昆明'; Project='昆明市公安局低空安全实战应用平台建设项目'; Type='侦测反制系统/平台'; Buyer='昆明市公安局'; AmountText='114.8000 万元'; AmountWan='114.8'; Contractor='公安部第三研究所'; Date='2025-12-29'; Year='2025'; SourceLevel='B-公开转载/行业平台'; Completeness='完整'; Source='https://www.bbda.com/bidDetail/db58c36bfc33d74cab3babbc5873428a962b7739ded9e70b6b12d688c0f6ad35.html'; Evidence='公开结果信息披露：昆明市公安局低空安全实战应用平台建设项目，公安部第三研究所成交，成交金额114.8万元；服务范围包含无人机安全监管、预警、处置等功能。'; Note='项目名称深度检索补入；低空安全实战应用平台样本' }
  [pscustomobject]@{ Province='重庆'; City='江北'; Project='重庆市公安局江北区分局所需低空安全防御服务项目'; Type='侦测反制服务/租赁'; Buyer='重庆市公安局江北区分局'; AmountText='67.8000 万元'; AmountWan='67.8'; Contractor='重庆晟楠科技有限公司'; Date='2026-01-07'; Year='2026'; SourceLevel='B-公开转载/行业平台'; Completeness='完整'; Source='https://www.bibenet.com/zfcg33349358.html'; Evidence='公开结果信息披露：重庆市公安局江北区分局所需低空安全防御服务项目，重庆晟楠科技有限公司中标，金额67.8万元；服务含监测发现、识别判断、侵入预警、干扰拦截、落地查人。'; Note='项目名称深度检索补入；低空安全防御服务和反制装备服务样本' }
  [pscustomobject]@{ Province='浙江'; City='杭州临安'; Project='杭州市临安区JW无人机低空安全保障服务项目'; Type='侦测反制服务/租赁'; Buyer='杭州市公安局临安区分局'; AmountText='207.6800 万元'; AmountWan='207.68'; Contractor='杭州临安数智城市发展有限公司'; Date='2025-12-16'; Year='2025'; SourceLevel='B-公开转载/行业平台'; Completeness='完整'; Source='https://m.sohu.com/a/965769224_122434053'; Evidence='公开结果信息披露：杭州市临安区JW无人机低空安全保障服务项目，杭州临安数智城市发展有限公司成交，金额207.68万元，服务期一年。'; Note='项目名称深度检索补入；公安无人机低空安全保障服务样本' }
  [pscustomobject]@{ Province='四川'; City='泸州泸县'; Project='泸县“蜀警飞鹰”低空警务建设项目'; Type='侦测反制系统/平台'; Buyer='泸县公安局'; AmountText='69.9510 万元'; AmountWan='69.951'; Contractor='四川中移通信技术工程有限公司'; Date='2025-12-30'; Year='2025'; SourceLevel='B-公开转载/行业平台'; Completeness='完整'; Source='https://sc.zhiliaobiaoxun.com/article/87732199'; Evidence='公开结果信息披露：泸县“蜀警飞鹰”低空警务建设项目，四川中移通信技术工程有限公司成交，金额69.951万元；标的包含无线电侦测设备、无线电干扰设备、低空安全管理平台等。'; Note='项目名称深度检索补入；低空警务建设且含侦测/干扰/管理平台' }
  [pscustomobject]@{ Province='福建'; City='泉州南安'; Project='南安市低空空域智能管控系统采购项目'; Type='侦测反制系统/平台'; Buyer='公开信息未披露'; AmountText='公开信息未披露'; AmountWan=''; Contractor='中国铁路通信信号股份有限公司'; Date='2025-12-26'; Year='2025'; SourceLevel='B-公开转载/企业公告'; Completeness='较完整'; Source='https://www.crsc.cn/8961.html'; Evidence='中国通号公开信息披露：成功中标南安市低空空域智能管控系统采购项目；公开页面未披露合同金额和采购人完整名称。'; Note='项目名称深度检索补入；低空空域智能管控系统样本，金额待核验' }
)

$clueSpecs = @(
  [pscustomobject]@{ Province='陕西'; City='汉中'; Project='汉中市低空经济数字化基础设施及配套场景建设项目'; Stage='中标/边界样本待拆分'; Demand='城市级低空治理/安全基础设施'; Buyer='公开信息未披露'; Amount='约29500万元'; Date='2025-12-18'; Source='https://www.geovis.com.cn/news/661'; Note='中科星图公开信息称成功中标，项目建设内容包含低空通信、导航、监视、反制设施等；因整体金额过大且侦测反制占比未拆分，暂不并入主库金额统计' }
  [pscustomobject]@{ Province='江西'; City='南昌红谷滩'; Project='南昌市公安局红谷滩分局巡逻处突大队采购低空安全及反制设备项目（第二次）'; Stage='采购公告/开标记录待核验'; Demand='日常巡防需求'; Buyer='南昌市公安局红谷滩分局'; Amount='103万元'; Date='2025-12-16'; Source='https://www.laernoc.com/productinfo/1844273797960699905'; Note='已检索到开标/项目线索，尚未确认成交公告和中标单位' }
  [pscustomobject]@{ Province='四川'; City='泸州'; Project='泸州市公安局低空警务建设项目'; Stage='采购公告/待中标'; Demand='日常巡防需求'; Buyer='泸州市公安局'; Amount='177.392万元'; Date='2024-11-29'; Source='https://www.laernoc.com/productinfo/1844273797960699905'; Note='公开低空项目汇总显示采购公告，尚未定位到结果公告' }
  [pscustomobject]@{ Province='四川'; City='凉山'; Project='凉山彝族自治州公安局低空警务中心建设项目'; Stage='结果线索/待核验'; Demand='日常巡防需求'; Buyer='凉山彝族自治州公安局'; Amount='71.2068万元'; Date='2026-05-14'; Source='https://www.laernoc.com/productinfo/1844273797960699905'; Note='检索到结果类线索但中标单位和设备内容尚未核验，先列入线索表' }
  [pscustomobject]@{ Province='四川'; City='雅安名山'; Project='雅安市公安局名山区分局“麒麟天巡”低空警务应用服务采购项目'; Stage='采购公告/待中标'; Demand='日常巡防需求'; Buyer='雅安市公安局名山区分局'; Amount='110万元'; Date='2026-01-05'; Source='https://www.laernoc.com/productinfo/1844273797960699905'; Note='低空警务应用服务项目，尚未确认结果公告' }
  [pscustomobject]@{ Province='山西'; City='临汾'; Project='临汾经济开发区低空安全全域巡检应用服务项目'; Stage='结果线索/待核验'; Demand='日常巡防需求'; Buyer='临汾经济开发区管理委员会经济科技发展部'; Amount='公开信息未披露'; Date='2026-05-08'; Source='https://www.bbda.com/bidList/k1295'; Note='检索到结果公告线索，但中标单位和成交金额未核验，先不并入主库' }
  [pscustomobject]@{ Province='江苏'; City='南京浦口'; Project='南京市公安局浦口分局低空警务装备项目'; Stage='结果线索/待核验'; Demand='日常巡防需求'; Buyer='南京市公安局浦口分局'; Amount='74.36万元'; Date='2025-07-31'; Source='https://www.laernoc.com/productinfo/1844273797960699905'; Note='公开低空项目汇总显示结果公告和金额，尚未确认中标单位' }
  [pscustomobject]@{ Province='福建'; City='福州新区'; Project='福州新区低空空域管理系统项目'; Stage='企业公开信息/待核验'; Demand='城市级低空治理/平台'; Buyer='公开信息未披露'; Amount='公开信息未披露'; Date='2026-05-22'; Source='https://www.geovis.com.cn/'; Note='中科星图相关公开信息出现项目名，暂未定位到招投标结果公告' }
  [pscustomobject]@{ Province='青海'; City='西宁'; Project='西宁市低空智航飞行应用平台项目'; Stage='企业公开信息/待核验'; Demand='城市级低空治理/平台'; Buyer='公开信息未披露'; Amount='公开信息未披露'; Date='2026-05-22'; Source='https://www.geovis.com.cn/'; Note='中科星图相关公开信息出现项目名，暂未定位到招投标结果公告' }
)

$mainRows = @(Import-Csv -LiteralPath $mainPath)
$addedMain = 0
foreach ($spec in $caseSpecs) {
  if (@($mainRows | Where-Object { $_.项目名称 -eq $spec.Project }).Count -eq 0) {
    $mainRows += (New-MainRow $spec)
    $addedMain++
  }
}

$mainRows | Export-Csv -LiteralPath $mainPath -NoTypeInformation -Encoding UTF8
$mainRows | Export-Csv -LiteralPath $rootCopy -NoTypeInformation -Encoding UTF8

$clues = @()
if (Test-Path -LiteralPath $cluePath) {
  $clues = @(Import-Csv -LiteralPath $cluePath)
}
foreach ($row in $clues) {
  if ($row.项目名称 -eq '汉中市低空经济数字化基础设施及配套场景建设项目') {
    $row.备注 = ($row.备注 -replace '\s+New-Clue$', '')
  }
}

$addedClues = 0
foreach ($spec in $clueSpecs) {
  if (@($clues | Where-Object { $_.项目名称 -eq $spec.Project }).Count -eq 0) {
    $clues += (New-ClueRow $spec)
    $addedClues++
  }
}

$clues | Export-Csv -LiteralPath $cluePath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
  主库新增项目数 = $addedMain
  线索表新增项目数 = $addedClues
  主库总行数 = $mainRows.Count
  线索表总行数 = $clues.Count
}
