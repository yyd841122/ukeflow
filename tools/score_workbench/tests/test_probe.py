"""探针缝(retro):组件表过滤与窗口裁剪,ASCII 步进。"""

import numpy as np

from score_workbench.probe import probe_image


def test_probe_lists_components_sorted_and_clips_window(tmp_path):
    import cv2
    img = np.full((60, 100), 255, dtype=np.uint8)
    img[10:30, 20:37] = 30          # 大块
    img[5:12, 80:87] = 30           # 窗口外(x>50)
    img[40:42, 10:60] = 30          # 薄横
    p = tmp_path / "c.png"
    cv2.imwrite(str(p), img)
    out = probe_image(str(p), x1=50)
    assert "组件 2 个" in out        # 窗口裁掉 x≥50 的块
    assert " 20   10   17   20" in out
    assert " 10   40   50    2" in out


def test_probe_missing_file_named():
    import pytest
    with pytest.raises(FileNotFoundError):
        probe_image("/nonexistent.png")


def test_probe_gray_steps_and_widths(tmp_path):
    """工单50 retro:灰度分层(亚阈结构三档字符)与行宽剖面。"""
    import cv2
    img = np.full((30, 60), 255, dtype=np.uint8)
    img[10:13, 10:20] = 60           # 深墨(≤100 → #)
    img[13:16, 10:20] = 150          # 中灰(≤180 → +)
    img[16:19, 10:20] = 200          # 亚阈(≤208 → o)
    p = tmp_path / "g.png"
    cv2.imwrite(str(p), img)
    out = probe_image(str(p), gray_steps="100,180,208")
    assert "灰度分层 100,180,208" in out
    for ch in "#+o":                 # 三档各现于字符行(60=#+150=+200=o)
        assert f"{ch}          " in out
    w_out = probe_image(str(p), widths=True)
    assert "w= 10" in w_out and "行宽剖面" in w_out
    assert "行宽剖面" in w_out
