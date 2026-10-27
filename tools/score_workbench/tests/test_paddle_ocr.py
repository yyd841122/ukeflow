"""OCR 缝(工单49):CTC 解码纯函数 + 数字格预处理;模型推理测试无模型则跳。"""

from pathlib import Path

import numpy as np
import pytest

from score_workbench.paddle_ocr import ctc_decode, digit_cell, load_chars


def test_ctc_decode_collapses_repeats_and_drops_blank():
    chars = ["", "a", "b", "c"]
    assert ctc_decode([1, 1, 1, 2, 0, 3, 3], chars) == "abc"


def test_ctc_decode_empty_and_all_blank():
    chars = ["", "a"]
    assert ctc_decode([], chars) == ""
    assert ctc_decode([0, 0, 0], chars) == ""


def test_load_chars_blank_head_and_dict_lines(tmp_path):
    d = tmp_path / "ppocrv6_dict.txt"
    d.write_text("1\n2\n\n3\n", encoding="utf-8")
    chars = load_chars(d)
    assert chars[0] == ""            # CTC blank 占 0 号
    assert chars[1:] == ["1", "2", "3"]  # 空行滤掉,索引连续


def test_digit_cell_64_white_padded_with_margin():
    img = np.full((40, 40), 255, dtype=np.uint8)
    img[10:30, 12:24] = 30            # 数字块 20×12
    cell = digit_cell(img, 12, 10, 12, 20)
    assert cell.shape == (64, 64)
    assert cell[0, 0] == 255          # 白底
    ink = cell < 200
    ys, xs = np.nonzero(ink)
    assert 4 <= ys.min() and ys.max() <= 59 and 4 <= xs.min() and xs.max() <= 59


def test_models_dir_missing_message_names_env():
    from score_workbench.paddle_ocr import resolve_models_dir
    with pytest.raises(FileNotFoundError) as ei:
        resolve_models_dir([str(Path("/nonexistent-models"))])
    assert "SWW_MODELS" in str(ei.value)
