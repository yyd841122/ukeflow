"""PP-OCR onnx 推理封装(工单49):数字格批量 rec + 整行 rec + CTC 解码。

模型=PP-OCRv6_small rec(21MB,Apache-2.0)+ ppocrv6_dict.txt,预处理照 dolce
PoC 实测口径(工单47):数字裁成白底黑字 64×64 居中格 → 48×48,归一化
(px/255-0.5)/0.5,三通道复制;CTC 逐步 argmax → 查字典(0 号=blank)。
det 模型一期不接:数字定位走连通域组件(几何规则的主场),整行 rec 只服务
页眉调号/拍号/速度行。
"""

from pathlib import Path

import cv2
import numpy as np

REC_H = 48                 # rec 输入高(dolce 实测口径)
CELL = 64                  # 数字格白底边长
CELL_PAD = 2               # 数字 bbox 外扩 px

_MODELS_FILE = "ch_PP-OCRv6_small_rec_infer.onnx"
_DICT_FILE = "ppocrv6_dict.txt"


def resolve_models_dir(candidates: list[str]) -> Path:
    """按序找模型目录(两件套齐全才算);找不到给出可操作的安装指引。"""
    for cand in candidates:
        d = Path(cand)
        if (d / _MODELS_FILE).is_file() and (d / _DICT_FILE).is_file():
            return d
    raise FileNotFoundError(
        f"找不到 PP-OCR 模型({_MODELS_FILE} + {_DICT_FILE}),"
        f"找过:{candidates}。获取:设 SWW_MODELS 指向含两件的目录,"
        "或从 dolce 仓 public/redist/ocr/ 拷入 tools/score_workbench/models/"
        "(README 有步骤)")


def load_chars(dict_path: Path) -> list[str]:
    """字典 → CTC 字符表:0 号=blank,其后按文件行序(空行滤除防索引漂移)。"""
    lines = [ln for ln in dict_path.read_text(encoding="utf-8").splitlines() if ln]
    return ["", *lines]


def ctc_decode(argmax: list[int], chars: list[str]) -> str:
    """CTC 贪心解码:相邻重复折叠,blank(0)丢弃。"""
    out = []
    prev = -1
    for idx in argmax:
        if idx != prev and idx != 0:
            out.append(chars[idx])
        prev = idx
    return "".join(out)


def digit_cell(img: np.ndarray, x: int, y: int, w: int, h: int) -> np.ndarray:
    """数字 bbox(带外扩)贴到 64×64 白底居中格(黑字白底,rec 口径)。"""
    y0, y1 = max(0, y - CELL_PAD), min(img.shape[0], y + h + CELL_PAD)
    x0, x1 = max(0, x - CELL_PAD), min(img.shape[1], x + w + CELL_PAD)
    g = img[y0:y1, x0:x1]
    cell = np.full((CELL, CELL), 255, dtype=np.uint8)
    scale = min((CELL - 2 * CELL_PAD) / g.shape[0], (CELL - 2 * CELL_PAD) / g.shape[1])
    gw, gh = max(1, int(g.shape[1] * scale)), max(1, int(g.shape[0] * scale))
    resized = cv2.resize(g, (gw, gh), interpolation=cv2.INTER_AREA)
    oy, ox = (CELL - gh) // 2, (CELL - gw) // 2
    cell[oy:oy + gh, ox:ox + gw] = resized
    return cell


# ── 模型推理(真机路径;无模型时 resolve 给出安装指引)──────────────────

DEFAULT_MODEL_DIRS = (
    "$SWW_MODELS",               # 环境变量优先
    str(Path(__file__).resolve().parent.parent / "models"),
    "/tmp/dolce/public/redist/ocr",   # 工单47 PoC  checkout(PoC 机)
)


class DigitOCR:
    """PP-OCRv6_small rec 封装:数字格批量推理 + 整行 rec(页眉)。

    字典在首次推理时按输出维度对齐(实测 dict 18708 行、输出 18710 类,
    尾部多出的类补 '?' 占位,防 CTC 索引越界——越界即静默丢,违反
    ADR-0009,宁可占位显形)。
    """

    def __init__(self, models_dir: str | None = None):
        import onnxruntime as ort

        cands = [models_dir] if models_dir else list(DEFAULT_MODEL_DIRS)
        cands = [c for c in cands if c and not c.startswith("$")]
        d = resolve_models_dir(cands)
        self.models_dir = d
        self._sess = ort.InferenceSession(
            str(d / _MODELS_FILE), providers=["CPUExecutionProvider"])
        self._chars = load_chars(d / _DICT_FILE)

    def _run(self, chw: np.ndarray) -> np.ndarray:
        out = self._sess.run(None, {self._sess.get_inputs()[0].name: chw})[0]
        if out.shape[-1] > len(self._chars):
            self._chars = self._chars + ["?"] * (out.shape[-1] - len(self._chars))
        return out

    @staticmethod
    def _chw(cells: list[np.ndarray]) -> np.ndarray:
        n = len(cells)
        chw = np.zeros((n, 3, REC_H, REC_H), dtype=np.float32)
        for i, c in enumerate(cells):
            r = cv2.resize(c, (REC_H, REC_H), interpolation=cv2.INTER_AREA)
            v = (r.astype(np.float32) / 255.0 - 0.5) / 0.5
            for ch in range(3):
                chw[i, ch] = v
        return chw

    def digit_labels(self, img: np.ndarray, digits) -> list:
        """数字格批量 rec → [(首字符, 置信度)]。空文本给 ('', 0)。"""
        if not digits:
            return []
        cells = [digit_cell(img, int(g.x), int(g.y), int(g.w), int(g.h))
                 for g in digits]
        out = self._run(self._chw(cells))
        labels = []
        for row in out:
            argmax = np.clip(row.argmax(axis=1), 0, len(self._chars) - 1)
            conf = float(row.max(axis=1).mean())
            text = ctc_decode([int(i) for i in argmax], self._chars).strip()
            labels.append((text[:1], conf))
        return labels

    def line_text(self, strip: np.ndarray) -> str:
        """整行文本 rec(页眉调号/速度行):等比缩到 h=48,零填充到 ≥320。"""
        h = strip.shape[0]
        if h <= 0 or strip.shape[1] <= 0:
            return ""
        w = max(1, int(REC_H * strip.shape[1] / h))
        r = cv2.resize(strip, (w, REC_H), interpolation=cv2.INTER_AREA)
        tw = min(2048, max(320, w))
        if w > tw:               # 超长行(段落标注带)截头,行 rec 只服务页眉
            r = r[:, :tw]
        chw = np.zeros((1, 3, REC_H, tw), dtype=np.float32)
        v = (r.astype(np.float32) / 255.0 - 0.5) / 0.5
        for ch in range(3):
            chw[0, ch, :, :w] = v
        out = self._run(chw)
        argmax = np.clip(out[0].argmax(axis=1), 0, len(self._chars) - 1)
        return ctc_decode([int(i) for i in argmax], self._chars)
