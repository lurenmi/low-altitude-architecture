from __future__ import annotations

import html
import os
import zipfile
from dataclasses import dataclass, field
from typing import List, Optional


OUT = "低空数字孪生平台竞品分析与系统功能需求分析汇报.pptx"

EMU = 914400
SLIDE_W = 13.333333
SLIDE_H = 7.5
W = int(SLIDE_W * EMU)
H = int(SLIDE_H * EMU)

BG = "0B0D10"
PANEL = "151922"
PANEL2 = "1E232D"
LINE = "343A46"
YELLOW = "FFD21F"
YELLOW2 = "F59E0B"
CYAN = "00E5FF"
GREEN = "22C55E"
RED = "EF4444"
TEXT = "E5E7EB"
MUTED = "94A3B8"
DIM = "64748B"


def e(v: float) -> int:
    return int(v * EMU)


def esc(v: str) -> str:
    return html.escape(v, quote=True)


def c(v: str) -> str:
    return v.replace("#", "").upper()


@dataclass
class Shape:
    x: float
    y: float
    w: float
    h: float
    text: str = ""
    fill: str = "none"
    line: str = "none"
    geom: str = "rect"
    font: int = 12
    bold: bool = False
    color: str = TEXT
    align: str = "l"
    valign: str = "mid"
    margin: float = 0.06
    paragraphs: Optional[List[str]] = None
    line_w: int = 1


@dataclass
class Slide:
    title: str = ""
    subtitle: str = ""
    shapes: List[Shape] = field(default_factory=list)
    section: str = ""


def body_xml(s: Shape) -> str:
    paras = s.paragraphs if s.paragraphs is not None else [s.text]
    mar = e(s.margin)
    anchor = "ctr" if s.valign == "mid" else "t"
    out = []
    for idx, raw in enumerate(paras):
        bullet = raw.startswith("- ") or raw.startswith("• ")
        txt = raw[2:] if bullet else raw
        size = int(round(s.font * 100))
        b = ' b="1"' if s.bold and (idx == 0 or s.paragraphs is None) else ""
        bullet_xml = '<a:buChar char="•"/>' if bullet else "<a:buNone/>"
        out.append(
            f'<a:p><a:pPr algn="{s.align}" marL="{e(0.15) if bullet else 0}" '
            f'indent="{e(-0.11) if bullet else 0}">{bullet_xml}</a:pPr>'
            f'<a:r><a:rPr lang="zh-CN" sz="{size}"{b}>'
            f'<a:solidFill><a:srgbClr val="{c(s.color)}"/></a:solidFill>'
            f'<a:latin typeface="Microsoft YaHei"/><a:ea typeface="Microsoft YaHei"/>'
            f'</a:rPr><a:t>{esc(txt)}</a:t></a:r>'
            f'<a:endParaRPr lang="zh-CN" sz="{size}"/></a:p>'
        )
    return (
        f'<p:txBody><a:bodyPr wrap="square" lIns="{mar}" tIns="{mar}" '
        f'rIns="{mar}" bIns="{mar}" anchor="{anchor}"/><a:lstStyle/>'
        f'{"".join(out)}</p:txBody>'
    )


def shape_xml(i: int, s: Shape) -> str:
    fill = "<a:noFill/>" if s.fill == "none" else f'<a:solidFill><a:srgbClr val="{c(s.fill)}"/></a:solidFill>'
    line = "<a:ln><a:noFill/></a:ln>" if s.line == "none" else (
        f'<a:ln w="{s.line_w * 9525}"><a:solidFill><a:srgbClr val="{c(s.line)}"/></a:solidFill></a:ln>'
    )
    return f"""
<p:sp>
  <p:nvSpPr><p:cNvPr id="{i}" name="Shape {i}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
  <p:spPr>
    <a:xfrm><a:off x="{e(s.x)}" y="{e(s.y)}"/><a:ext cx="{e(s.w)}" cy="{e(s.h)}"/></a:xfrm>
    <a:prstGeom prst="{s.geom}"><a:avLst/></a:prstGeom>
    {fill}{line}
  </p:spPr>
  {body_xml(s)}
</p:sp>
"""


def rect(x, y, w, h, fill=PANEL, line=LINE, geom="rect", line_w: int = 1) -> Shape:
    return Shape(x, y, w, h, fill=fill, line=line, geom=geom, line_w=line_w)


def txt(x, y, w, h, text, font=12, color=TEXT, bold=False, align="l", valign="mid") -> Shape:
    return Shape(x, y, w, h, text=text, fill="none", line="none", font=font, color=color, bold=bold, align=align, valign=valign, margin=0)


def bullet(x, y, w, h, items: List[str], font=11, color=MUTED) -> Shape:
    return Shape(x, y, w, h, paragraphs=[f"- {v}" for v in items], fill="none", line="none", font=font, color=color, valign="top", margin=0)


def pill(x, y, w, h, text, fill=PANEL2, line=LINE, color=TEXT, font=11, bold=True) -> Shape:
    return Shape(x, y, w, h, text=text, fill=fill, line=line, geom="roundRect", font=font, bold=bold, color=color, align="c")


def panel_title(x, y, title, accent=YELLOW) -> List[Shape]:
    return [
        rect(x, y + 0.03, 0.08, 0.28, fill=accent, line="none"),
        txt(x + 0.16, y, 2.8, 0.35, title, font=14, bold=True, color=TEXT),
    ]


def card(x, y, w, h, title, items, accent=YELLOW) -> List[Shape]:
    return [
        rect(x, y, w, h, fill=PANEL, line=LINE, geom="roundRect"),
        rect(x, y, w, 0.06, fill=accent, line="none"),
        txt(x + 0.18, y + 0.18, w - 0.36, 0.3, title, font=13, bold=True, color=TEXT),
        bullet(x + 0.18, y + 0.6, w - 0.36, h - 0.72, items, font=9, color=MUTED),
    ]


def metric(x, y, label, value, note, accent=YELLOW) -> List[Shape]:
    return [
        rect(x, y, 2.35, 1.04, fill=PANEL, line=LINE, geom="roundRect"),
        txt(x + 0.16, y + 0.13, 1.95, 0.2, label, font=8, color=DIM),
        txt(x + 0.16, y + 0.38, 1.95, 0.34, value, font=18, bold=True, color=accent),
        txt(x + 0.16, y + 0.75, 1.95, 0.16, note, font=7, color=MUTED),
    ]


