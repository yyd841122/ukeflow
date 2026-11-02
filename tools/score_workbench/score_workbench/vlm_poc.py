"""工单57:VLM 直读 TAB POC 抓手(DeepSeek vision,ADR-0010 主线)。

输入 = 印张位图(整谱页原生位图拼装,或含完整节奏带的系统条带),输出 =
ukeflow.eval.candidate/1 候选草稿,交 eval-joint 评分。票面纪律:key 只从
环境变量 DEEPSEEK_API_KEY 注入;原始响应/候选/账本一律落 --out-dir(仓库外,
不入库不入 git);提示词冻结于 PROMPT(定版后批量禁改,防单张过拟合)。

管线(vlm-run → vlm-assemble):
1. run:调用→存原始响应(raw/)→ extract_json+normalize(拍位/时值入
   Fraction,tech 别名收拢;muted 不入码——真值侧 muted 是和弦 -1 弦推导
   产物,两侧都不进符号层计分,见工单56 eval_build._muted_for)→ 候选落盘
   (cand/,未过筛全时值轴,留诊断)→ 账本记账;
2. assemble:多单元合并 → scope_filter 只留已裁定拍段(0-36 + 80-108)→
   按 eval_build.SEGMENTS 标段 → 落整表候选(列带 unit 出处,便于定位)。

duration 语义:normalize 重算 = 至下一 attack(连音列除外)或休止的持续
窗,封顶 MAIN_AXIS_BEATS——与真值同规(eval_build 时值段);模型读错的
列照常被计入,只消「印刷时值 vs 持续窗」的口径差;原值留 printed_duration。

成本:usage 按官方价表折算(见 PRICE_USD_PER_M 注),峰谷按 UTC 判;预算
护栏 = 账本累计 + --budget-cny 上限告警(票面首轮硬上限 ¥20)。
"""

import base64
import datetime as dt
import hashlib
import json
import os
import time
import urllib.error
import urllib.request
from fractions import Fraction

from PIL import Image

from .eval_build import MAIN_AXIS_BEATS, SEGMENTS
from .eval_expand import rat

MODEL_DEFAULT = "deepseek-v4-flash-vision-exp"   # ADR-0010 指定;已退役名,
# 官方路由到 deepseek-flash(V4.1-Flash-1017),账单按 Flash 价——报告里注明。
API_URL = "https://api.deepseek.com/chat/completions"
PROMPT_VERSION = "57-v1"
MAX_TOKENS = 65536
TEMPERATURE = 0
# 路由模型 deepseek-flash 默认思考 effort=high——首轮实测 16k completion 全
# 烧在 reasoning_content、final content 为空(finish=length)。冻结配置 =
# 思考开 + effort=low(保逐步读谱,封成本/时长);2026-11-02 官方文档:
# thinking {type: enabled/disabled},effort ∈ low/high/max,输出上限 384K。
THINKING = {"type": "enabled"}
REASONING_EFFORT = "low"
CNY_PER_USD = 7.1          # 近似汇率,成本清单注明口径
BUDGET_CNY_DEFAULT = 20.0  # 票面首轮 API 硬上限

# 官方价表 USD/1M tokens(2026-11-02 api-docs.deepseek.com/quick_start/pricing,
# deepseek-flash 栏;峰时=UTC 周一~五 01-04/06-10 时,谷时为半)。
PRICE_USD_PER_M = {
    ("input_cache_miss", False): 0.15,
    ("input_cache_miss", True): 0.30,
    ("input_cache_hit", False): 0.003,
    ("input_cache_hit", True): 0.006,
    ("output", False): 0.60,
    ("output", True): 1.20,
}

# 印张位图拼装/裁块的几何换算(300dpi 渲染 ↔ 原生 993×1404 位图拼装)。
NATIVE_PAGE_W = 1986
RENDER_PAGE_W = 2480.3336       # 595.28pt × 300/72
SCALE_RENDER_TO_NATIVE = NATIVE_PAGE_W / RENDER_PAGE_W
RENDER_HALF_H = 1753.9668       # 3507.93 / 2
PDF_HALF_PT = 420.9             # PDF 页高 841.89pt 之半(位图摆放上下半界)
CROP_PAD_NATIVE = 25            # 裁块上下留白,防切符杆/段落标注

