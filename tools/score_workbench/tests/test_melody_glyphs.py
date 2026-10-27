"""字形几何缝(工单49):数字行选举 + 组件角色分类 + 记号归属。

组件 = cv2 stats 五元组 (x, y, w, h, area),几何常量以弦距 g 为单位。
真机档案(工单48/49 实测,300dpi g≈19.2):数字 h≈1.3g w 0.55-0.95g;
八度点/附点 ≤0.5g;时值线/延音杠 h≈0.16g;延音弧宽 ≥2g 空心;
小节线竖段 w≈0.2g 高 ≥2.3g;歌词字 h≈1.35g 但 w ≥1.2g(窄偏旁除外,
由「最大簇」选举排除);TAB 残段污染靠 y 域闸门排。
"""

from score_workbench.melody import classify_glyphs, find_digit_band

G = 19.2


def comp(x, y, w, h, area=None):
    return (x, y, w, h, area if area is not None else w * h // 2)


def digit(x, y=100):
    return comp(x, y, 17, 25)


def test_digit_band_picks_largest_cluster_not_lyric_radicals():
    """歌词窄偏旁(h 同数字)可能成簇,但数字簇恒最大(sys01 实测 33>5)。"""
    comps = [digit(x, 100) for x in range(50, 400, 50)]           # 8 个数字
    comps += [comp(x, 200, 10, 26) for x in range(60, 180, 30)]   # 4 个歌词偏旁
    band, ambiguous = find_digit_band(comps, G)
    assert band[0] <= 100 < band[1]
    assert not ambiguous


def test_digit_band_flags_ambiguity_when_runner_up_close_and_above():
    """次簇计数逼近主簇且在其上方 → 歧证上报(证据不静默)。"""
    comps = [digit(x, 100) for x in range(50, 350, 50)]           # 6 个数字
    comps += [comp(x, 40, 11, 25) for x in range(60, 211, 30)]    # 6 个上方残段
    band, ambiguous = find_digit_band(comps, G)
    assert band[0] <= 40 < band[1] or band[0] <= 100 < band[1]
    assert ambiguous


def test_classify_roles_by_geometry():
    comps = [
        digit(50),                                  # 数字
        comp(55, 75, 7, 7),                         # 高音点(数字上方)
        comp(70, 108, 6, 7),                        # 附点(数字右中)
        comp(48, 130, 94, 3),                       # 时值线(共享梁)
        comp(160, 100, 39, 10, area=143),           # 延音弧(宽扁空心)
        comp(300, 60, 3, 48),                       # 小节线竖段
        comp(400, 100, 17, 25),                     # 数字 2
        comp(424, 110, 18, 3),                      # 延音杠(行中薄横)
        comp(500, 200, 24, 26),                     # 歌词字(过宽 → other)
    ]
    band = (95.0, 125.0)
    glyphs = classify_glyphs(comps, G, band)
    roles = {}
    for gl in glyphs:
        roles.setdefault(gl.role, []).append(gl)
    assert len(roles["digit"]) == 2
    assert len(roles["dot"]) == 2
    assert len(roles["bar"]) == 2                   # 时值线+延音杠,细分在归属层
    assert len(roles["arc"]) == 1
    assert len(roles["vertical"]) == 1
    assert len(roles["other"]) == 1                 # 歌词字


# ── 归属层:点/杠/附点挂到数字 ────────────────────────────────────────

from score_workbench.melody import attach_marks


def _notes_by_x(res):
    return {n.glyph.x: n for n in res.notes}


def test_attach_octave_dots_and_aug_by_geometry():
    """高音点 x 对齐数字心;附点在数字右中;sys01 实测几何。"""
    comps = [
        digit(50),                    # 数字(带 1 个高音点+1 个附点)
        comp(55, 75, 7, 7),           # 高音点(cx 对齐)
        comp(70, 108, 6, 7),          # 附点(右中)
        digit(150),
    ]
    glyphs = classify_glyphs(comps, G, (95.0, 125.0))
    res = attach_marks(glyphs, G)
    notes = _notes_by_x(res)
    assert len(notes) == 2
    n0 = notes[50.0]
    assert n0.above_dots == 1 and n0.aug and n0.below_dots == 0
    assert notes[150.0].above_dots == 0 and not notes[150.0].aug


def test_shared_beam_counts_for_both_notes_secondary_only_for_16ths():
    """共享主梁盖两音心 → 两音各计 1;副梁只盖十六分音 → 该音计 2(sys01)。"""
    comps = [
        digit(50),                    # 附点八分:主梁+附点
        comp(72, 112, 6, 7),          # 附点
        digit(150),                   # 十六分:主梁+副梁
        comp(48, 130, 140, 3),        # 主梁 x48-188 盖两音心
        comp(148, 138, 22, 3),        # 副梁 x148-170 只盖第二音
    ]
    glyphs = classify_glyphs(comps, G, (95.0, 125.0))
    res = attach_marks(glyphs, G)
    notes = _notes_by_x(res)
    assert notes[50.0].n_underlines == 1
    assert notes[150.0].n_underlines == 2


def test_dash_attaches_to_digit_on_its_left():
    comps = [
        digit(50),
        digit(150),
        comp(172, 105, 18, 3),        # 延音杠(数字 2 右侧,行中高度)
        comp(48, 130, 140, 3),        # 时值线(行下,不混)
    ]
    glyphs = classify_glyphs(comps, G, (95.0, 125.0))
    res = attach_marks(glyphs, G)
    notes = _notes_by_x(res)
    assert notes[50.0].n_dashes == 0
    assert notes[150.0].n_dashes == 1 and notes[150.0].n_underlines == 1
    assert notes[50.0].n_underlines == 1


def test_unattached_mid_dot_becomes_repeat_evidence_not_octave():
    """反复记号点:左于全部数字、行中高度 → marks 不吃进音符。"""
    comps = [
        comp(17, 95, 6, 6),           # 反复记号点(行中,无数字可挂)
        digit(50),
        comp(2, 90, 3, 48),           # 反复竖线
    ]
    glyphs = classify_glyphs(comps, G, (95.0, 125.0))
    res = attach_marks(glyphs, G)
    assert len(res.notes) == 1
    kinds = [m.kind for m in res.marks]
    assert 'repeat_dot' in kinds and 'vertical' in kinds