def background(slide: Slide, idx: int, total: int) -> List[Shape]:
    shapes = [rect(0, 0, SLIDE_W, SLIDE_H, fill=BG, line="none")]
    # subtle grid
    for x in [0.7, 2.1, 3.5, 4.9, 6.3, 7.7, 9.1, 10.5, 11.9]:
        shapes.append(rect(x, 0.8, 0.006, 6.0, fill="171B22", line="none"))
    for y in [1.3, 2.2, 3.1, 4.0, 4.9, 5.8, 6.7]:
        shapes.append(rect(0.45, y, 12.4, 0.006, fill="171B22", line="none"))
    shapes.append(rect(0, 0, SLIDE_W, 0.1, fill=YELLOW, line="none"))
    shapes.append(rect(0.55, 0.36, 0.16, 0.16, fill=YELLOW, line="none"))
    if slide.title:
        shapes.append(txt(0.78, 0.24, 8.7, 0.42, slide.title, font=20, bold=True, color=TEXT))
    if slide.subtitle:
        shapes.append(txt(0.8, 0.72, 9.8, 0.24, slide.subtitle, font=8, color=MUTED))
    if slide.section:
        shapes.append(pill(10.95, 0.35, 1.65, 0.32, slide.section, fill="111827", line=LINE, color=YELLOW, font=8))
    shapes.append(txt(12.15, 7.08, 0.55, 0.2, f"{idx:02d}/{total:02d}", font=7, color=DIM, align="r"))
    return shapes