SCOPE_RANGES = ((Fraction(0), Fraction(36)), (Fraction(80), Fraction(108)))

PROMPT = """你是有谱面校对经验的识谱员。任务是逐符号读取一张尤克里里「四线谱(TAB)」印张图片,输出严格的 JSON。只报告图片上真实印刷的记号,不做任何音乐推理或补全。

【输入形态】图片可能是完整一页谱,也可能是单个谱表系统的横条。版式自上而下:和弦图与和弦名 / 四线谱 TAB / 节奏符杆(向下伸出谱底)/ 简谱与歌词行。简谱行的数字属于人声旋律,不是四线谱音位,不要读进 TAB。反复记号、段落标注(如「副歌」「间奏」)不进输出,照常逐小节读取。

【四线谱约定】四条横线自上而下 = ①②③④弦(①=顶线);T-A-B 字头与拍号(如 4/4)在谱表左侧。
- 音位数字:压在某条线上的阿拉伯数字 = 该弦该品;0 = 空弦。
- × 记号:压在某条线上的 × = 拨响该弦(品位来自当前和弦,你不必推导);同一竖直位置的多个 × 纵向成堆 = 同时拨多弦。
- 同一竖直位置(同一拍)的所有数字与 × 输出为同一列(columns 的一项),每个记号是 marks 的一项。

【节奏系统】音位记号向下伸出细符杆;符杆间的横杠(符杠)层数决定时值:1 条 = 八分音符 0.5 拍,2 条 = 十六分音符 0.25 拍;符杆末端斜旗 = 八分音符 0.5 拍;符杆后小圆点 = 附点(该音时值 ×1.5);无符杆的长音按时值延线或延续到下一列估计。
- 休止写 rests 不写 columns:八分休止 = 实心点带右下尾旗的小符号;全小节休止 = 挂在小节开头谱线下的粗短横块。
- 同弦同品两音之间的弧线 = 延音线:后一位置无新音,不输出它的列,只输出 ties 一条 {"from_beat":前音拍位,"to_beat":后音拍位};延音链逐弧拆条。
- × 堆上方的弧线 = 连音×柱:该列 "tie":true,marks 照读,它不发声不占时值。
- 数字外的空心椭圆(长音)= 该音延续,无新音;罩住四线的高瘦空心椭圆 = 震音:该列 "tech":"tremolo",内部 × 照读进 marks。
- 竖波浪线 = 卷弦:该列 "tech":"roll";旁边如有独立的 × 或数字,照读进 marks。
- 长竖线带箭头 = 扫弦:箭头向上 "tech":"strumUp",向下 "tech":"strumDown";箭头列通常无 marks。
- 两音之间的斜杠 = 滑音:输出 slides 一条 {"from_beat":前音拍位,"to_beat":后音拍位}。

【拍位计算】4/4 拍:第 n 小节起始拍 = (n−1)×4,第 1 小节从拍 0 开始。每个小节上方的灰色小字(如 18)是小节号,是拍位锚定的依据。列的 beat = 小节起始拍 + 该小节内排在它之前的所有列与休止的时值总和。全部用小数(如 13.25)。

【输出:只输出一个 JSON 对象,不要任何解释文字】
{"schema":"ukeflow.eval.candidate/1",
 "columns":[
  {"beat":4.0,"duration":0.5,"marks":[{"string":1,"kind":"digit","fret":2},{"string":2,"kind":"x"}]},
  {"beat":4.5,"duration":0.5,"tech":"roll"},
  {"beat":12.0,"duration":1.0,"marks":[{"string":4,"kind":"x"},{"string":3,"kind":"x"},{"string":2,"kind":"x"},{"string":1,"kind":"x"}],"tech":"tremolo"},
  {"beat":14.0,"duration":0.5,"marks":[{"string":3,"kind":"x"},{"string":2,"kind":"x"}],"tie":true}
 ],
 "rests":[{"beat":0.0,"beats":4.0}],
 "ties":[],"slides":[]}

字段约定:marks[].string = 1..4 整数(①=1=顶线),kind 只能是 "digit"(必须带整数 fret)或 "x";读不清的记号照位置输出且 kind 填 "unknown";tech 只能是 "roll"/"strumUp"/"strumDown"/"tremolo" 或省略;"tie":true 只用于连音×柱列;duration = 按符杠读出的印刷时值(拍,小数);rests[].beats = 印刷休止时值。

【纪律】
- 只输出印刷记号;不要因「这里应该是什么和弦」增删任何东西。
- 宁可存疑(unknown)不可遗漏:每一个印刷记号都必须落在输出里。"""

