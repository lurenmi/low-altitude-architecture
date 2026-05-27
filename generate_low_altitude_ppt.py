from __future__ import annotations

import html
import os
import zipfile
from dataclasses import dataclass, field
from typing import Iterable, List, Optional, Tuple


OUT = "低空数字孪生平台竞品分析与系统功能需求分析汇报.pptx"

EMU_PER_INCH = 914400
SLIDE_W = 13.333333
SLIDE_H = 7.5
W = int(SLIDE_W * EMU_PER_INCH)
H = int(SLIDE_H * EMU_PER_INCH)


def emu(inch: float) -> int:
    return int(inch * EMU_PER_INCH)


def esc(text: str) -> str:
    return html.escape(text, quote=True)


def color(hex_color: str) -> str:
    return hex_color.replace("#", "").upper()


@dataclass
class TextRun:
    text: str
    size: int = 18
    bold: bool = False
    fill: str = "1F2937"


@dataclass
class Shape:
    kind: str
    x: float
    y: float
    w: float
    h: float
    text: str = ""
    fill: str = "FFFFFF"
    line: str = "D5DAE3"
    text_color: str = "1F2937"
    font_size: int = 18
    bold: bool = False
    radius: bool = False
    align: str = "l"
    valign: str = "mid"
    margin: float = 0.08
    paragraphs: Optional[List[str]] = None
    title: bool = False


@dataclass
class Slide:
    title: str
    subtitle: str = ""
    shapes: List[Shape] = field(default_factory=list)
    notes: str = ""


class Deck:
    def __init__(self) -> None:
        self.slides: List[Slide] = []

    def add(self, slide: Slide) -> None:
        self.slides.append(slide)


def tx_body(
    text: str = "",
    *,
    paragraphs: Optional[List[str]] = None,
    font_size: int = 18,
    text_color: str = "1F2937",
    bold: bool = False,
    align: str = "l",
    margin: float = 0.08,
) -> str:
    mar = emu(margin)
    sz = int(round(font_size * 100))
    paras = paragraphs if paragraphs is not None else [text]
    p_xml = []
    for idx, p in enumerate(paras):
        bullet = False
        clean = p
        if p.startswith("- "):
            bullet = True
            clean = p[2:]
        elif p.startswith("• "):
            bullet = True
            clean = p[2:]
        rpr = (
            f'<a:rPr lang="zh-CN" sz="{sz}" '
            f'{"b=\"1\" " if bold and idx == 0 else ""}>'
            f'<a:solidFill><a:srgbClr val="{color(text_color)}"/></a:solidFill>'
            f'<a:latin typeface="Microsoft YaHei"/><a:ea typeface="Microsoft YaHei"/>'
            f'</a:rPr>'
        )
        bullet_xml = '<a:buChar char="•"/>' if bullet else '<a:buNone/>'
        p_xml.append(
            f'<a:p><a:pPr algn="{align}" marL="{emu(0.16) if bullet else 0}" '
            f'indent="{emu(-0.12) if bullet else 0}">{bullet_xml}</a:pPr>'
            f'<a:r>{rpr}<a:t>{esc(clean)}</a:t></a:r><a:endParaRPr lang="zh-CN" sz="{sz}"/></a:p>'
        )
    return (
        f'<p:txBody><a:bodyPr wrap="square" lIns="{mar}" tIns="{mar}" '
        f'rIns="{mar}" bIns="{mar}" anchor="ctr"/><a:lstStyle/>{"".join(p_xml)}</p:txBody>'
    )


def shape_xml(shape_id: int, s: Shape) -> str:
    x, y, w, h = emu(s.x), emu(s.y), emu(s.w), emu(s.h)
    geom = "roundRect" if s.radius else "rect"
    fill_xml = (
        f'<a:solidFill><a:srgbClr val="{color(s.fill)}"/></a:solidFill>'
        if s.fill != "none"
        else "<a:noFill/>"
    )
    line_xml = (
        f'<a:ln w="9525"><a:solidFill><a:srgbClr val="{color(s.line)}"/></a:solidFill></a:ln>'
        if s.line != "none"
        else "<a:ln><a:noFill/></a:ln>"
    )
    body = tx_body(
        s.text,
        paragraphs=s.paragraphs,
        font_size=s.font_size,
        text_color=s.text_color,
        bold=s.bold,
        align=s.align,
        margin=s.margin,
    )
    return f"""
<p:sp>
  <p:nvSpPr><p:cNvPr id="{shape_id}" name="Shape {shape_id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
  <p:spPr>
    <a:xfrm><a:off x="{x}" y="{y}"/><a:ext cx="{w}" cy="{h}"/></a:xfrm>
    <a:prstGeom prst="{geom}"><a:avLst/></a:prstGeom>
    {fill_xml}{line_xml}
  </p:spPr>
  {body}
</p:sp>
"""