def slide_xml(slide: Slide, idx: int, total: int) -> str:
    all_shapes = background(slide, idx, total) + slide.shapes
    body = [
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>',
        '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>',
    ]
    for i, s in enumerate(all_shapes, start=2):
        body.append(shape_xml(i, s))
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree>{''.join(body)}</p:spTree></p:cSld>
  <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>"""


def build() -> List[Slide]:
    slides: List[Slide] = []

    slides.append(Slide(
        shapes=[
            rect(0, 0, SLIDE_W, SLIDE_H, fill="07090D", line="none"),
            rect(0, 0, SLIDE_W, 0.12, fill=YELLOW, line="none"),
            txt(0.78, 1.15, 8.4, 0.78, "低空数字孪生平台", font=34, bold=True, color=TEXT),
            txt(0.82, 1.95, 9.2, 0.44, "竞品分析与系统功能需求分析汇报", font=22, bold=True, color=YELLOW),
            txt(0.84, 2.58, 7.8, 0.45, "面向低空空域治理、飞行服务、运行监管与产业运营的一体化数字底座", font=12, color="CBD5E1"),
            pill(0.84, 3.36, 1.42, 0.36, "竞品格局", fill="111827", line=LINE, color=YELLOW, font=9),
            pill(2.42, 3.36, 1.42, 0.36, "功能蓝图", fill="111827", line=LINE, color=YELLOW, font=9),
            pill(4.0, 3.36, 1.42, 0.36, "建设路线", fill="111827", line=LINE, color=YELLOW, font=9),
            pill(5.58, 3.36, 1.42, 0.36, "价值指标", fill="111827", line=LINE, color=YELLOW, font=9),
            # Tech airspace visual
            rect(8.75, 1.22, 3.35, 4.48, fill="10141B", line=LINE, geom="roundRect"),
            txt(9.05, 1.55, 2.7, 0.28, "4D LOW-ALTITUDE TWIN", font=10, bold=True, color=YELLOW, align="c"),
            rect(9.25, 2.15, 2.35, 0.04, fill=YELLOW, line="none"),
            rect(9.45, 2.75, 2.35, 0.04, fill=CYAN, line="none"),
            rect(9.25, 3.35, 2.35, 0.04, fill=YELLOW, line="none"),
            rect(9.45, 3.95, 2.35, 0.04, fill=CYAN, line="none"),
            rect(9.05, 4.55, 2.35, 0.04, fill=YELLOW, line="none"),
            Shape(9.95, 2.05, 0.14, 0.14, fill=YELLOW, line="none", geom="ellipse"),
            Shape(10.7, 2.65, 0.14, 0.14, fill=CYAN, line="none", geom="ellipse"),
            Shape(10.15, 3.25, 0.14, 0.14, fill=YELLOW, line="none", geom="ellipse"),
            Shape(11.15, 3.85, 0.14, 0.14, fill=CYAN, line="none", geom="ellipse"),
            txt(0.82, 6.65, 2.6, 0.22, "2026年5月", font=9, color=DIM),
        ]
    ))

    slides.append(Slide(
        title="核心判断",
        subtitle="低空数字孪生平台的竞争焦点，正在从可视化展示转向可运营、可监管、可仿真的低空基础设施。",
        section="EXEC",
        shapes=[
            *metric(0.78, 1.28, "平台定位", "数字底座", "不是单一三维大屏", YELLOW),
            *metric(3.38, 1.28, "业务主线", "全流程闭环", "规划-审批-执行-复盘", CYAN),
            *metric(5.98, 1.28, "核心资产", "四维空域", "空间+高度+时间+规则", GREEN),
            *metric(8.58, 1.28, "落地策略", "轻重两套", "市级管服+园区快装", YELLOW2),
            rect(0.78, 2.85, 11.75, 2.52, fill=PANEL, line=LINE, geom="roundRect"),
            *panel_title(1.05, 3.15, "一句话结论"),
            txt(1.05, 3.68, 10.95, 0.66, "把低空飞行从“看得见”推进到“算得出、批得快、管得住、调得动、可运营”。", font=22, bold=True, color=YELLOW, align="c"),
            bullet(1.05, 4.55, 10.9, 0.52, [
                "一期打穿飞行计划、审批、放行、监控、告警、复盘的最小闭环",
                "二期补齐四维空域、容量评估、多源感知、应急指挥和仿真能力",
                "三期扩展 AI 优化、计费结算、生态接入和跨城市复制"
            ], font=9, color="CBD5E1"),
            rect(0.78, 5.82, 11.75, 0.52, fill="111827", line=LINE, geom="roundRect"),
            txt(1.05, 5.97, 10.95, 0.18, "汇报建议落点：以低空安全监管为刚需切入，以飞行服务闭环为一期抓手，以场景运营和生态接口形成长期价值。", font=10, bold=True, color=TEXT),
        ]
    ))

    slides.append(Slide(
        title="行业与政策驱动",
        subtitle="低空经济进入“安全健康发展”阶段，平台需求从试点展示转向高频运行保障。",
        section="MARKET",
        shapes=[
            rect(0.9, 1.35, 11.5, 0.06, fill=YELLOW, line="none"),
            Shape(1.2, 1.18, 0.38, 0.38, fill=YELLOW, line="none", geom="ellipse"),
            Shape(4.25, 1.18, 0.38, 0.38, fill=YELLOW, line="none", geom="ellipse"),
            Shape(7.35, 1.18, 0.38, 0.38, fill=YELLOW, line="none", geom="ellipse"),
            Shape(10.45, 1.18, 0.38, 0.38, fill=YELLOW, line="none", geom="ellipse"),
            txt(0.85, 1.68, 1.2, 0.22, "2024", font=13, bold=True, color=YELLOW, align="c"),
            txt(3.9, 1.68, 1.2, 0.22, "2025", font=13, bold=True, color=YELLOW, align="c"),
            txt(7.0, 1.68, 1.2, 0.22, "2026", font=13, bold=True, color=YELLOW, align="c"),
            txt(10.1, 1.68, 1.2, 0.22, "后续", font=13, bold=True, color=YELLOW, align="c"),
            *card(0.75, 2.15, 2.75, 2.4, "法规落地", ["《无人驾驶航空器飞行管理暂行条例》施行", "实名登记、识别报送、飞行申请成为基础要求"], YELLOW),
            *card(3.75, 2.15, 2.75, 2.4, "政策提速", ["推动低空经济安全健康发展", "先载货后载人、先隔离后融合"], CYAN),
            *card(6.75, 2.15, 2.75, 2.4, "接口标准", ["UOM 与 USS 数据接口标准推进", "地方飞行服务保障体系需要平台承载"], GREEN),
            *card(9.75, 2.15, 2.75, 2.4, "规模运行", ["从局部试点走向区域商用", "空域容量、安全监管、运营结算成为重点"], YELLOW2),
            rect(0.75, 5.15, 11.75, 0.72, fill="10141B", line=LINE, geom="roundRect"),
            txt(1.05, 5.38, 11.0, 0.22, "建设含义：平台必须内置合规流程、数据接口、安全留痕和业务连续性，不能只做三维展示。", font=11, bold=True, color=TEXT),
        ]
    ))

    slides.append(Slide(
        title="竞品格局：四类玩家",
        subtitle="不同玩家分别占据政府管服、国际 UTM、设备运营和垂直场景，机会在于整合成可复制的运行底座。",
        section="COMP",
        shapes=[
            rect(1.0, 1.3, 10.8, 4.4, fill="0F131A", line=LINE, geom="roundRect"),
            rect(1.75, 5.35, 9.3, 0.025, fill=LINE, line="none"),
            rect(6.25, 1.75, 0.025, 3.55, fill=LINE, line="none"),
            txt(9.2, 5.55, 2.0, 0.2, "运营闭环强", font=9, color=MUTED, align="r"),
            txt(0.95, 5.55, 2.0, 0.2, "运营闭环弱", font=9, color=MUTED),
            txt(0.7, 1.55, 2.0, 0.2, "治理深度强", font=9, color=MUTED),
            txt(0.7, 5.0, 2.0, 0.2, "治理深度弱", font=9, color=MUTED),
            Shape(3.35, 2.45, 1.3, 1.3, fill="253044", line=YELLOW, geom="ellipse", line_w=2),
            txt(3.43, 2.86, 1.15, 0.2, "城市级管服", font=10, bold=True, color=YELLOW, align="c"),
            txt(2.82, 3.98, 2.4, 0.2, "深城交 / 中科星图 / 莱斯", font=8, color=MUTED, align="c"),
            Shape(7.6, 2.1, 1.25, 1.25, fill="102B30", line=CYAN, geom="ellipse", line_w=2),
            txt(7.73, 2.47, 1.0, 0.22, "UTM", font=12, bold=True, color=CYAN, align="c"),
            txt(7.05, 3.48, 2.3, 0.2, "Altitude Angel / Unifly / ANRA", font=8, color=MUTED, align="c"),
            Shape(7.8, 4.12, 1.15, 1.15, fill="14291B", line=GREEN, geom="ellipse", line_w=2),
            txt(7.9, 4.48, 0.95, 0.2, "作业平台", font=10, bold=True, color=GREEN, align="c"),
            txt(7.35, 5.1, 2.0, 0.18, "DJI FlightHub 2", font=8, color=MUTED, align="c"),
            Shape(4.35, 4.25, 1.15, 1.15, fill="2B2112", line=YELLOW2, geom="ellipse", line_w=2),
            txt(4.45, 4.6, 0.95, 0.2, "场景平台", font=10, bold=True, color=YELLOW2, align="c"),
            rect(0.98, 6.05, 10.85, 0.48, fill=PANEL, line=LINE, geom="roundRect"),
            txt(1.25, 6.2, 10.25, 0.16, "机会：将城市级治理深度、UTM 合规工作流、作业平台任务闭环、场景平台业务价值，整合为统一产品。", font=10, bold=True, color=TEXT),
        ]
    ))

    slides.append(Slide(
        title="国内竞品对比",
        subtitle="国内厂商更贴近地方政府项目，差异主要在数据底座、空管经验、仿真能力和产品化程度。",
        section="COMP",
        shapes=[
            rect(0.65, 1.18, 12.0, 4.75, fill=PANEL, line=LINE, geom="roundRect"),
            rect(0.65, 1.18, 12.0, 0.46, fill="232A35", line="none"),
            txt(0.9, 1.32, 1.25, 0.18, "厂商/产品", font=9, bold=True, color=YELLOW),
            txt(2.35, 1.32, 2.55, 0.18, "核心优势", font=9, bold=True, color=YELLOW),
            txt(5.3, 1.32, 2.7, 0.18, "可借鉴", font=9, bold=True, color=YELLOW),
            txt(8.55, 1.32, 3.1, 0.18, "可突破", font=9, bold=True, color=YELLOW),
            *[
                rect(0.65, y, 12.0, 0.01, fill=LINE, line="none")
                for y in [2.1, 2.88, 3.66, 4.44, 5.22]
            ],
            txt(0.9, 1.82, 1.25, 0.2, "深城交", font=10, bold=True, color=TEXT),
            txt(2.35, 1.76, 2.55, 0.35, "城市交通规划、CIM、低空管服", font=8, color=MUTED),
            txt(5.3, 1.76, 2.7, 0.35, "把低空纳入城市交通治理体系", font=8, color=MUTED),
            txt(8.55, 1.76, 3.1, 0.35, "沉淀轻量化和标准化复制版本", font=8, color=MUTED),
            txt(0.9, 2.6, 1.25, 0.2, "中科星图", font=10, bold=True, color=TEXT),
            txt(2.35, 2.54, 2.55, 0.35, "空天数据、数字地球、空域网格", font=8, color=MUTED),
            txt(5.3, 2.54, 2.7, 0.35, "多圈层数据 + 仿真计算", font=8, color=MUTED),
            txt(8.55, 2.54, 3.1, 0.35, "增强审批、运营结算和生态接口", font=8, color=MUTED),
            txt(0.9, 3.38, 1.25, 0.2, "莱斯信息", font=10, bold=True, color=TEXT),
            txt(2.35, 3.32, 2.55, 0.35, "空管信息化、实时监视、高并发", font=8, color=MUTED),
            txt(5.3, 3.32, 2.7, 0.35, "用性能指标证明工程能力", font=8, color=MUTED),
            txt(8.55, 3.32, 3.1, 0.35, "强化城市运营体验和场景应用", font=8, color=MUTED),
            txt(0.9, 4.16, 1.25, 0.2, "飞沃智航", font=10, bold=True, color=TEXT),
            txt(2.35, 4.1, 2.55, 0.35, "4D 空域、AI 规划、三维交互", font=8, color=MUTED),
            txt(5.3, 4.1, 2.7, 0.35, "用时间维组织容量和冲突", font=8, color=MUTED),
            txt(8.55, 4.1, 3.1, 0.35, "补齐政府级监管和合规能力", font=8, color=MUTED),
            txt(0.9, 4.94, 1.25, 0.2, "冰柏科技", font=10, bold=True, color=TEXT),
            txt(2.35, 4.88, 2.55, 0.35, "1底座 + 1平台 + N场景", font=8, color=MUTED),
            txt(5.3, 4.88, 2.7, 0.35, "分阶段交付和多场景复制", font=8, color=MUTED),
            txt(8.55, 4.88, 3.1, 0.35, "形成大规模运行硬指标", font=8, color=MUTED),
            rect(0.65, 6.18, 12.0, 0.46, fill="111827", line=LINE, geom="roundRect"),
            txt(0.95, 6.33, 11.3, 0.16, "结论：国内竞品项目能力强，但仍有机会在“标准化产品 + 运营闭环 + 开放接口 + 仿真反哺”上形成差异。", font=9, bold=True, color=YELLOW),
        ]
    ))

    slides.append(Slide(
        title="国际 UTM / U-space 启示",
        subtitle="国际平台的强项不是视觉，而是授权、地理感知、网络识别、交通信息、合规审计和连续运行。",
        section="COMP",
        shapes=[
            *card(0.65, 1.22, 2.82, 2.55, "Altitude Angel", ["飞行请求与审批", "禁飞/关闭空域管理", "一致性监控", "传感器和反制数据集成"], YELLOW),
            *card(3.75, 1.22, 2.82, 2.55, "Unifly", ["集中式/分布式 UTM", "监管模型可配置", "国际化与品牌化部署"], CYAN),
            *card(6.85, 1.22, 2.82, 2.55, "ANRA", ["EASA U-space 认证", "网络识别与地理感知", "安全、网安和连续性"], GREEN),
            *card(9.95, 1.22, 2.55, 2.55, "OneSky", ["4D 态势感知", "建模仿真", "运行中心决策支持"], YELLOW2),
            rect(1.1, 4.55, 10.9, 0.06, fill=YELLOW, line="none"),
            *[Shape(x, 4.43, 0.28, 0.28, fill=YELLOW, line="none", geom="ellipse") for x in [1.25, 3.4, 5.55, 7.7, 9.85]],
            txt(0.8, 4.92, 1.25, 0.22, "识别", font=11, bold=True, color=TEXT, align="c"),
            txt(2.95, 4.92, 1.25, 0.22, "感知", font=11, bold=True, color=TEXT, align="c"),
            txt(5.1, 4.92, 1.25, 0.22, "授权", font=11, bold=True, color=TEXT, align="c"),
            txt(7.25, 4.92, 1.25, 0.22, "监控", font=11, bold=True, color=TEXT, align="c"),
            txt(9.4, 4.92, 1.25, 0.22, "审计", font=11, bold=True, color=TEXT, align="c"),
            rect(0.65, 5.85, 11.85, 0.55, fill="10141B", line=LINE, geom="roundRect"),
            txt(0.95, 6.02, 11.25, 0.18, "产品启示：把安全、网络安全、业务连续性、接口标准和软件保证纳入核心需求，而不是验收附录。", font=10, bold=True, color=YELLOW),
        ]
    ))

    slides.append(Slide(
        title="竞品空白与突破方向",
        subtitle="差异化不是堆功能，而是把平台从一次性项目交付变成持续运行能力。",
        section="GAP",
        shapes=[
            rect(0.75, 1.25, 5.35, 4.55, fill=PANEL, line=LINE, geom="roundRect"),
            *panel_title(1.05, 1.58, "竞品常见短板", RED),
            bullet(1.05, 2.18, 4.65, 2.6, [
                "偏项目制，跨城市复制成本高",
                "三维展示强，业务闭环弱",
                "绑定设备或单一场景，开放生态不足",
                "仿真结果难反哺审批和运营",
                "安全、审计、连续性常被后置"
            ], font=12, color="CBD5E1"),
            rect(7.18, 1.25, 5.35, 4.55, fill=PANEL, line=LINE, geom="roundRect"),
            *panel_title(7.48, 1.58, "建议突破方向", GREEN),
            bullet(7.48, 2.18, 4.65, 2.6, [
                "四维空域网格成为核心资产",
                "规划-审批-执行-监控-复盘闭环",
                "规则、接口、场景应用插件化",
                "设备中立，兼容多源感知",
                "轻重两套交付，快速复制"
            ], font=12, color="CBD5E1"),
            pill(6.13, 3.18, 1.02, 0.52, "转化", fill=YELLOW, line="none", color=BG, font=13),
        ]
    ))

    slides.append(Slide(
        title="平台总体定位",
        subtitle="建议定位为“低空数字孪生与运行服务平台”，同时服务政府监管、飞行服务中心和运营企业。",
        section="ARCH",
        shapes=[
            rect(0.78, 1.18, 11.75, 0.7, fill="141820", line=LINE, geom="roundRect"),
            txt(1.08, 1.42, 11.15, 0.2, "低空运行数字底座 + 空域/航线/设施规划仿真 + 飞行服务与运行监管 + 场景运营应用", font=13, bold=True, color=YELLOW, align="c"),
            rect(1.0, 5.42, 11.3, 0.55, fill=PANEL2, line=LINE, geom="roundRect"),
            txt(1.22, 5.6, 10.85, 0.18, "开放生态层：API / SDK / UOM / USS / 设备接入 / 政务与行业系统", font=10, bold=True, color=TEXT, align="c"),
            rect(1.35, 4.62, 10.6, 0.58, fill="18202B", line=LINE, geom="roundRect"),
            txt(1.55, 4.82, 10.2, 0.16, "场景应用层：应急、巡检、物流、城市治理、文旅、测绘、载人交通预研", font=9, color="CBD5E1", align="c"),
            rect(1.7, 3.72, 9.9, 0.68, fill="1C2532", line=LINE, geom="roundRect"),
            txt(1.95, 3.95, 9.4, 0.18, "管控服务层：空域规划、飞行服务、运行监控、安全监管、应急指挥、运营分析", font=9, bold=True, color=TEXT, align="c"),
            rect(2.05, 2.72, 9.2, 0.78, fill="202A38", line=YELLOW, geom="roundRect", line_w=2),
            txt(2.3, 2.98, 8.7, 0.2, "孪生底座层：三维场景、四维空域网格、动态实体、规则引擎、仿真引擎、AI 推理", font=9, bold=True, color=YELLOW, align="c"),
            rect(2.45, 2.02, 8.4, 0.48, fill="151922", line=LINE, geom="roundRect"),
            txt(2.65, 2.17, 8.0, 0.15, "数据资源层：GIS/CIM/BIM、空域规则、低空设施、主体航空器、环境与运行数据", font=8, color=MUTED, align="c"),
        ]
    ))

    slides.append(Slide(
        title="低空运行业务闭环",
        subtitle="所有功能围绕“规划-申报-审批-放行-执行-监控-处置-复盘”组织，避免平台变成只看不管的大屏。",
        section="FLOW",
        shapes=[
            rect(0.78, 2.42, 1.36, 0.7, fill="1B2430", line=YELLOW, geom="roundRect", line_w=2),
            rect(2.32, 2.42, 1.36, 0.7, fill="1B2430", line=YELLOW, geom="roundRect", line_w=2),
            rect(3.86, 2.42, 1.36, 0.7, fill="1B2430", line=YELLOW, geom="roundRect", line_w=2),
            rect(5.4, 2.42, 1.36, 0.7, fill="1B2430", line=YELLOW, geom="roundRect", line_w=2),
            rect(6.94, 2.42, 1.36, 0.7, fill="1B2430", line=YELLOW, geom="roundRect", line_w=2),
            rect(8.48, 2.42, 1.36, 0.7, fill="1B2430", line=YELLOW, geom="roundRect", line_w=2),
            rect(10.02, 2.42, 1.36, 0.7, fill="1B2430", line=YELLOW, geom="roundRect", line_w=2),
            rect(11.56, 2.42, 1.0, 0.7, fill=YELLOW, line="none", geom="roundRect"),
            txt(0.78, 2.66, 1.36, 0.2, "规划", font=14, bold=True, color=TEXT, align="c"),
            txt(2.32, 2.66, 1.36, 0.2, "申报", font=14, bold=True, color=TEXT, align="c"),
            txt(3.86, 2.66, 1.36, 0.2, "审批", font=14, bold=True, color=TEXT, align="c"),
            txt(5.4, 2.66, 1.36, 0.2, "放行", font=14, bold=True, color=TEXT, align="c"),
            txt(6.94, 2.66, 1.36, 0.2, "执行", font=14, bold=True, color=TEXT, align="c"),
            txt(8.48, 2.66, 1.36, 0.2, "监控", font=14, bold=True, color=TEXT, align="c"),
            txt(10.02, 2.66, 1.36, 0.2, "处置", font=14, bold=True, color=TEXT, align="c"),
            txt(11.56, 2.66, 1.0, 0.2, "复盘", font=14, bold=True, color=BG, align="c"),
            bullet(1.0, 3.72, 5.4, 1.15, [
                "规划成果沉淀为空域、航路、起降点、容量和规则",
                "审批授权进入动态放行和运行监控",
                "异常事件进入告警处置和应急指挥"
            ], font=11, color="CBD5E1"),
            bullet(7.0, 3.72, 5.0, 1.15, [
                "复盘结果反哺审批规则、航线设计和设施选址",
                "每个飞行计划具备全链路审计记录",
                "监管侧看安全，运营侧看效率和成本"
            ], font=11, color="CBD5E1"),
            rect(0.78, 5.55, 11.78, 0.48, fill=PANEL, line=LINE, geom="roundRect"),
            txt(1.05, 5.7, 11.2, 0.16, "闭环验收：任一飞行计划都能追溯到申请、审批、放行、航迹、告警、处置和归档记录。", font=10, bold=True, color=YELLOW),
        ]
    ))

    slides.append(Slide(
        title="系统功能蓝图",
        subtitle="功能域按 P0/P1/P2 分层建设：先闭环，再增强，最后走向智能运营和开放生态。",
        section="FUNC",
        shapes=[
            *card(0.65, 1.2, 2.35, 1.42, "P0 低空一张图", ["三维底图", "空域/航线/起降点", "实时位置"], YELLOW),
            *card(3.2, 1.2, 2.35, 1.42, "P0 飞行服务", ["计划申报", "自动风险评估", "审批协同"], YELLOW),
            *card(5.75, 1.2, 2.35, 1.42, "P0 运行监控", ["航迹接入", "偏航/越界/超高", "告警中心"], YELLOW),
            *card(8.3, 1.2, 2.35, 1.42, "P0 台账管理", ["企业/人员", "航空器", "资质/保险"], YELLOW),
            *card(10.85, 1.2, 1.8, 1.42, "P0 统计", ["架次", "审批", "告警"], YELLOW),
            *card(0.65, 3.0, 2.35, 1.42, "P1 四维空域", ["网格剖分", "容量评估", "时间预约"], CYAN),
            *card(3.2, 3.0, 2.35, 1.42, "P1 多源感知", ["雷达/光电", "5G-A 通感", "目标融合"], CYAN),
            *card(5.75, 3.0, 2.35, 1.42, "P1 应急指挥", ["临时空域", "任务优先级", "反制联动"], CYAN),
            *card(8.3, 3.0, 2.35, 1.42, "P1 仿真推演", ["航线仿真", "设施选址", "交通流"], CYAN),
            *card(10.85, 3.0, 1.8, 1.42, "P1 场景", ["应急", "巡检", "物流"], CYAN),
            *card(1.25, 4.8, 2.8, 1.22, "P2 AI 优化", ["航线优化", "容量预测", "告警降噪"], GREEN),
            *card(4.45, 4.8, 2.8, 1.22, "P2 运营结算", ["服务计费", "起降资源", "收入分析"], GREEN),
            *card(7.65, 4.8, 2.8, 1.22, "P2 开放生态", ["API/SDK", "插件应用", "跨城市模板"], GREEN),
        ]
    ))

    slides.append(Slide(
        title="四维空域与数字孪生底座",
        subtitle="核心不是建一个好看的城市模型，而是形成可计算、可调度、可审计的低空时空资源。",
        section="TWIN",
        shapes=[
            rect(0.85, 1.25, 5.2, 4.82, fill=PANEL, line=LINE, geom="roundRect"),
            *panel_title(1.15, 1.58, "四维空域表达"),
            rect(1.35, 2.22, 3.95, 0.05, fill=YELLOW, line="none"),
            rect(1.62, 2.86, 3.95, 0.05, fill=CYAN, line="none"),
            rect(1.35, 3.5, 3.95, 0.05, fill=YELLOW, line="none"),
            rect(1.62, 4.14, 3.95, 0.05, fill=CYAN, line="none"),
            rect(1.35, 4.78, 3.95, 0.05, fill=YELLOW, line="none"),
            Shape(2.15, 2.12, 0.18, 0.18, fill=YELLOW, line="none", geom="ellipse"),
            Shape(3.55, 2.76, 0.18, 0.18, fill=CYAN, line="none", geom="ellipse"),
            Shape(4.3, 3.4, 0.18, 0.18, fill=YELLOW, line="none", geom="ellipse"),
            Shape(2.75, 4.04, 0.18, 0.18, fill=CYAN, line="none", geom="ellipse"),
            txt(1.2, 5.33, 4.5, 0.22, "空间 + 高度 + 时间 + 规则", font=13, bold=True, color=YELLOW, align="c"),
            rect(6.45, 1.25, 5.95, 4.82, fill=PANEL, line=LINE, geom="roundRect"),
            *panel_title(6.75, 1.58, "底座能力清单"),
            bullet(6.75, 2.12, 5.0, 3.2, [
                "多源空间数据：地形、影像、建筑、道路、障碍物、CIM/BIM",
                "低空专题图层：禁限飞区、适飞区、临时管制区、电子围栏",
                "动态实体映射：无人机、机库、传感器、气象站、反制设备",
                "环境要素叠加：微气象、风场、能见度、电磁、通信覆盖",
                "规则与仿真引擎：冲突检测、容量评估、航线优化、回放复盘"
            ], font=11, color="CBD5E1"),
        ]
    ))

    slides.append(Slide(
        title="数据与接口体系",
        subtitle="接口能力决定平台能否从单点系统升级为低空数字基础设施。",
        section="DATA",
        shapes=[
            rect(4.3, 2.55, 4.6, 1.05, fill=YELLOW, line="none", geom="roundRect"),
            txt(4.65, 2.88, 3.9, 0.26, "低空数字孪生与运行服务平台", font=16, bold=True, color=BG, align="c"),
            *card(0.75, 1.08, 2.55, 1.35, "监管接口", ["UOM/USS", "实名登记", "飞行计划", "运行事件"], RED),
            *card(0.75, 4.15, 2.55, 1.35, "空间数据", ["GIS/CIM/BIM", "影像地形", "障碍物", "基础设施"], YELLOW),
            *card(5.0, 4.75, 2.55, 1.22, "环境数据", ["气象", "风场", "电磁", "通信覆盖"], CYAN),
            *card(9.95, 4.15, 2.55, 1.35, "设备接入", ["无人机/机库", "雷达/光电", "Remote ID", "5G-A 通感"], GREEN),
            *card(9.95, 1.08, 2.55, 1.35, "业务系统", ["应急/公安", "城管/交通", "行业工单", "支付结算"], YELLOW2),
            rect(4.45, 3.9, 4.3, 0.45, fill=PANEL, line=LINE, geom="roundRect"),
            txt(4.7, 4.04, 3.8, 0.16, "统一身份、统一时空基准、统一规则、统一审计", font=9, bold=True, color=TEXT, align="c"),
        ]
    ))

    slides.append(Slide(
        title="一期 MVP 建设范围",
        subtitle="一期不贪大，优先建立可演示、可试运行、可验收的低空运行最小闭环。",
        section="ROADMAP",
        shapes=[
            rect(0.78, 1.25, 3.65, 4.65, fill=PANEL, line=YELLOW, geom="roundRect", line_w=2),
            *panel_title(1.08, 1.58, "基础底座"),
            bullet(1.08, 2.15, 2.8, 2.7, ["低空一张图", "空域/航线/起降点", "主体与航空器台账", "基础数据导入", "无人机/机库接入"], font=12, color="CBD5E1"),
            rect(4.85, 1.25, 3.65, 4.65, fill=PANEL, line=YELLOW, geom="roundRect", line_w=2),
            *panel_title(5.15, 1.58, "业务闭环"),
            bullet(5.15, 2.15, 2.8, 2.7, ["飞行计划申报", "审批流程配置", "航线规划与风险校验", "实时航迹监控", "告警处置与复盘"], font=12, color="CBD5E1"),
            rect(8.92, 1.25, 3.35, 4.65, fill=PANEL, line=YELLOW, geom="roundRect", line_w=2),
            *panel_title(9.22, 1.58, "验收指标"),
            bullet(9.22, 2.15, 2.5, 2.7, ["计划可追溯", "审批可留痕", "航迹可回放", "越界/超高/偏航可告警", "运行统计可输出"], font=12, color="CBD5E1"),
        ]
    ))

    slides.append(Slide(
        title="二三期演进路线",
        subtitle="从最小闭环逐步演进为城市级运行服务和产业运营平台。",
        section="ROADMAP",
        shapes=[
            rect(0.75, 1.65, 3.4, 3.65, fill=PANEL, line=YELLOW, geom="roundRect", line_w=2),
            txt(1.05, 1.98, 2.75, 0.35, "一期：闭环可用", font=16, bold=True, color=YELLOW),
            bullet(1.05, 2.55, 2.7, 1.8, ["一张图", "计划申报", "审批协同", "实时监控", "告警处置"], font=12, color="CBD5E1"),
            rect(4.95, 1.65, 3.4, 3.65, fill=PANEL, line=CYAN, geom="roundRect", line_w=2),
            txt(5.25, 1.98, 2.75, 0.35, "二期：能力增强", font=16, bold=True, color=CYAN),
            bullet(5.25, 2.55, 2.7, 1.8, ["四维空域网格", "容量评估", "多源感知融合", "应急指挥", "设施选址仿真"], font=12, color="CBD5E1"),
            rect(9.15, 1.65, 3.4, 3.65, fill=PANEL, line=GREEN, geom="roundRect", line_w=2),
            txt(9.45, 1.98, 2.75, 0.35, "三期：运营生态", font=16, bold=True, color=GREEN),
            bullet(9.45, 2.55, 2.7, 1.8, ["AI 航线优化", "计费结算", "开放 API/SDK", "行业应用市场", "跨城市复制"], font=12, color="CBD5E1"),
            rect(0.75, 5.8, 11.8, 0.55, fill="111827", line=LINE, geom="roundRect"),
            txt(1.05, 5.98, 11.2, 0.18, "阶段策略：先服务监管刚需，再提高运行效率，最后形成平台运营收入和生态扩展能力。", font=10, bold=True, color=YELLOW),
        ]
    ))

    slides.append(Slide(
        title="关键指标与建设价值",
        subtitle="建议用安全、效率、运行、稳定、运营、数据六类指标衡量建设成效。",
        section="VALUE",
        shapes=[
            *metric(0.75, 1.18, "安全", "冲突预警", "越界、黑飞、事件闭环", RED),
            *metric(3.25, 1.18, "效率", "审批提速", "动态放行、航线校验", YELLOW),
            *metric(5.75, 1.18, "运行", "容量可算", "空域、航路、起降点", CYAN),
            *metric(8.25, 1.18, "稳定", "7x24", "核心运行监控高可用", GREEN),
            *metric(10.75, 1.18, "运营", "收入闭环", "服务费、起降费、场景收入", YELLOW2),
            rect(0.95, 3.0, 11.4, 2.52, fill=PANEL, line=LINE, geom="roundRect"),
            txt(1.25, 3.32, 10.8, 0.26, "从“项目验收”转向“持续运营”的指标体系", font=16, bold=True, color=TEXT, align="c"),
            rect(1.5, 4.0, 2.0, 0.16, fill=RED, line="none"),
            rect(3.75, 4.0, 2.0, 0.16, fill=YELLOW, line="none"),
            rect(6.0, 4.0, 2.0, 0.16, fill=CYAN, line="none"),
            rect(8.25, 4.0, 2.0, 0.16, fill=GREEN, line="none"),
            txt(1.2, 4.38, 2.6, 0.2, "安全可控", font=12, bold=True, color=TEXT, align="c"),
            txt(3.45, 4.38, 2.6, 0.2, "效率提升", font=12, bold=True, color=TEXT, align="c"),
            txt(5.7, 4.38, 2.6, 0.2, "资源优化", font=12, bold=True, color=TEXT, align="c"),
            txt(7.95, 4.38, 2.6, 0.2, "商业闭环", font=12, bold=True, color=TEXT, align="c"),
            rect(0.95, 5.95, 11.4, 0.48, fill="111827", line=LINE, geom="roundRect"),
            txt(1.25, 6.1, 10.8, 0.16, "最终目标：形成可持续运行的低空基础设施，而非一次性交付的信息化项目。", font=10, bold=True, color=YELLOW, align="c"),
        ]
    ))

    slides.append(Slide(
        title="风险与保障措施",
        subtitle="低空平台主要风险来自监管变化、数据质量、设备碎片化和实时工程性能。",
        section="RISK",
        shapes=[
            *card(0.65, 1.25, 2.9, 3.75, "监管接口变化", ["接口适配层", "字段映射和版本管理", "人工补录与审核兜底"], RED),
            *card(3.85, 1.25, 2.9, 3.75, "数据质量不足", ["关键区域校核", "障碍物与航线版本管理", "数据质量评分"], YELLOW2),
            *card(7.05, 1.25, 2.9, 3.75, "设备生态碎片", ["统一接入网关", "协议适配器", "设备能力画像"], CYAN),
            *card(10.25, 1.25, 2.35, 3.75, "实时性能压力", ["流式处理", "空间索引", "实时/历史拆分"], GREEN),
            rect(0.65, 5.6, 11.95, 0.55, fill="231818", line="513030", geom="roundRect"),
            txt(0.95, 5.78, 11.35, 0.18, "管理建议：验收口径围绕业务闭环和运行指标设定，避免项目滑向只看大屏效果。", font=10, bold=True, color=YELLOW),
        ]
    ))

    slides.append(Slide(
        title="下一步建议",
        subtitle="建议以一个示范区域和两类高价值场景启动，快速形成可看、可用、可验收的样板。",
        section="NEXT",
        shapes=[
            rect(0.9, 1.22, 11.55, 4.25, fill=PANEL, line=LINE, geom="roundRect"),
            Shape(1.3, 1.72, 0.34, 0.34, fill=YELLOW, line="none", geom="ellipse"),
            Shape(1.3, 2.42, 0.34, 0.34, fill=YELLOW, line="none", geom="ellipse"),
            Shape(1.3, 3.12, 0.34, 0.34, fill=YELLOW, line="none", geom="ellipse"),
            Shape(1.3, 3.82, 0.34, 0.34, fill=YELLOW, line="none", geom="ellipse"),
            Shape(1.3, 4.52, 0.34, 0.34, fill=YELLOW, line="none", geom="ellipse"),
            txt(1.82, 1.75, 10.0, 0.22, "选定示范区域：园区、景区、港口、机场周边或城市重点片区", font=13, color=TEXT),
            txt(1.82, 2.45, 10.0, 0.22, "明确一期数据清单：空域、航线、起降点、障碍物、设备、主体、航空器", font=13, color=TEXT),
            txt(1.82, 3.15, 10.0, 0.22, "选择两类场景打深：建议优先应急保障 + 城市治理/巡检", font=13, color=TEXT),
            txt(1.82, 3.85, 10.0, 0.22, "定义验收脚本：申请、审批、放行、监控、告警、复盘全链路演示", font=13, color=TEXT),
            txt(1.82, 4.55, 10.0, 0.22, "同步启动接口方案：预留 UOM/USS、无人机厂商、GIS/CIM、应急平台对接", font=13, color=TEXT),
            rect(0.9, 5.95, 11.55, 0.55, fill=YELLOW, line="none", geom="roundRect"),
            txt(1.2, 6.13, 10.95, 0.18, "建议先做“示范区 + 两场景 + 一套验收脚本”，用真实闭环证明平台价值。", font=11, bold=True, color=BG, align="c"),
        ]
    ))

    slides.append(Slide(
        title="参考资料",
        subtitle="报告与 PPT 内容基于公开资料和前述分析整理。",
        section="REF",
        shapes=[
            rect(0.85, 1.25, 11.65, 4.95, fill=PANEL, line=LINE, geom="roundRect"),
            bullet(1.18, 1.62, 10.9, 4.0, [
                "中国信通院：《低空产业高质量发展路径及其策略研究报告（2025年）》",
                "中国民航局：《无人驾驶航空器飞行管理暂行条例》及 UOM/USS 数据接口征求意见材料",
                "深城交：低空管控方案公开资料",
                "中科星图：星图低空云、低空规划平台公开资料及年报",
                "Altitude Angel、Unifly、ANRA、OneSky 官方 UTM/U-space 资料",
                "DJI Enterprise：DJI FlightHub 2 官方资料"
            ], font=12, color="CBD5E1"),
            rect(0.85, 6.42, 11.65, 0.35, fill="111827", line=LINE, geom="roundRect"),
            txt(1.15, 6.52, 11.05, 0.12, "注：正式对外汇报前，建议结合本地低空专班、监管接口和示范区数据进一步替换为本地化表述。", font=8, color=MUTED),
        ]
    ))

    return slides


def content_types(n: int) -> str:
    extra = "".join(
        f'<Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
        for i in range(1, n + 1)
    )
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
  <Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
  <Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
  <Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
  {extra}
</Types>"""