TECH_ALIASES = {
    "roll": "roll", "tremolo": "tremolo",
    "strumup": "strumUp", "strum_up": "strumUp", "up": "strumUp",
    "strumdown": "strumDown", "strum_down": "strumDown", "down": "strumDown",
}


# ── 提示词与载荷 ────────────────────────────────────────────

def image_data_url(path) -> str:
    with open(path, "rb") as fh:
        return "data:image/png;base64," + base64.b64encode(fh.read()).decode()


def build_payload(image_path, prompt=PROMPT, model=MODEL_DEFAULT) -> dict:
    """一次调用的请求体(温度/上限/JSON 模式全冻结)。"""
    return {
        "model": model,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image_url",
                 "image_url": {"url": image_data_url(image_path)}},
                {"type": "text", "text": prompt},
            ],
        }],
        "temperature": TEMPERATURE,
        "max_tokens": MAX_TOKENS,
        "thinking": THINKING,
        "reasoning_effort": REASONING_EFFORT,
        "response_format": {"type": "json_object"},
        "stream": False,
    }


# ── 调用与成本 ──────────────────────────────────────────────

def require_key() -> str:
    key = os.environ.get("DEEPSEEK_API_KEY")
    if not key:
        raise RuntimeError("缺 DEEPSEEK_API_KEY 环境变量(票面:key 经环境注入,不入库)")
    return key


def call_model(payload, transport=None, timeout=600):
    """POST chat/completions,返回响应 dict。transport 仅供测试注入。"""
    if transport is None:
        def transport(pl):
            req = urllib.request.Request(
                API_URL,
                data=json.dumps(pl).encode("utf-8"),
                headers={"Content-Type": "application/json",
                         "Authorization": f"Bearer {require_key()}"},
                method="POST")
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
    try:
        return transport(payload)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        # json_object 不被接受 → 同载荷去该字段重试一次(管线兜底,非提示词变更)
        if exc.code == 400 and "response_format" in body:
            fallback = {k: v for k, v in payload.items()
                        if k != "response_format"}
            return transport(fallback)
        raise RuntimeError(f"API {exc.code}: {body[:300]}") from exc


def is_peak(ts: float) -> bool:
    """峰时 = UTC 周一~五 01-04 / 06-10 时(官方规则)。"""
    t = dt.datetime.fromtimestamp(ts, tz=dt.timezone.utc)
    if t.weekday() >= 5:
        return False
    return 1 <= t.hour < 4 or 6 <= t.hour < 10


def call_cost_usd(usage: dict | None, peak: bool) -> float | None:
    """官方价表折算;usage 缺失返回 None(不臆造)。"""
    if not usage:
        return None
    n_hit = usage.get("prompt_cache_hit_tokens", 0)
    n_miss = max(0, usage.get("prompt_cache_miss_tokens",
                              usage.get("prompt_tokens", 0) - n_hit))
    n_out = usage.get("completion_tokens", 0)
    return (n_miss * PRICE_USD_PER_M[("input_cache_miss", peak)]
            + n_hit * PRICE_USD_PER_M[("input_cache_hit", peak)]
            + n_out * PRICE_USD_PER_M[("output", peak)]) / 1e6