def line_xml(shape_id: int, x1: float, y1: float, x2: float, y2: float, stroke: str = "CBD5E1", width: int = 2) -> str:
    x, y = min(x1, x2), min(y1, y2)
    w, h = abs(x2 - x1), abs(y2 - y1)
    return f"""
<p:cxnSp>
  <p:nvCxnSpPr><p:cNvPr id="{shape_id}" name="Line {shape_id}"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>
  <p:spPr>
    <a:xfrm><a:off x="{emu(x)}" y="{emu(y)}"/><a:ext cx="{emu(w)}" cy="{emu(h)}"/></a:xfrm>
    <a:prstGeom prst="line"><a:avLst/></a:prstGeom>
    <a:ln w="{width * 12700}"><a:solidFill><a:srgbClr val="{color(stroke)}"/></a:solidFill></a:ln>
  </p:spPr>
</p:cxnSp>
"""


def base_slide(slide: Slide, idx: int) -> str:
    shapes = []
    # background
    shapes.append(Shape("rect", 0, 0, SLIDE_W, SLIDE_H, fill="F7F9FC", line="none"))
    # top accent
    shapes.append(Shape("rect", 0, 0, SLIDE_W, 0.12, fill="2563EB", line="none"))
    # title
    if slide.title:
        shapes.append(Shape("text", 0.55, 0.32, 8.8, 0.5, slide.title, fill="none", line="none", font_size=22, bold=True, text_color="0F172A", margin=0))
    if slide.subtitle:
        shapes.append(Shape("text", 0.57, 0.82, 8.8, 0.28, slide.subtitle, fill="none", line="none", font_size=9, text_color="64748B", margin=0))
    # page number
    shapes.append(Shape("text", 12.35, 7.12, 0.5, 0.22, f"{idx:02d}", fill="none", line="none", font_size=8, text_color="94A3B8", align="r", margin=0))
    shapes.extend(slide.shapes)

    sp_tree = [
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>',
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>',
    ]
    sid = 2
    for s in shapes:
        sp_tree.append(shape_xml(sid, s))
        sid += 1
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree>{''.join(sp_tree)}</p:spTree></p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>"""


def content_types(n: int) -> str:
    overrides = [
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>',
        '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>',
        '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>',
        '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>',
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>',
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>',
    ]
    for i in range(1, n + 1):
        overrides.append(f'<Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>')
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  {''.join(overrides)}
</Types>"""


def rels_root() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>"""


def presentation_xml(n: int) -> str:
    ids = ''.join(f'<p:sldId id="{255+i}" r:id="rId{i}"/>' for i in range(1, n + 1))
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId{n+1}"/></p:sldMasterIdLst>
  <p:sldIdLst>{ids}</p:sldIdLst>
  <p:sldSz cx="{W}" cy="{H}" type="wide"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>"""


