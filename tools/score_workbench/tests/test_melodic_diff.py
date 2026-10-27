"""真值 diff 缝(工单49):草稿×168 音逐位对照。

配对:truth 22 个 4 拍小节 ↔ 草稿小节按读出长度贪心凑 4(印张 2/4 变拍两小节
并成一块,sys05 实测 2+2);逐位比 度数+八度点(印张约定=应用点数+1)/块内
拍位/时值(休止感知:音后接休止时按「至下音的累计」对真值 gap)。闭合不对
的块跳过时值比对(长度底座不成立),照常比度数。
"""

from score_workbench.melodic_diff import diff_melody, truth_to_print_pitch


def draft_measure(idx, start, notes, rests=(), read=None, closure=True):
    return {"index": idx, "start_beat": start,
            "read_beats": read if read is not None else 4.0,
            "closure_ok": closure, "notes": notes, "rests": list(rests),
            "warnings": []}


def dnote(degree, beat, dur, above=1):
    return {"degree": degree, "octave_dots_above": above,
            "octave_dots_below": 0, "beat": beat, "duration": dur,
            "confidence": 1.0}


def test_truth_midi_maps_to_degree_and_print_dots():
    # G4=67 → 5,印张 1 点(5');E5=76 → 3,印张 2 点(3'')
    assert truth_to_print_pitch(67) == (5, 1)
    assert truth_to_print_pitch(76) == (3, 2)
    assert truth_to_print_pitch(60) == (1, 1)      # C4


def test_perfect_draft_diffs_clean():
    # 两块:一块 4 拍单小节,一块 2+2 两小节并(变拍)
    draft = {"measures": [
        draft_measure(5, 20.0, [dnote(5, 20.0, 1.0), dnote(6, 21.0, 1.0),
                                dnote(7, 22.0, 1.0), dnote(1, 23.0, 1.0, above=2)]),
        draft_measure(6, 24.0, [dnote(2, 24.0, 1.0), dnote(3, 25.0, 1.0)],
                      read=2.0),
        draft_measure(7, 26.0, [dnote(4, 26.0, 1.0), dnote(5, 27.0, 1.0)],
                      read=2.0),
    ]}
    truth = {"notes": [
        {"beat": 0.0, "midi": 67}, {"beat": 1.0, "midi": 69},
        {"beat": 2.0, "midi": 71}, {"beat": 3.0, "midi": 72},
        # 真值按连拍格:第 2 个 4 拍小节跨印张两小节
        {"beat": 4.0, "midi": 62}, {"beat": 5.0, "midi": 64},
        {"beat": 6.0, "midi": 65}, {"beat": 7.0, "midi": 67},
    ]}
    report = diff_melody(draft, truth, start_measure=5, chunk_beats=4.0)
    assert report["summary"]["degree_bad"] == 0
    assert report["summary"]["beat_bad"] == 0
    assert len(report["chunks"]) == 2
    assert report["chunks"][1]["draft_measures"] == [6, 7]   # 2+2 并块


def test_degree_and_beat_mismatch_located():
    draft = {"measures": [
        draft_measure(0, 0.0, [dnote(5, 0.0, 1.0), dnote(3, 1.0, 1.0),
                               dnote(7, 2.0, 1.0), dnote(1, 3.0, 1.0)]),
    ]}
    truth = {"notes": [{"beat": 0.0, "midi": 67}, {"beat": 1.0, "midi": 69},
                       {"beat": 2.0, "midi": 71}, {"beat": 3.0, "midi": 72}]}
    report = diff_melody(draft, truth, start_measure=0, chunk_beats=4.0)
    fields = {(m["field"], m["i"]) for m in report["chunks"][0]["mismatches"]}
    assert ("degree", 1) in fields          # 草稿 3 vs 真值 6(A4)
    assert report["summary"]["degree_bad"] == 1


def test_rest_aware_duration_comparison():
    # 印张:八分音+八分休止+十六分对;真值 gap 0.5/1.0/0.25(休止计入)
    draft = {"measures": [
        draft_measure(0, 0.0,
                      [dnote(5, 0.0, 0.5), dnote(3, 1.0, 0.25),
                       dnote(3, 1.25, 0.25)],
                      rests=[{"beat": 0.5, "beats": 0.5, "x": 90}]),
    ]}
    truth = {"notes": [{"beat": 0.0, "midi": 67}, {"beat": 1.0, "midi": 64},
                       {"beat": 1.25, "midi": 64}]}
    report = diff_melody(draft, truth, start_measure=0, chunk_beats=4.0)
    assert report["summary"]["duration_bad"] == 0


def test_unclosed_chunk_skips_duration_but_keeps_degree():
    draft = {"measures": [
        draft_measure(0, 0.0, [dnote(5, 0.0, 1.0), dnote(6, 1.0, 1.0)],
                      read=2.0, closure=False),
    ]}
    truth = {"notes": [{"beat": 0.0, "midi": 67}, {"beat": 1.0, "midi": 69}]}
    report = diff_melody(draft, truth, start_measure=0, chunk_beats=4.0)
    assert report["chunks"][0]["duration_compared"] == 0
    assert report["summary"]["degree_bad"] == 0