# ── 响应 → 候选草稿 ─────────────────────────────────────────

def extract_json(text: str) -> dict:
    """剥包装取 JSON(容忍代码围栏/前后杂文);失败带原文片段报错。"""
    lo = text.find("{")
    hi = text.rfind("}")
    if lo < 0 or hi <= lo:
        raise ValueError(f"响应里没有 JSON 对象:{text[:200]!r}")
    try:
        return json.loads(text[lo:hi + 1])
    except json.JSONDecodeError as exc:
        raise ValueError(f"JSON 解析失败({exc}):{text[lo:lo + 200]!r}") from exc


def _norm_mark(m, warns, at):
    if not isinstance(m, dict):
        warns.append(f"@{at}: 记号非对象 {m!r},丢弃")
        return None
    s = m.get("string")
    if isinstance(s, str) and s.isdigit():
        s = int(s)                      # 居容:JSON 字符串数字照收
    if s not in (1, 2, 3, 4):
        warns.append(f"@{at}: 弦号非法 {s!r},记号丢弃")
        return None
    kind = m.get("kind")
    out = {"string": int(s),
           "kind": kind if kind in ("digit", "x", "unknown") else "unknown"}
    fret = m.get("fret")
    if isinstance(fret, str) and fret.isdigit():
        fret = int(fret)
    if kind == "digit" and not isinstance(fret, int):
        warns.append(f"@{at}: digit 缺品位 S{s},降级 unknown")
        out["kind"] = "unknown"
    elif kind == "digit":
        out["fret"] = int(fret)
    return out


def _norm_tech(tech, warns, at):
    if tech in (None, "", "null"):
        return None
    canon = TECH_ALIASES.get(str(tech).lower())
    if canon is None:
        warns.append(f"@{at}: tech 未识别 {tech!r},丢弃")
        return None
    return canon


def normalize(doc, main_axis=Fraction(MAIN_AXIS_BEATS)):
    """模型 JSON → 规整候选(marks 收拢、duration 持续窗重算、排序)。"""
    warns = []
    cols = []
    for c in doc.get("columns") or []:
        if not isinstance(c, dict) or c.get("beat") is None:
            warns.append(f"列缺 beat,丢弃:{c!r}")
            continue
        beat = rat(c["beat"])
        marks = []
        for m in c.get("marks") or []:
            nm = _norm_mark(m, warns, beat)
            if nm:
                marks.append(nm)
        col = {"beat": beat, "marks": marks,
               "tech": _norm_tech(c.get("tech"), warns, beat),
               "tie": bool(c.get("tie"))}
        if c.get("muted"):
            warns.append(f"@{beat}: 模型输出 muted,不入码(工单56 口径)")
        if c.get("duration") is not None:
            col["printed_duration"] = rat(c["duration"])
        cols.append(col)
    cols.sort(key=lambda c: c["beat"])

    rests = []
    for r in doc.get("rests") or []:
        if isinstance(r, dict) and r.get("beat") is not None \
                and r.get("beats") is not None:
            rests.append({"beat": rat(r["beat"]), "beats": rat(r["beats"])})
    ties, slides = [], []
    for t in doc.get("ties") or []:
        if isinstance(t, dict) and t.get("from_beat") is not None \
                and t.get("to_beat") is not None:
            a, b = rat(t["from_beat"]), rat(t["to_beat"])
            if b > a:
                ties.append({"from_beat": a, "to_beat": b})
            else:
                warns.append(f"延音线方向颠倒 {a}→{b},丢弃")
    for s in doc.get("slides") or []:
        if isinstance(s, dict) and s.get("from_beat") is not None \
                and s.get("to_beat") is not None:
            a, b = rat(s["from_beat"]), rat(s["to_beat"])
            if b > a:
                slides.append({"from_beat": a, "to_beat": b})
            else:
                warns.append(f"滑音方向颠倒 {a}→{b},丢弃")
    rests.sort(key=lambda r: r["beat"])

    # 持续窗重算:下一 attack(连音列除外)或休止止,封顶 main_axis
    attacks = sorted(c["beat"] for c in cols if not c["tie"])
    cuts = sorted(attacks + [r["beat"] for r in rests])
    for c in cols:
        nxt = [b for b in cuts if c["beat"] < b <= main_axis]
        c["duration"] = (min(nxt) if nxt else main_axis) - c["beat"]

    return {"schema": "ukeflow.eval.candidate/1", "columns": cols,
            "rests": rests, "ties": ties, "slides": slides,
            "warnings": warns}