def presentation_rels(n: int) -> str:
    rels = []
    for i in range(1, n + 1):
        rels.append(f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide{i}.xml"/>')
    rels.append(f'<Relationship Id="rId{n+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>')
    rels.append(f'<Relationship Id="rId{n+2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>')
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{''.join(rels)}</Relationships>"""


def slide_rels() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>"""


def master_xml() -> str:
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
             xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree>
    <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
    <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
  </p:spTree></p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
</p:sldMaster>"""


def layout_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
             xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank">
  <p:cSld name="Blank"><p:spTree>
    <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
    <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
  </p:spTree></p:cSld>
</p:sldLayout>"""


def theme_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="LowAltitudeTheme">
  <a:themeElements>
    <a:clrScheme name="Office">
      <a:dk1><a:srgbClr val="0F172A"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="1F2937"/></a:dk2><a:lt2><a:srgbClr val="F7F9FC"/></a:lt2>
      <a:accent1><a:srgbClr val="2563EB"/></a:accent1><a:accent2><a:srgbClr val="0891B2"/></a:accent2>
      <a:accent3><a:srgbClr val="16A34A"/></a:accent3><a:accent4><a:srgbClr val="F59E0B"/></a:accent4>
      <a:accent5><a:srgbClr val="DC2626"/></a:accent5><a:accent6><a:srgbClr val="7C3AED"/></a:accent6>
      <a:hlink><a:srgbClr val="2563EB"/></a:hlink><a:folHlink><a:srgbClr val="7C3AED"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="YaHei"><a:majorFont><a:latin typeface="Microsoft YaHei"/><a:ea typeface="Microsoft YaHei"/></a:majorFont><a:minorFont><a:latin typeface="Microsoft YaHei"/><a:ea typeface="Microsoft YaHei"/></a:minorFont></a:fontScheme>
    <a:fmtScheme name="Clean"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>
  </a:themeElements>
</a:theme>"""


def app_xml(n: int) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
            xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Codex</Application><PresentationFormat>宽屏</PresentationFormat><Slides>{n}</Slides>
</Properties>"""


def core_xml() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
                   xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:dcterms="http://purl.org/dc/terms/"
                   xmlns:dcmitype="http://purl.org/dc/dcmitype/"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>低空数字孪生平台竞品分析与系统功能需求分析汇报</dc:title>
  <dc:creator>Codex</dc:creator>
  <cp:lastModifiedBy>Codex</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">2026-05-15T00:00:00Z</dcterms:created>
  <dcterms:modified xsi:type="dcterms:W3CDTF">2026-05-15T00:00:00Z</dcterms:modified>
</cp:coreProperties>"""


def card(x: float, y: float, w: float, h: float, title: str, body: Iterable[str], accent: str = "2563EB") -> List[Shape]:
    return [
        Shape("rect", x, y, w, h, fill="FFFFFF", line="E2E8F0", radius=True),
        Shape("rect", x, y, 0.08, h, fill=accent, line="none"),
        Shape("text", x + 0.18, y + 0.13, w - 0.28, 0.28, title, fill="none", line="none", font_size=13, bold=True, text_color="0F172A", margin=0),
        Shape("text", x + 0.18, y + 0.48, w - 0.32, h - 0.58, paragraphs=[f"- {b}" for b in body], fill="none", line="none", font_size=9, text_color="475569", margin=0),
    ]


def metric(x: float, y: float, label: str, value: str, color_hex: str) -> List[Shape]:
    return [
        Shape("rect", x, y, 2.25, 1.05, fill="FFFFFF", line="E2E8F0", radius=True),
        Shape("text", x + 0.15, y + 0.15, 1.95, 0.22, label, fill="none", line="none", font_size=9, text_color="64748B", margin=0),
        Shape("text", x + 0.15, y + 0.43, 1.95, 0.38, value, fill="none", line="none", font_size=18, bold=True, text_color=color_hex, margin=0),
    ]


def build_deck() -> Deck:
    d = Deck()

    d.add(Slide(
        "",
        shapes=[
            Shape("rect", 0, 0, SLIDE_W, SLIDE_H, fill="0F172A", line="none"),
            Shape("rect", 0, 0, SLIDE_W, 0.16, fill="38BDF8", line="none"),
            Shape("text", 0.7, 1.15, 7.8, 0.65, "低空数字孪生平台", fill="none", line="none", font_size=30, bold=True, text_color="FFFFFF", margin=0),
            Shape("text", 0.72, 1.86, 8.7, 0.48, "竞品分析与系统功能需求分析汇报", fill="none", line="none", font_size=20, bold=True, text_color="BAE6FD", margin=0),
            Shape("text", 0.75, 2.65, 7.9, 0.62, "面向低空空域治理、飞行服务、运行监管与产业运营的一体化数字底座", fill="none", line="none", font_size=13, text_color="CBD5E1", margin=0),
            Shape("rect", 8.95, 1.15, 3.35, 4.7, fill="172554", line="334155", radius=True),
            Shape("text", 9.25, 1.6, 2.7, 0.35, "汇报主线", fill="none", line="none", font_size=16, bold=True, text_color="FFFFFF", margin=0),
            Shape("text", 9.25, 2.1, 2.55, 2.8, paragraphs=[
                "- 行业与政策驱动",
                "- 竞品格局与机会",
                "- 平台定位与功能蓝图",
                "- 分期建设与关键指标",
            ], fill="none", line="none", font_size=12, text_color="E0F2FE", margin=0),
            Shape("text", 0.75, 6.65, 5.4, 0.26, "2026年5月", fill="none", line="none", font_size=10, text_color="94A3B8", margin=0),
        ],
    ))

    d.add(Slide(
        "核心结论",
        "低空数字孪生平台的竞争焦点，正在从可视化展示转向可运营、可监管、可仿真的城市级低空基础设施。",
        shapes=[
            *card(0.65, 1.35, 3.75, 1.55, "定位判断", ["不是单一三维大屏，而是低空运行数字底座", "覆盖规划、审批、执行、监管、复盘闭环"], "2563EB"),
            *card(4.78, 1.35, 3.75, 1.55, "竞品判断", ["国内强在城市项目和数字底座", "国际强在 UTM/U-space 合规工作流"], "0891B2"),
            *card(8.92, 1.35, 3.75, 1.55, "机会判断", ["用四维空域、仿真、开放接口拉开差异", "设备中立和规则可配置决定复制能力"], "16A34A"),
            Shape("rect", 0.65, 3.35, 12.0, 2.55, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 0.95, 3.68, 2.0, 0.3, "一句话目标", fill="none", line="none", font_size=14, bold=True, text_color="0F172A", margin=0),
            Shape("text", 2.85, 3.56, 9.2, 0.55, "把低空飞行从“看得见”推进到“算得出、批得快、管得住、调得动、可运营”。", fill="none", line="none", font_size=20, bold=True, text_color="2563EB", margin=0),
            Shape("text", 0.95, 4.46, 10.8, 0.85, paragraphs=[
                "- 一期先打穿飞行计划、审批、监控、告警、复盘的最小闭环。",
                "- 二期补齐四维空域、容量评估、多源感知、应急指挥和仿真能力。",
                "- 三期扩展 AI 优化、计费结算、生态接入和跨城市复制。"
            ], fill="none", line="none", font_size=12, text_color="475569", margin=0),
        ],
    ))

    d.add(Slide(
        "行业与政策驱动",
        "低空经济进入安全健康发展阶段，平台建设从试点展示走向高频运行保障。",
        shapes=[
            *metric(0.75, 1.32, "政策方向", "安全健康发展", "2563EB"),
            *metric(3.25, 1.32, "应用路径", "先载货后载人", "0891B2"),
            *metric(5.75, 1.32, "运行原则", "先隔离后融合", "16A34A"),
            *metric(8.25, 1.32, "部署逻辑", "先远郊后城区", "F59E0B"),
            Shape("rect", 10.75, 1.32, 1.9, 1.05, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 10.92, 1.47, 1.55, 0.22, "监管趋势", fill="none", line="none", font_size=9, text_color="64748B", margin=0),
            Shape("text", 10.92, 1.75, 1.55, 0.35, "UOM/USS", fill="none", line="none", font_size=17, bold=True, text_color="DC2626", margin=0),
            Shape("rect", 0.75, 2.85, 12.0, 2.8, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 1.05, 3.18, 11.2, 1.85, paragraphs=[
                "- 《无人驾驶航空器飞行管理暂行条例》已实施，实名登记、飞行申请、识别信息报送、运行安全责任成为平台基础要求。",
                "- 民航局正在推进 UOM 与 USS 数据接口标准，地方低空飞行服务保障体系建设将更依赖标准化平台能力。",
                "- 通信感知、微气象、空域网格、实时航迹和仿真推演共同构成低空数字孪生的技术底座。"
            ], fill="none", line="none", font_size=13, text_color="334155", margin=0),
            Shape("text", 1.05, 5.26, 10.9, 0.18, "建设含义：平台必须内置合规流程、数据接口、安全留痕和业务连续性，不能只做三维展示。", fill="none", line="none", font_size=10, bold=True, text_color="0F172A", margin=0),
        ],
    ))

    d.add(Slide(
        "竞品格局总览",
        "市场上形成四类典型平台，各有优势，也留下了产品化和运营闭环的机会。",
        shapes=[
            *card(0.65, 1.35, 2.9, 3.8, "城市级管服/孪生", ["深城交", "中科星图", "莱斯信息", "飞沃智航", "冰柏科技"], "2563EB"),
            *card(3.85, 1.35, 2.9, 3.8, "国际 UTM/U-space", ["Altitude Angel", "Unifly", "ANRA", "OneSky"], "0891B2"),
            *card(7.05, 1.35, 2.9, 3.8, "无人机作业运营", ["DJI FlightHub 2", "机库/无人机厂商平台", "巡检作业系统"], "16A34A"),
            *card(10.25, 1.35, 2.4, 3.8, "行业场景平台", ["应急", "巡检", "物流", "文旅", "农业"], "F59E0B"),
            Shape("rect", 0.65, 5.55, 12.0, 0.68, fill="EFF6FF", line="BFDBFE", radius=True),
            Shape("text", 0.95, 5.73, 11.2, 0.24, "机会：将城市级管服的治理深度、UTM 的合规流程、作业平台的任务闭环、场景平台的业务价值整合到一个可复制底座。", fill="none", line="none", font_size=12, bold=True, text_color="1E40AF", margin=0),
        ],
    ))

    d.add(Slide(
        "国内竞品对比",
        "国内厂商更贴近政府项目和本地空域治理，差异主要体现在底座能力、空管经验和产品化程度。",
        shapes=[
            Shape("rect", 0.55, 1.22, 12.25, 4.85, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("rect", 0.55, 1.22, 12.25, 0.45, fill="E2E8F0", line="none"),
            Shape("text", 0.75, 1.34, 1.4, 0.18, "竞品", fill="none", line="none", font_size=9, bold=True, text_color="0F172A", margin=0),
            Shape("text", 2.35, 1.34, 3.0, 0.18, "核心优势", fill="none", line="none", font_size=9, bold=True, text_color="0F172A", margin=0),
            Shape("text", 5.8, 1.34, 3.0, 0.18, "可学习点", fill="none", line="none", font_size=9, bold=True, text_color="0F172A", margin=0),
            Shape("text", 9.1, 1.34, 3.0, 0.18, "可突破点", fill="none", line="none", font_size=9, bold=True, text_color="0F172A", margin=0),
            Shape("text", 0.75, 1.88, 1.25, 0.26, "深城交", fill="none", line="none", font_size=10, bold=True, text_color="2563EB", margin=0),
            Shape("text", 2.35, 1.82, 2.8, 0.42, "城市交通规划、CIM、低空管服", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 5.8, 1.82, 2.8, 0.42, "低空纳入城市交通体系", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 9.1, 1.82, 2.8, 0.42, "轻量化、标准化复制", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 0.75, 2.58, 1.25, 0.26, "中科星图", fill="none", line="none", font_size=10, bold=True, text_color="2563EB", margin=0),
            Shape("text", 2.35, 2.52, 2.8, 0.42, "空天数据、数字地球、网格剖分", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 5.8, 2.52, 2.8, 0.42, "多圈层数据 + 仿真计算", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 9.1, 2.52, 2.8, 0.42, "运营闭环和生态接口", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 0.75, 3.28, 1.25, 0.26, "莱斯信息", fill="none", line="none", font_size=10, bold=True, text_color="2563EB", margin=0),
            Shape("text", 2.35, 3.22, 2.8, 0.42, "空管信息化、实时监视、高并发", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 5.8, 3.22, 2.8, 0.42, "用性能指标证明工程能力", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 9.1, 3.22, 2.8, 0.42, "城市治理和运营体验", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 0.75, 3.98, 1.25, 0.26, "飞沃智航", fill="none", line="none", font_size=10, bold=True, text_color="2563EB", margin=0),
            Shape("text", 2.35, 3.92, 2.8, 0.42, "4D 空域、AI 规划、三维交互", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 5.8, 3.92, 2.8, 0.42, "时间维组织航线和容量", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 9.1, 3.92, 2.8, 0.42, "政府级监管合规", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 0.75, 4.68, 1.25, 0.26, "冰柏科技", fill="none", line="none", font_size=10, bold=True, text_color="2563EB", margin=0),
            Shape("text", 2.35, 4.62, 2.8, 0.42, "1底座+1平台+N场景", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 5.8, 4.62, 2.8, 0.42, "场景复制和分阶段落地", fill="none", line="none", font_size=9, text_color="334155", margin=0),
            Shape("text", 9.1, 4.62, 2.8, 0.42, "大规模运行硬指标", fill="none", line="none", font_size=9, text_color="334155", margin=0),
        ],
    ))

    d.add(Slide(
        "国际 UTM/U-space 启示",
        "国际平台的价值不在视觉效果，而在飞行授权、合规服务、安全治理和业务连续性。",
        shapes=[
            *card(0.65, 1.35, 2.9, 3.8, "Altitude Angel", ["飞行请求与审批", "禁飞/关闭空域管理", "传感器和反制数据集成", "一致性监控"], "2563EB"),
            *card(3.85, 1.35, 2.9, 3.8, "Unifly", ["适配集中式/分布式 UTM", "监管模型可配置", "多语言和品牌化部署"], "0891B2"),
            *card(7.05, 1.35, 2.9, 3.8, "ANRA", ["EASA U-space 认证", "网络识别、地理感知", "安全、网络安全、连续性"], "16A34A"),
            *card(10.25, 1.35, 2.4, 3.8, "OneSky", ["4D 态势感知", "建模仿真", "运行中心决策支持"], "F59E0B"),
            Shape("rect", 0.65, 5.55, 12.0, 0.68, fill="ECFEFF", line="A5F3FC", radius=True),
            Shape("text", 0.95, 5.73, 11.2, 0.24, "产品启示：把监管流程、数据可信、接口标准和运行连续性前置到架构中，形成可证明的安全服务能力。", fill="none", line="none", font_size=12, bold=True, text_color="155E75", margin=0),
        ],
    ))

    d.add(Slide(
        "竞品空白与突破方向",
        "差异化不靠堆功能，而靠把平台从项目交付变成持续运营能力。",
        shapes=[
            Shape("rect", 0.8, 1.35, 5.25, 4.35, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 1.1, 1.65, 4.5, 0.35, "竞品常见短板", fill="none", line="none", font_size=16, bold=True, text_color="DC2626", margin=0),
            Shape("text", 1.1, 2.2, 4.35, 2.5, paragraphs=[
                "- 偏项目制，跨城市复制成本高",
                "- 三维展示强，业务闭环弱",
                "- 设备或场景绑定，开放生态不足",
                "- 仿真结果难反哺审批和运营",
                "- 安全、审计、业务连续性常被后置"
            ], fill="none", line="none", font_size=13, text_color="475569", margin=0),
            Shape("rect", 7.25, 1.35, 5.25, 4.35, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 7.55, 1.65, 4.5, 0.35, "建议突破方向", fill="none", line="none", font_size=16, bold=True, text_color="16A34A", margin=0),
            Shape("text", 7.55, 2.2, 4.35, 2.5, paragraphs=[
                "- 四维空域网格作为核心资产",
                "- 规划-审批-执行-监控-复盘闭环",
                "- 规则、接口、场景应用插件化",
                "- 设备中立，兼容多源感知",
                "- 轻重两套交付，支持快速落地"
            ], fill="none", line="none", font_size=13, text_color="475569", margin=0),
            Shape("rect", 5.95, 3.28, 1.4, 0.55, fill="2563EB", line="none", radius=True),
            Shape("text", 6.12, 3.44, 1.05, 0.2, "转化为", fill="none", line="none", font_size=11, bold=True, text_color="FFFFFF", align="c", margin=0),
        ],
    ))

    d.add(Slide(
        "平台总体定位",
        "建议定位为“低空数字孪生与运行服务平台”，支撑监管、服务、运营三类角色。",
        shapes=[
            Shape("rect", 0.72, 1.25, 11.9, 0.72, fill="DBEAFE", line="BFDBFE", radius=True),
            Shape("text", 1.0, 1.48, 11.2, 0.24, "低空运行数字底座 + 空域/航线/设施规划仿真 + 飞行服务与运行监管 + 场景运营应用", fill="none", line="none", font_size=14, bold=True, text_color="1E3A8A", margin=0),
            *card(0.72, 2.35, 2.15, 2.6, "数据资源层", ["GIS/CIM/BIM", "空域规则", "低空设施", "主体/航空器", "实时运行数据"], "64748B"),
            *card(3.2, 2.35, 2.15, 2.6, "孪生底座层", ["三维场景", "四维空域网格", "动态实体", "规则引擎", "仿真引擎"], "2563EB"),
            *card(5.68, 2.35, 2.15, 2.6, "管控服务层", ["空域规划", "飞行服务", "运行监控", "安全监管", "应急指挥"], "0891B2"),
            *card(8.16, 2.35, 2.15, 2.6, "场景应用层", ["应急", "巡检", "物流", "文旅", "城市治理"], "16A34A"),
            *card(10.64, 2.35, 1.95, 2.6, "开放生态层", ["API/SDK", "UOM/USS", "设备接入", "业务系统"], "F59E0B"),
            Shape("rect", 0.72, 5.55, 11.9, 0.55, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 1.02, 5.72, 11.2, 0.18, "核心设计原则：底座统一、规则可配、接口开放、场景可插拔、运行可审计。", fill="none", line="none", font_size=11, bold=True, text_color="0F172A", margin=0),
        ],
    ))

    d.add(Slide(
        "业务闭环",
        "平台价值来自全生命周期闭环，而不是单点功能。",
        shapes=[
            Shape("rect", 0.8, 2.45, 1.55, 0.75, "规划", fill="DBEAFE", line="93C5FD", radius=True, font_size=18, bold=True, text_color="1E3A8A", align="c"),
            Shape("rect", 2.65, 2.45, 1.55, 0.75, "申报", fill="ECFEFF", line="67E8F9", radius=True, font_size=18, bold=True, text_color="155E75", align="c"),
            Shape("rect", 4.5, 2.45, 1.55, 0.75, "审批", fill="DCFCE7", line="86EFAC", radius=True, font_size=18, bold=True, text_color="166534", align="c"),
            Shape("rect", 6.35, 2.45, 1.55, 0.75, "执行", fill="FEF3C7", line="FCD34D", radius=True, font_size=18, bold=True, text_color="92400E", align="c"),
            Shape("rect", 8.2, 2.45, 1.55, 0.75, "监控", fill="FEE2E2", line="FCA5A5", radius=True, font_size=18, bold=True, text_color="991B1B", align="c"),
            Shape("rect", 10.05, 2.45, 1.55, 0.75, "处置", fill="F3E8FF", line="C4B5FD", radius=True, font_size=18, bold=True, text_color="6D28D9", align="c"),
            Shape("rect", 11.2, 4.2, 1.2, 0.6, "复盘", fill="FFFFFF", line="CBD5E1", radius=True, font_size=15, bold=True, text_color="0F172A", align="c"),
            Shape("text", 0.95, 3.55, 10.2, 0.85, paragraphs=[
                "- 规划成果沉淀为空域、航路、起降点、容量和规则。",
                "- 审批授权进入动态放行和运行监控，异常事件进入处置流程。",
                "- 复盘结果反哺规则、航线、容量、设施选址和运营指标。"
            ], fill="none", line="none", font_size=12, text_color="475569", margin=0),
            Shape("rect", 0.8, 5.25, 11.6, 0.62, fill="EFF6FF", line="BFDBFE", radius=True),
            Shape("text", 1.08, 5.44, 10.9, 0.2, "闭环验收建议：任一飞行计划都能追溯到申请、审批、放行、航迹、告警、处置和归档记录。", fill="none", line="none", font_size=11, bold=True, text_color="1E40AF", margin=0),
        ],
    ))

    d.add(Slide(
        "系统功能蓝图",
        "按平台能力拆成七个功能域，既能支撑监管，也能支撑运营。",
        shapes=[
            *card(0.55, 1.25, 2.35, 1.45, "1 低空一张图", ["三维场景", "专题图层", "动态实体"], "2563EB"),
            *card(3.1, 1.25, 2.35, 1.45, "2 空域规划", ["空域建模", "航路设计", "设施选址"], "0891B2"),
            *card(5.65, 1.25, 2.35, 1.45, "3 飞行服务", ["计划申报", "风险评估", "审批协同"], "16A34A"),
            *card(8.2, 1.25, 2.35, 1.45, "4 运行监控", ["航迹接入", "冲突检测", "告警中心"], "F59E0B"),
            *card(10.75, 1.25, 2.0, 1.45, "5 安全监管", ["电子围栏", "应急空域", "反制联动"], "DC2626"),
            *card(1.8, 3.45, 2.75, 1.55, "6 仿真与 AI", ["交通流仿真", "容量预测", "AI 航线优化"], "7C3AED"),
            *card(4.9, 3.45, 2.75, 1.55, "7 场景应用", ["应急", "巡检", "物流", "文旅"], "0F766E"),
            *card(8.0, 3.45, 2.75, 1.55, "8 运营管理", ["租户", "计费", "指标", "生态接入"], "475569"),
            Shape("rect", 0.75, 5.55, 11.8, 0.55, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 1.02, 5.72, 11.1, 0.18, "优先级：P0 打通“申报审批 + 运行监控 + 告警处置”；P1 扩展“四维空域 + 仿真 + 多源感知”；P2 做 AI 与商业运营。", fill="none", line="none", font_size=10.5, bold=True, text_color="0F172A", margin=0),
        ],
    ))

    d.add(Slide(
        "一期 MVP 范围",
        "一期目标是建立可演示、可试运行、可验收的低空运行最小闭环。",
        shapes=[
            Shape("rect", 0.7, 1.25, 3.8, 4.55, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 1.0, 1.56, 3.2, 0.32, "基础底座", fill="none", line="none", font_size=15, bold=True, text_color="2563EB", margin=0),
            Shape("text", 1.0, 2.05, 3.1, 2.7, paragraphs=[
                "- 低空一张图",
                "- 空域/航线/起降点",
                "- 主体与航空器台账",
                "- 基础数据导入",
                "- 无人机/机库接入"
            ], fill="none", line="none", font_size=13, text_color="475569", margin=0),
            Shape("rect", 4.85, 1.25, 3.8, 4.55, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 5.15, 1.56, 3.2, 0.32, "业务闭环", fill="none", line="none", font_size=15, bold=True, text_color="16A34A", margin=0),
            Shape("text", 5.15, 2.05, 3.1, 2.7, paragraphs=[
                "- 飞行计划申报",
                "- 审批流程配置",
                "- 航线规划与风险校验",
                "- 实时航迹监控",
                "- 告警处置与复盘"
            ], fill="none", line="none", font_size=13, text_color="475569", margin=0),
            Shape("rect", 9.0, 1.25, 3.2, 4.55, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 9.3, 1.56, 2.55, 0.32, "验收指标", fill="none", line="none", font_size=15, bold=True, text_color="F59E0B", margin=0),
            Shape("text", 9.3, 2.05, 2.45, 2.7, paragraphs=[
                "- 计划可追溯",
                "- 审批可留痕",
                "- 航迹可回放",
                "- 越界/超高/偏航可告警",
                "- 运行统计可输出"
            ], fill="none", line="none", font_size=13, text_color="475569", margin=0),
        ],
    ))

    d.add(Slide(
        "二三期演进路线",
        "从最小闭环逐步走向城市级运行服务和产业运营平台。",
        shapes=[
            Shape("rect", 0.75, 1.45, 3.55, 3.75, fill="FFFFFF", line="93C5FD", radius=True),
            Shape("text", 1.05, 1.78, 2.7, 0.36, "一期：闭环可用", fill="none", line="none", font_size=16, bold=True, text_color="1D4ED8", margin=0),
            Shape("text", 1.05, 2.35, 2.85, 2.1, paragraphs=["- 一张图", "- 计划申报", "- 审批协同", "- 实时监控", "- 告警处置"], fill="none", line="none", font_size=13, text_color="475569", margin=0),
            Shape("rect", 4.9, 1.45, 3.55, 3.75, fill="FFFFFF", line="86EFAC", radius=True),
            Shape("text", 5.2, 1.78, 2.7, 0.36, "二期：能力增强", fill="none", line="none", font_size=16, bold=True, text_color="15803D", margin=0),
            Shape("text", 5.2, 2.35, 2.85, 2.1, paragraphs=["- 四维空域网格", "- 容量评估", "- 多源感知融合", "- 应急指挥", "- 设施选址仿真"], fill="none", line="none", font_size=13, text_color="475569", margin=0),
            Shape("rect", 9.05, 1.45, 3.55, 3.75, fill="FFFFFF", line="C4B5FD", radius=True),
            Shape("text", 9.35, 1.78, 2.7, 0.36, "三期：运营生态", fill="none", line="none", font_size=16, bold=True, text_color="6D28D9", margin=0),
            Shape("text", 9.35, 2.35, 2.85, 2.1, paragraphs=["- AI 航线优化", "- 计费结算", "- 开放 API/SDK", "- 行业应用市场", "- 跨城市复制"], fill="none", line="none", font_size=13, text_color="475569", margin=0),
            Shape("rect", 0.75, 5.55, 11.85, 0.6, fill="EFF6FF", line="BFDBFE", radius=True),
            Shape("text", 1.02, 5.74, 11.2, 0.18, "阶段策略：先服务监管刚需，再提高运行效率，最后形成平台运营收入和生态扩展能力。", fill="none", line="none", font_size=11, bold=True, text_color="1E40AF", margin=0),
        ],
    ))

    d.add(Slide(
        "数据与接口体系",
        "数据接口决定平台能否从单点系统升级为低空数字基础设施。",
        shapes=[
            Shape("rect", 4.72, 2.45, 3.9, 1.25, "低空数字孪生与运行服务平台", fill="2563EB", line="1D4ED8", radius=True, font_size=18, bold=True, text_color="FFFFFF", align="c"),
            *card(0.65, 1.05, 2.7, 1.35, "监管接口", ["UOM/USS", "实名登记", "飞行计划", "运行事件"], "DC2626"),
            *card(0.65, 4.25, 2.7, 1.35, "空间数据", ["GIS/CIM/BIM", "影像地形", "障碍物", "基础设施"], "2563EB"),
            *card(5.05, 4.95, 2.7, 1.15, "环境数据", ["气象", "风场", "电磁", "通信覆盖"], "0891B2"),
            *card(9.95, 4.25, 2.7, 1.35, "设备接入", ["无人机/机库", "雷达/光电", "Remote ID", "5G-A 通感"], "16A34A"),
            *card(9.95, 1.05, 2.7, 1.35, "业务系统", ["应急/公安", "城管/交通", "行业工单", "支付结算"], "F59E0B"),
            Shape("text", 4.78, 3.92, 3.75, 0.32, "统一身份、统一时空基准、统一规则、统一审计", fill="none", line="none", font_size=11, bold=True, text_color="0F172A", align="c", margin=0),
        ],
    ))

    d.add(Slide(
        "关键指标与价值",
        "建议用安全、效率、运行、稳定、运营、数据六类指标衡量建设成效。",
        shapes=[
            *card(0.65, 1.25, 3.75, 1.35, "安全价值", ["越界/冲突提前预警", "黑飞识别与处置闭环", "重大活动低空保障"], "DC2626"),
            *card(4.78, 1.25, 3.75, 1.35, "效率价值", ["审批时长下降", "航线规划自动校验", "任务准点率提升"], "2563EB"),
            *card(8.92, 1.25, 3.75, 1.35, "运行价值", ["空域利用率提升", "航路/起降点容量可计算", "设备在线率可监管"], "16A34A"),
            *card(0.65, 3.25, 3.75, 1.35, "运营价值", ["服务费、起降费、场景应用收入", "租户和生态接入", "单架次服务成本下降"], "F59E0B"),
            *card(4.78, 3.25, 3.75, 1.35, "数据价值", ["统一低空数据资产", "历史轨迹和事件可追溯", "数据质量可评分"], "0891B2"),
            *card(8.92, 3.25, 3.75, 1.35, "治理价值", ["监管有抓手", "产业有底座", "城市有标准化能力"], "7C3AED"),
            Shape("rect", 0.65, 5.35, 12.0, 0.62, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 0.95, 5.55, 11.2, 0.18, "最终目标：形成可持续运行的低空基础设施，而非一次性交付的信息化项目。", fill="none", line="none", font_size=12, bold=True, text_color="0F172A", margin=0),
        ],
    ))

    d.add(Slide(
        "风险与保障措施",
        "低空平台的主要风险来自监管变化、数据质量、设备碎片化和工程性能。",
        shapes=[
            *card(0.65, 1.25, 2.9, 3.8, "监管接口变化", ["建立接口适配层", "字段映射和版本管理", "保留人工补录和审核"], "DC2626"),
            *card(3.85, 1.25, 2.9, 3.8, "数据质量不足", ["关键区域校核", "障碍物和航线版本管理", "数据质量评分"], "F59E0B"),
            *card(7.05, 1.25, 2.9, 3.8, "设备生态碎片", ["统一接入网关", "协议适配器", "设备能力画像"], "0891B2"),
            *card(10.25, 1.25, 2.4, 3.8, "实时性能压力", ["流式处理", "空间索引", "实时/历史服务拆分"], "2563EB"),
            Shape("rect", 0.65, 5.45, 12.0, 0.62, fill="FEF2F2", line="FECACA", radius=True),
            Shape("text", 0.95, 5.65, 11.2, 0.18, "管理建议：验收口径围绕业务闭环和运行指标设定，避免项目滑向只看大屏效果。", fill="none", line="none", font_size=11, bold=True, text_color="991B1B", margin=0),
        ],
    ))

    d.add(Slide(
        "下一步建议",
        "建议以一个示范区域和两类高价值场景启动，快速形成可看、可用、可验收的样板。",
        shapes=[
            Shape("rect", 0.85, 1.35, 11.65, 3.65, fill="FFFFFF", line="E2E8F0", radius=True),
            Shape("text", 1.2, 1.7, 10.8, 2.35, paragraphs=[
                "- 选定示范区域：园区、景区、港口、机场周边或城市重点片区。",
                "- 明确一期数据清单：空域、航线、起降点、障碍物、设备、主体、航空器。",
                "- 选择两类场景打深：建议优先应急保障 + 城市治理/巡检。",
                "- 定义验收脚本：从飞行申请到审批、放行、监控、告警、复盘全链条演示。",
                "- 同步启动接口方案：预留 UOM/USS、无人机厂商、GIS/CIM、应急平台对接。"
            ], fill="none", line="none", font_size=15, text_color="334155", margin=0),
            Shape("rect", 0.85, 5.45, 11.65, 0.72, fill="0F172A", line="none", radius=True),
            Shape("text", 1.15, 5.68, 11.0, 0.22, "汇报建议落点：以低空安全监管为刚需切入，以飞行服务闭环为一期抓手，以场景运营和生态接口形成长期价值。", fill="none", line="none", font_size=12, bold=True, text_color="FFFFFF", margin=0),
        ],
    ))

    return d


def write_deck(deck: Deck, path: str) -> None:
    n = len(deck.slides)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types(n))
        z.writestr("_rels/.rels", rels_root())
        z.writestr("ppt/presentation.xml", presentation_xml(n))
        z.writestr("ppt/_rels/presentation.xml.rels", presentation_rels(n))
        z.writestr("ppt/theme/theme1.xml", theme_xml())
        z.writestr("ppt/slideMasters/slideMaster1.xml", master_xml())
        z.writestr("ppt/slideMasters/_rels/slideMaster1.xml.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>""")
        z.writestr("ppt/slideLayouts/slideLayout1.xml", layout_xml())
        z.writestr("ppt/slideLayouts/_rels/slideLayout1.xml.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>""")
        z.writestr("docProps/app.xml", app_xml(n))
        z.writestr("docProps/core.xml", core_xml())
        for i, slide in enumerate(deck.slides, start=1):
            z.writestr(f"ppt/slides/slide{i}.xml", base_slide(slide, i))
            z.writestr(f"ppt/slides/_rels/slide{i}.xml.rels", slide_rels())


if __name__ == "__main__":
    deck = build_deck()
    write_deck(deck, OUT)
    print(os.path.abspath(OUT))