def root_rels() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>"""


def presentation(n: int) -> str:
    ids = "".join(f'<p:sldId id="{255 + i}" r:id="rId{i}"/>' for i in range(1, n + 1))
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId{n + 1}"/></p:sldMasterIdLst>
  <p:sldIdLst>{ids}</p:sldIdLst>
  <p:sldSz cx="{W}" cy="{H}" type="wide"/>
  <p:notesSz cx="6858000" cy="9144000"/>
</p:presentation>"""


def presentation_rels(n: int) -> str:
    rels = "".join(
        f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide{i}.xml"/>'
        for i in range(1, n + 1)
    )
    rels += f'<Relationship Id="rId{n + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>'
    rels += f'<Relationship Id="rId{n + 2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>'
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{rels}</Relationships>"""


def theme() -> str:
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="DarkTech">
  <a:themeElements>
    <a:clrScheme name="DarkTech">
      <a:dk1><a:srgbClr val="{BG}"/></a:dk1><a:lt1><a:srgbClr val="FFFFFF"/></a:lt1>
      <a:dk2><a:srgbClr val="{PANEL}"/></a:dk2><a:lt2><a:srgbClr val="F8FAFC"/></a:lt2>
      <a:accent1><a:srgbClr val="{YELLOW}"/></a:accent1><a:accent2><a:srgbClr val="{CYAN}"/></a:accent2>
      <a:accent3><a:srgbClr val="{GREEN}"/></a:accent3><a:accent4><a:srgbClr val="{YELLOW2}"/></a:accent4>
      <a:accent5><a:srgbClr val="{RED}"/></a:accent5><a:accent6><a:srgbClr val="8B5CF6"/></a:accent6>
      <a:hlink><a:srgbClr val="{CYAN}"/></a:hlink><a:folHlink><a:srgbClr val="{YELLOW}"/></a:folHlink>
    </a:clrScheme>
    <a:fontScheme name="YaHei"><a:majorFont><a:latin typeface="Microsoft YaHei"/><a:ea typeface="Microsoft YaHei"/></a:majorFont><a:minorFont><a:latin typeface="Microsoft YaHei"/><a:ea typeface="Microsoft YaHei"/></a:minorFont></a:fontScheme>
    <a:fmtScheme name="Clean"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme>
  </a:themeElements>
</a:theme>"""