def _seg_of(beat):
    for s in SEGMENTS:
        if rat(s["from_beat"]) <= beat < rat(s["to_beat"]):
            return s["id"]
    return None


def scope_filter(cand, ranges=SCOPE_RANGES):
    """只留已裁定拍段;按 SEGMENTS 标注 segment(per-segment 评分用)。"""
    def in_scope(b):
        return any(a <= b < e for a, e in ranges)

    out = {"schema": cand["schema"], "columns": [], "rests": [],
           "ties": [], "slides": [], "warnings": list(cand["warnings"])}
    for c in cand["columns"]:
        if in_scope(c["beat"]):
            col = dict(c)
            col["segment"] = _seg_of(c["beat"])
            out["columns"].append(col)
    out["rests"] = [r for r in cand["rests"] if in_scope(r["beat"])]
    out["ties"] = [t for t in cand["ties"] if in_scope(t["from_beat"])]
    out["slides"] = [s for s in cand["slides"] if in_scope(s["from_beat"])]
    return out


def _rat_json(v):
    f = rat(v)
    return str(f.numerator) if f.denominator == 1 \
        else f"{f.numerator}/{f.denominator}"


def to_jsonable(cand):
    """Fraction → JSON 可持久化形态(eval-joint 的 rat() 直接吃回)。"""
    def col(c):
        out = {"beat": _rat_json(c["beat"]),
               "duration": _rat_json(c["duration"]),
               "marks": c["marks"], "segment": c.get("segment")}
        if c.get("tech"):
            out["tech"] = c["tech"]
        if c.get("tie"):
            out["tie"] = True
        if c.get("unit"):
            out["unit"] = c["unit"]
        if c.get("printed_duration") is not None:
            out["printed_duration"] = _rat_json(c["printed_duration"])
        return out
    return {"schema": cand["schema"],
            "columns": [col(c) for c in cand["columns"]],
            "rests": [{"beat": _rat_json(r["beat"]),
                       "beats": _rat_json(r["beats"])} for r in cand["rests"]],
            "ties": [{"from_beat": _rat_json(t["from_beat"]),
                      "to_beat": _rat_json(t["to_beat"])} for t in cand["ties"]],
            "slides": [{"from_beat": _rat_json(s["from_beat"]),
                        "to_beat": _rat_json(s["to_beat"])}
                       for s in cand["slides"]],
            "warnings": cand["warnings"]}


# ── 编排:run / assemble ────────────────────────────────────

def ledger_path(out_dir):
    return os.path.join(out_dir, "ledger.jsonl")


def ledger_total_cny(out_dir) -> float:
    if not os.path.exists(ledger_path(out_dir)):
        return 0.0
    total = 0.0
    with open(ledger_path(out_dir), encoding="utf-8") as fh:
        for line in fh:
            row = json.loads(line)
            if row.get("cost_cny") is not None:
                total += row["cost_cny"]
    return total


