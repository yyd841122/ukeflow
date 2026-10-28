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
