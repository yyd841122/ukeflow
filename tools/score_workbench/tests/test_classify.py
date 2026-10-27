"""谱型判别缝(spec 实现决策7):纯函数,fixture 特征驱动。"""

from score_workbench.classify import CheckupSignals, LayoutSignals, classify_score


def bitmap(pages=3, tab_systems=17, notation_staves=0, text_bands=12,
           digit_bands=10, underline_bands=8):
    """谱全了式位图扫描默认信号:全覆盖、零文本层零矢量。"""
    checkup = CheckupSignals(pages=pages, text_chars=0, n_images=pages * 4,
                             image_coverage=1.0, n_drawings=0)
    layout = LayoutSignals(tab_systems=tab_systems, notation_staves=notation_staves,
                           text_bands=text_bands, digit_bands=digit_bands,
                           underline_bands=underline_bands, other_line_groups=0)
    return checkup, layout


def test_bitmap_with_tab_systems_is_solo():
    checkup, layout = bitmap(tab_systems=17)
    v = classify_score(checkup, layout)
    assert v.score_type == "solo"
    assert v.disposition == "process"
    assert any("四线谱" in r for r in v.reasons)


def vector_score():
    return (CheckupSignals(pages=2, text_chars=256, n_images=0,
                           image_coverage=0.0, n_drawings=340), None)


def test_vector_score_reported_not_processed():
    checkup, layout = vector_score()
    v = classify_score(checkup, layout)
    assert v.score_type == "vector"
    assert v.disposition == "report_only"
    assert any("只报告" in r for r in v.reasons)


def test_vector_beats_layout_signals():
    # 矢量特征与版面信号同现(低覆盖+矢量线)仍只报告——工单47:矢量谱遇到不处理
    checkup = CheckupSignals(pages=1, text_chars=0, n_images=0,
                             image_coverage=0.0, n_drawings=120)
    layout = LayoutSignals(tab_systems=3, notation_staves=0, text_bands=2,
                           digit_bands=1, underline_bands=0, other_line_groups=0)
    v = classify_score(checkup, layout)
    assert v.score_type == "vector"


def test_incidental_ocr_text_layer_still_bitmap_solo():
    # 扫描谱带 OCR 文本层:位图覆盖率优先,仍走位图路径
    checkup = CheckupSignals(pages=3, text_chars=5000, n_images=12,
                             image_coverage=1.0, n_drawings=0)
    layout = LayoutSignals(tab_systems=12, notation_staves=0, text_bands=10,
                           digit_bands=8, underline_bands=6, other_line_groups=0)
    v = classify_score(checkup, layout)
    assert v.score_type == "solo"


def test_strum_chord_jianpu_without_tab():
    checkup, layout = bitmap(tab_systems=0, text_bands=16, digit_bands=6,
                             underline_bands=4)
    v = classify_score(checkup, layout)
    assert v.score_type == "strum"
    assert v.disposition == "archive"


def test_text_bands_without_digit_evidence_is_image():
    # 纯文字/歌词图:无简谱证据不能判 strum
    checkup, layout = bitmap(tab_systems=0, text_bands=9, digit_bands=0,
                             underline_bands=0)
    v = classify_score(checkup, layout)
    assert v.score_type == "image"


def test_bitmap_without_any_structure_is_image():
    checkup, layout = bitmap(tab_systems=0, text_bands=0, digit_bands=0,
                             underline_bands=0)
    v = classify_score(checkup, layout)
    assert v.score_type == "image"
    assert v.disposition == "archive"


def test_low_coverage_blank_pdf_is_image():
    checkup = CheckupSignals(pages=1, text_chars=0, n_images=0,
                             image_coverage=0.0, n_drawings=0)
    v = classify_score(checkup, None)
    assert v.score_type == "image"


def test_bitmap_without_layout_run_is_image():
    checkup, _ = bitmap()
    v = classify_score(checkup, None)
    assert v.score_type == "image"


def test_five_line_notation_without_tab_is_image():
    # 五线谱非一期目标:认不出,归档
    checkup, layout = bitmap(tab_systems=0, notation_staves=8, text_bands=4,
                             digit_bands=0, underline_bands=0)
    v = classify_score(checkup, layout)
    assert v.score_type == "image"
    assert any("五线谱" in r for r in v.reasons)


def test_override_flips_type_and_keeps_auto():
    checkup, layout = bitmap(tab_systems=0, text_bands=0, digit_bands=0,
                             underline_bands=0)
    v = classify_score(checkup, layout, override="solo")
    assert v.score_type == "solo"
    assert v.disposition == "process"
    assert v.auto_type == "image"
    assert v.overridden is True


def test_override_agreeing_is_not_marked_overridden():
    checkup, layout = bitmap()
    v = classify_score(checkup, layout, override="solo")
    assert v.overridden is False
    assert v.auto_type == ""