def run_image(image_path, unit, out_dir, model=MODEL_DEFAULT,
              budget_cny=BUDGET_CNY_DEFAULT, transport=None):
    """跑一个单元:调用→存原始响应→归一→落候选→记账。返回候选 dict。"""
    os.makedirs(os.path.join(out_dir, "raw"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "cand"), exist_ok=True)
    with open(image_path, "rb") as fh:
        img_sha = hashlib.sha256(fh.read()).hexdigest()

    payload = build_payload(image_path, model=model)
    t0 = time.time()
    resp = call_model(payload, transport=transport)
    latency = round(time.time() - t0, 2)
    content = resp["choices"][0]["message"]["content"]
    usage = resp.get("usage")
    peak = is_peak(resp.get("created", time.time()))
    usd = call_cost_usd(usage, peak)
    cost_cny = None if usd is None else round(usd * CNY_PER_USD, 4)

    with open(os.path.join(out_dir, "raw", f"{unit}.resp.json"), "w",
              encoding="utf-8") as fh:
        json.dump(resp, fh, ensure_ascii=False, indent=1)

    def _ledger(ok, error=None):
        total_after = ledger_total_cny(out_dir) + (cost_cny or 0.0)
        with open(ledger_path(out_dir), "a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "unit": unit,
                "model": model, "prompt_version": PROMPT_VERSION,
                "image": os.path.abspath(image_path),
                "image_sha256": img_sha, "usage": usage,
                "peak_hours": peak, "cost_usd": usd, "cost_cny": cost_cny,
                "latency_s": latency, "finish_reason":
                    resp["choices"][0].get("finish_reason"), "ok": ok,
                "error": error,
            }, ensure_ascii=False) + "\n")
        return total_after

    try:
        cand = normalize(extract_json(content))
    except ValueError as exc:
        total = _ledger(ok=False, error=str(exc)[:200])
        print(f"[{unit}] 解析失败(响应已存 raw/,费用已记账):{exc}")
        u = usage or {}
        print(f"[{unit}] prompt={u.get('prompt_tokens')} "
              f"out={u.get('completion_tokens')} cost=¥{cost_cny} "
              f"累计=¥{total:.4f}")
        raise
    meta_warnings = [{"unit": unit, "msg": w} for w in cand["warnings"]]
    cand["meta"] = {"unit": unit, "model": model,
                    "prompt_version": PROMPT_VERSION, "image_sha256": img_sha,
                    "finish_reason": resp["choices"][0].get("finish_reason"),
                    "usage": usage, "peak_hours": peak, "cost_usd": usd,
                    "cost_cny": cost_cny, "latency_s": latency,
                    "warnings": meta_warnings}

    total_after = _ledger(ok=True)

    with open(os.path.join(out_dir, "cand", f"{unit}.cand.json"), "w",
              encoding="utf-8") as fh:
        json.dump(to_jsonable(cand), fh, ensure_ascii=False, indent=1)

    u = usage or {}
    print(f"[{unit}] {model} prompt={u.get('prompt_tokens')} "
          f"out={u.get('completion_tokens')} peak={peak} "
          f"cost=¥{cost_cny} 累计=¥{total_after:.4f} {latency}s "
          f"警告×{len(meta_warnings)}")
    if budget_cny is not None and total_after > budget_cny:
        print(f"✗ 预算越线:累计 ¥{total_after:.4f} > 上限 ¥{budget_cny}"
              f"(票面硬上限 ¥{BUDGET_CNY_DEFAULT});停止后续调用,"
              f"证据按已跑部分计。")
    return cand