def master() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
             xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
  <p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>
  <p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
  <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
</p:sldMaster>"""


def layout() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
             xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
             xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank">
  <p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld>
</p:sldLayout>"""


def slide_rels() -> str:
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>"""


def core() -> str:
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


def app(n: int) -> str:
    return f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"
            xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
  <Application>Codex</Application><PresentationFormat>16:9</PresentationFormat><Slides>{n}</Slides>
</Properties>"""


def write(slides: List[Slide]) -> None:
    n = len(slides)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types(n))
        z.writestr("_rels/.rels", root_rels())
        z.writestr("ppt/presentation.xml", presentation(n))
        z.writestr("ppt/_rels/presentation.xml.rels", presentation_rels(n))
        z.writestr("ppt/theme/theme1.xml", theme())
        z.writestr("ppt/slideMasters/slideMaster1.xml", master())
        z.writestr("ppt/slideMasters/_rels/slideMaster1.xml.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>""")
        z.writestr("ppt/slideLayouts/slideLayout1.xml", layout())
        z.writestr("ppt/slideLayouts/_rels/slideLayout1.xml.rels", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>""")
        z.writestr("docProps/core.xml", core())
        z.writestr("docProps/app.xml", app(n))
        for i, slide in enumerate(slides, start=1):
            z.writestr(f"ppt/slides/slide{i}.xml", slide_xml(slide, i, n))
            z.writestr(f"ppt/slides/_rels/slide{i}.xml.rels", slide_rels())


if __name__ == "__main__":
    deck = build()
    write(deck)
    print(os.path.abspath(OUT))
