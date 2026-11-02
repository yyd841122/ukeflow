"""已裁定评测集(工单56):装载/校验/冻结哈希/三类台账统计。

评测集 = 冻结的印张符号层真值(列+休止+延音线+滑音+和弦锚),版本化 +
payload sha256;真值冻结后改动走版本号(票面范围纪律)。历史转录(484 音)
只是底稿,评测集按裁决修正后与 Dart 常量有意偏离——所以不走 dump 真值
漂移闸(那闸护的是「随 App 常量走」的 fixture),本文件以自身哈希自洽。

三类台账(票面验收):已裁定 / 待裁定 / 未覆盖。待裁定项公布数量与覆盖率;
排除项(status=excluded)必须带 reason 行。
"""

import hashlib
import json

from .eval_expand import rat

SCHEMA = "ukeflow.eval.truth/1"
STATUSES = ("adjudicated", "pending", "excluded")
DEFAULT_PATH = "evalset/gs-aini-tab-v1.json"


def payload_sha256(payload) -> str:
    canonical = json.dumps(payload, sort_keys=True, ensure_ascii=False,
                           separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _need(cond, msg, path=""):
    if not cond:
        raise ValueError(f"评测集校验失败 {path}: {msg}")


def _validate_column(col, path):
    _need(isinstance(col.get("beat"), (int, float, str)), "缺 beat", path)
    beat = rat(col["beat"])
    status = col.get("status", "adjudicated")
    _need(status in STATUSES, f"status 非法 {status!r}", path)
    if status in ("pending", "excluded"):
        _need(bool(col.get("reason")) or bool(col.get("evidence")),
              f"{status} 项缺 reason/evidence 行", f"{path}@{beat}")
    for m in col.get("marks") or []:
        _need(m.get("kind") in ("x", "digit", "muted"),
              f"记号类别非法 {m.get('kind')!r}", f"{path}@{beat}")
        _need(m.get("string") in (1, 2, 3, 4), f"弦号非法 {m.get('string')}",
              f"{path}@{beat}")
        if m["kind"] == "digit":
            _need(isinstance(m.get("fret"), int), f"数字缺品位", f"{path}@{beat}")
    tech = col.get("tech")
    _need(tech in (None, "roll", "strumUp", "strumDown", "tremolo"),
          f"tech 非法 {tech!r}", f"{path}@{beat}")


def validate_evalset(doc) -> None:
    """结构+台账纪律校验(装载与冻结两侧同走)。"""
    _need(doc.get("schema") == SCHEMA, f"schema 非 {SCHEMA}")
    _need(isinstance(doc.get("version"), int) and doc["version"] >= 1,
          "缺整数 version")
    _need(bool(doc.get("frozen_at")), "缺 frozen_at")
    payload = doc.get("payload")
    _need(isinstance(payload, dict), "缺 payload")
    _need(doc.get("payload_sha256") == payload_sha256(payload),
          "payload_sha256 与 payload 不符(被手改?)")
    meta = doc.get("meta") or {}
    _need(isinstance(meta.get("event_count"), int),
          "meta.event_count 缺失(冻结一致性锚)")
    seg_ids = {s["id"] for s in payload.get("segments", [])}
    for col in payload.get("columns", []):
        _validate_column(col, "column")
        if col.get("segment") is not None:
            _need(col["segment"] in seg_ids, f"segment {col['segment']!r} 未登记")
    for r in payload.get("rests", []):
        _need(r.get("status", "adjudicated") in STATUSES, "rest status 非法")
        _need(r.get("beats") is not None, "rest 缺 beats")
    for t in payload.get("ties", []):
        _need(rat(t["to_beat"]) > rat(t["from_beat"]), "tie 方向颠倒")
    for s in payload.get("slides", []):
        _need(rat(s["to_beat"]) > rat(s["from_beat"]), "slide 方向颠倒")


def load_evalset(path) -> dict:
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    validate_evalset(doc)
    return doc


def in_scope(row, include_pending=False) -> bool:
    """评分范围:已裁定入分;待裁定默认出分(--include-pending 可入);
    排除项永不出分。"""
    st = row.get("status", "adjudicated")
    if st == "excluded":
        return False
    if st == "pending":
        return include_pending
    return True


def ledger_stats(doc) -> dict:
    """三类台账(已裁定/待裁定/未覆盖)计数与覆盖率。

    事件口径:列按展开后事件数计(expand 后数);覆盖率 = 已裁定事件 /
    (已裁定+待裁定) 事件。未覆盖拍段照抄 payload.uncovered(不计数)。
    """
    from .eval_expand import expand_events
    payload = doc["payload"]
    chords = payload.get("chords", [])
    cols = payload["columns"]
    counts = {"adjudicated": 0, "pending": 0, "excluded": 0}
    ev_counts = {"adjudicated": 0, "pending": 0, "excluded": 0}
    marks = {"adjudicated": 0, "pending": 0, "excluded": 0}
    for col in cols:
        st = col.get("status", "adjudicated")
        counts[st] += 1
        evs, _ = expand_events([col], chords)
        ev_counts[st] += len(evs)
        marks[st] += sum(1 for m in (col.get("marks") or []))
    scorable = ev_counts["adjudicated"] + ev_counts["pending"]
    coverage = (ev_counts["adjudicated"] / scorable) if scorable else 1.0
    pending_cols = [c for c in cols if c.get("status") == "pending"]
    pending_dir = [c for c in cols
                   if c.get("status") == "adjudicated" and c.get("tech_pending")]
    return {
        "columns": counts, "events": ev_counts, "marks": marks,
        "pending_direction_slots": len(pending_dir),
        "coverage_of_scorable_events": round(coverage, 4),
        "uncovered": payload.get("uncovered", []),
        "pending_beats": [str(c["beat"]) for c in pending_cols],
    }