def assemble(runs_dir, units, out_path):
    """多单元候选合并 → 过筛已裁定拍段 → 标段 → 落整表候选。

    过筛放在合并后单点做:未过筛单元文件留全时值轴(诊断用),整表候选
    才进 eval-joint。"""
    cols, rests, ties, slides, warns = [], [], [], [], []
    for u in units:
        with open(os.path.join(runs_dir, "cand", f"{u}.cand.json"),
                  encoding="utf-8") as fh:
            c = json.load(fh)
        for col in c["columns"]:
            col["unit"] = u
            cols.append(col)
        rests.extend(c["rests"])
        ties.extend(c["ties"])
        slides.extend(c["slides"])
        warns.extend({"unit": u, "msg": w} for w in c.get("warnings", []))
    merged = scope_filter({
        "schema": "ukeflow.eval.candidate/1",
        "columns": [{"beat": rat(c["beat"]), "duration": rat(c["duration"]),
                     "marks": c["marks"], "tech": c.get("tech"),
                     "tie": bool(c.get("tie")), "unit": c.get("unit"),
                     "printed_duration": (rat(c["printed_duration"])
                                          if c.get("printed_duration")
                                          else None)}
                    for c in cols],
        "rests": [{"beat": rat(r["beat"]), "beats": rat(r["beats"])}
                  for r in rests],
        "ties": [{"from_beat": rat(t["from_beat"]),
                  "to_beat": rat(t["to_beat"])} for t in ties],
        "slides": [{"from_beat": rat(s["from_beat"]),
                    "to_beat": rat(s["to_beat"])} for s in slides],
        "warnings": warns,
    })
    merged["columns"].sort(key=lambda c: c["beat"])
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(to_jsonable(merged), fh, ensure_ascii=False, indent=1)
    print(f"assemble {len(units)} 单元 → {out_path}:"
          f" 过筛后 {len(merged['columns'])} 列 / {len(merged['rests'])} 休止"
          f" / {len(merged['ties'])} 延音 / {len(merged['slides'])} 滑音")
    return merged


# ── 输入制备:整谱页拼装 + 系统裁块 ─────────────────────────

def _pix_to_image(pix):
    import io
    return Image.open(io.BytesIO(pix.tobytes("png")))


def prepare_pages(pdf_path, layout, score_pages, out_dir):
    """PDF 嵌入位图原生拼装整谱页(工单56 考古口径:不重采样)。"""
    import pymupdf
    doc = pymupdf.open(pdf_path)
    made = []
    for sp in score_pages:
        entry = next(p for p in layout["score_pages"] if p["index"] == sp)
        tiles = {}
        page = doc[entry["pdf_page"]]
        for im in page.get_images(full=True):
            for r in page.get_image_rects(im[0]):
                half = 0 if r.y0 < PDF_HALF_PT else 1
                if half != entry["half"]:
                    continue
                col = 0 if r.x0 < 297 else 1
                pix = pymupdf.Pixmap(doc, im[0])
                if pix.n - pix.alpha > 3:
                    pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
                tiles[(col, round(r.x0, 1))] = _pix_to_image(pix)
        assert len(tiles) == 2, f"谱页{sp}: 位图拼装需 2 块,得 {len(tiles)}"
        left = tiles[min(tiles, key=lambda k: k[1])]
        right = tiles[max(tiles, key=lambda k: k[1])]
        canvas = Image.new("RGB", (left.width + right.width, left.height),
                           "white")
        canvas.paste(left, (0, 0))
        canvas.paste(right, (left.width, 0))
        out = os.path.join(out_dir, f"page{sp}.png")
        canvas.save(out)
        made.append(out)
    return made


def prepare_crops(pages_dir, layout, systems, out_dir):
    """系统条带裁块(整块全层,保留完整节奏带);坐标 300dpi→原生换算。

    systems = ["page0:0", ...](谱页号:layout 系统 index)。"""
    made = []
    for spec in systems:
        page_s, sys_i = spec.split(":")
        sp = int(page_s.replace("page", ""))
        entry = next(p for p in layout["score_pages"] if p["index"] == sp)
        sys_row = next(s for s in entry["systems"] if s["index"] == int(sys_i))
        img = Image.open(os.path.join(pages_dir, f"page{sp}.png"))
        y0, y1 = sys_row["block"]
        ny0 = max(0, int((y0 - entry["half"] * RENDER_HALF_H)
                         * SCALE_RENDER_TO_NATIVE) - CROP_PAD_NATIVE)
        ny1 = min(img.height, int((y1 - entry["half"] * RENDER_HALF_H)
                                  * SCALE_RENDER_TO_NATIVE) + CROP_PAD_NATIVE)
        out = os.path.join(out_dir, f"crop-page{sp}.sys{sys_i}.png")
        img.crop((0, ny0, img.width, ny1)).save(out)
        made.append(out)
    return made
