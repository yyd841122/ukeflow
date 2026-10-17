#!/usr/bin/env python3
"""把内置 ChordPro 谱排版成「图片谱」示例资产(工单 18)。

用途:assets/image_charts/ 下的内置图片谱是真实曲谱内容(与文本谱同源),
让「图片谱·只读」开箱有东西可看、可缩放。重生成:python3 本脚本。

排版:和弦/歌词行用等宽字体(和弦列对齐歌词字符位),标题/段落标签用
CJK 字体(文泉驿正黑,WSL 自带;歌词本身是 ASCII,等宽网格无缺字)。
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

SOURCE = Path("assets/charts/big-big-world.pro")
TARGET = Path("assets/image_charts/big-big-world.png")

MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
CJK = "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"

BG = (250, 250, 248)
INK = (28, 28, 30)
MUTED = (110, 110, 115)
ACCENT = (150, 60, 40)

MONO_SIZE = 30
TITLE_SIZE = 52
LABEL_SIZE = 30
PAD = 72
LINE_GAP = 22
SECTION_GAP = 34
MIN_CHORD_GAP = 2  # 相邻和弦名至少空开的等宽格数


def parse(source: str):
    """极简 ChordPro 读取:标题/歌手/注释/段落标签/[和弦]歌词行。"""
    doc = {"title": "", "artist": "", "comment": "", "sections": []}
    section = None
    for raw in source.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("{title:"):
            doc["title"] = line.split(":", 1)[1].rstrip("}").strip()
        elif line.startswith("{artist:"):
            doc["artist"] = line.split(":", 1)[1].rstrip("}").strip()
        elif line.startswith("{c:"):
            doc["comment"] = line.split(":", 1)[1].rstrip("}").strip()
        elif line.startswith("{start_of_"):
            label = line.split(":", 1)[1].rstrip("}").strip()
            section = {"label": label, "lines": []}
            doc["sections"].append(section)
        elif line.startswith("{end_of_"):
            section = None
        elif "[" in line:
            # [C]歌词 → (和弦, 歌词字符位置) 列表 + 纯歌词
            chords, lyric, i = [], [], 0
            while line:
                if line.startswith("["):
                    name = line[1 : line.index("]")]
                    chords.append((name, i))
                    line = line[line.index("]") + 1 :]
                else:
                    # 「Miss you much [Am]」式句中和弦落在词尾之后一格
                    head = line.split("[", 1)[0]
                    if head == "":  # 连续和弦,如 [Am][Dm]
                        chords.append(("", i))
                        line = line[line.index("]") + 1 :]
                        chords.append((line[1 : line.index("]")], i))
                        line = line[line.index("]") + 1 :]
                        continue
                    lyric.append(head)
                    i += len(head)
                    line = line[len(head) :]
            section["lines"].append((chords, "".join(lyric)))
    return doc


def render(doc) -> Image.Image:
    mono = ImageFont.truetype(MONO, MONO_SIZE)
    title_font = ImageFont.truetype(CJK, TITLE_SIZE)
    label_font = ImageFont.truetype(CJK, LABEL_SIZE)
    probe = Image.new("RGB", (8, 8))
    probe_draw = ImageDraw.Draw(probe)
    cell = probe_draw.textlength("M", font=mono)

    def chord_row(chords, lyric):
        slots = [" "] * (len(lyric) + 12)
        cursor = 0
        for name, pos in chords:
            start = max(pos, cursor + MIN_CHORD_GAP)
            slots[start : start + len(name)] = name
            cursor = start + len(name)
        return "".join(slots).rstrip()

    blocks = []  # (kind, text)
    blocks.append(("title", doc["title"]))
    blocks.append(("artist", doc["artist"]))
    if doc["comment"]:
        blocks.append(("comment", "· " + doc["comment"]))
    for section in doc["sections"]:
        blocks.append(("label", section["label"]))
        for chords, lyric in section["lines"]:
            blocks.append(("chords", chord_row(chords, lyric)))
            blocks.append(("lyric", lyric))

    width = 0
    for kind, text in blocks:
        # 测量与绘制必须同字体:comment/artist 用 CJK 绘制,也得用
        # CJK 测宽,不然中文行右缘被裁。
        font = {
            "title": title_font,
            "label": label_font,
            "artist": label_font,
            "comment": label_font,
        }.get(kind, mono)
        width = max(width, probe_draw.textlength(text, font=font))
    width = int(width) + PAD * 2

    def line_h(kind):
        if kind == "title":
            return TITLE_SIZE + 18
        if kind == "label":
            return LABEL_SIZE + SECTION_GAP
        return MONO_SIZE + LINE_GAP

    height = PAD * 2 + sum(line_h(k) for k, _ in blocks)
    img = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(img)
    y = PAD
    for kind, text in blocks:
        if kind == "title":
            draw.text((PAD, y), text, font=title_font, fill=INK)
        elif kind == "artist":
            draw.text((PAD, y), text, font=label_font, fill=MUTED)
        elif kind == "comment":
            draw.text((PAD, y), text, font=label_font, fill=MUTED)
        elif kind == "label":
            draw.text((PAD, y), text, font=label_font, fill=ACCENT)
        else:
            draw.text((PAD, y), text, font=mono, fill=INK)
        y += line_h(kind)
    return img


def main():
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    doc = parse(SOURCE.read_text(encoding="utf-8"))
    assert doc["title"] and doc["sections"], "解析结果异常"
    img = render(doc)
    img.save(TARGET)
    print(f"{TARGET} {img.size[0]}x{img.size[1]}")


if __name__ == "__main__":
    main()
