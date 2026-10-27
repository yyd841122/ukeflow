"""谱型判别缝(spec 实现决策7):信号 → (谱型+理由) 纯函数。

启发式优先级(工单47/ADR-0009):
  1. 体检判矢量 → vector:只报告不处理;
  2. 位图路径:检出四线谱系统 → solo;
  3. 无 TAB 而有文本带+简谱证据 → strum;
  4. 其余 → image(认不出,归档待识别)。
误判可手改(override 只翻类型,自动判定保留在 auto_type)。
"""

from dataclasses import dataclass

# 体检阈值
# BITMAP_COVERAGE_MIN:0.5 无档案实测依据,谱全了语料实测=1.0(每页 4 条全宽
# 位图带);「多页谱仅部分页扫描」的页均边界未测,工单48/51 前按新语料校准。
BITMAP_COVERAGE_MIN = 0.5   # 嵌入位图覆盖页均 ≥ 此值 → 位图扫描谱
VECTOR_TEXT_MIN = 100       # 非位图时:可提取文本 ≥ 此字符 → 矢量谱证据
VECTOR_DRAWINGS_MIN = 20    # 非位图时:矢量绘图指令 ≥ 此数 → 矢量谱证据

SCORE_TYPES = ("solo", "strum", "image", "vector")
# 分流去向:solo 走完整识谱管线;strum/image 归档图片谱待识别;vector 只报告
DISPOSITIONS = {"solo": "process", "strum": "archive", "image": "archive",
                "vector": "report_only"}


@dataclass(frozen=True)
class CheckupSignals:
    """体检信号(PDF 对象层,checkup_pdf 产出)。"""

    pages: int
    text_chars: int        # 可提取文本字符数(去空白)
    n_images: int          # 嵌入位图对象数
    image_coverage: float  # 位图覆盖率(页均,0..1)
    n_drawings: int        # 矢量绘图指令数


@dataclass(frozen=True)
class LayoutSignals:
    """版面信号(位图路径,extract_layout 产出)。"""

    tab_systems: int        # 四线谱系统组数(源 PDF 检出的谱表组;与 GLOSSARY
                            # 「谱表系统」=谱面视图排版单元同词不同概念)
    notation_staves: int    # 五线谱谱表组数(非一期目标)
    text_bands: int         # 文本带数(和弦名/歌词候选)
    digit_bands: int        # 数字带数(简谱候选)
    underline_bands: int    # 带短横时值线的数字带数(简谱判定关键)
    other_line_groups: int  # 非 4/5 线的长横线组数(诊断信号,判别不消费;
                            # 工单48 版面切分可用)


@dataclass(frozen=True)
class ScoreTypeVerdict:
    score_type: str         # solo | strum | image | vector
    disposition: str        # process | archive | report_only
    reasons: tuple          # 人话理由,引用信号实数
    auto_type: str = ""     # override 前的自动判定
    overridden: bool = False


def is_bitmap(checkup: CheckupSignals) -> bool:
    return checkup.image_coverage >= BITMAP_COVERAGE_MIN


def is_vector_score(checkup: CheckupSignals) -> bool:
    if is_bitmap(checkup):
        return False  # 位图扫描谱即使带 OCR 文本层也走位图路径
    return (checkup.n_drawings >= VECTOR_DRAWINGS_MIN
            or checkup.text_chars >= VECTOR_TEXT_MIN)
    # 边界决策(2026-10-27 评审立):born-digital 弹唱谱(真文本简谱、位图
    # 覆盖率<0.5)现落 vector 只报告,不判 strum——一期输入=谱全了位图谱,
    # born-digital 源未在语料;工单48/51 前若要接,须在 bitmap/vector 之间
    # 加「矢量文本谱」分支。


def checkup_kind(checkup: CheckupSignals) -> str:
    """体检信号的一句人话判读(优先级与 classify_score 同源,供 CLI)。"""
    if is_vector_score(checkup):
        return "矢量谱特征:只报告不处理"
    if is_bitmap(checkup):
        return "位图扫描谱(可走版面判别)"
    return "信号不足(既非位图也无矢量特征)"


def classify_score(checkup: CheckupSignals, layout: LayoutSignals | None,
                   override: str | None = None) -> ScoreTypeVerdict:
    auto = _classify_auto(checkup, layout)
    if override is not None and override != auto.score_type:
        return ScoreTypeVerdict(
            score_type=override, disposition=DISPOSITIONS[override],
            reasons=(f"人工改判 {override}(自动判 {auto.score_type})",) + auto.reasons,
            auto_type=auto.score_type, overridden=True)
    return auto


def _classify_auto(checkup: CheckupSignals, layout: LayoutSignals | None) -> ScoreTypeVerdict:
    if is_vector_score(checkup):
        return ScoreTypeVerdict(
            score_type="vector", disposition=DISPOSITIONS["vector"],
            reasons=(f"矢量谱特征(文本 {checkup.text_chars} 字符/绘图 "
                     f"{checkup.n_drawings} 条):只报告不处理",))
    if not is_bitmap(checkup):
        return ScoreTypeVerdict(
            score_type="image", disposition=DISPOSITIONS["image"],
            reasons=(f"既非位图扫描(覆盖率 {checkup.image_coverage:.2f})"
                     f"也无矢量特征,认不出",))
    # 位图路径:版面信号判型
    if layout is None:
        return ScoreTypeVerdict(
            score_type="image", disposition=DISPOSITIONS["image"],
            reasons=("位图但未取版面信号,认不出",))
    if layout.tab_systems >= 1:
        return ScoreTypeVerdict(
            score_type="solo", disposition=DISPOSITIONS["solo"],
            reasons=(f"检出 {layout.tab_systems} 组四线谱系统 → 独奏谱",))
    if (layout.text_bands >= 1
            and (layout.underline_bands >= 1 or layout.digit_bands >= 1)):
        return ScoreTypeVerdict(
            score_type="strum", disposition=DISPOSITIONS["strum"],
            reasons=(f"无 TAB,检出文本带 {layout.text_bands} 条+简谱证据"
                     f"(数字带 {layout.digit_bands}/时值线带 {layout.underline_bands})"
                     f"→ 弹唱谱",))
    if layout.notation_staves >= 1:
        return ScoreTypeVerdict(
            score_type="image", disposition=DISPOSITIONS["image"],
            reasons=(f"只检出 {layout.notation_staves} 组五线谱谱表:"
                     f"五线谱非一期目标,归档待识别",))
    return ScoreTypeVerdict(
        score_type="image", disposition=DISPOSITIONS["image"],
        reasons=("位图但未见四线谱系统/简谱证据,认不出",))
