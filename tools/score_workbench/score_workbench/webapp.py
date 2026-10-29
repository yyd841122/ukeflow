"""校对台 web 层(工单51,dev-only):localhost 单页,左裁图/右数据/点击互跳。

Flask 应用工厂:状态全部住 `proof.load_session` 的会话里,每次变更落
`proof.json`(重启不丢);条带图 = 源 PDF 按切分 dpi 重渲染后按系统块裁
行(bbox 全程页坐标系,叠图直接对位)。只绑 127.0.0.1,无任何网络服务
(票面 Non-goal)。对照模式直接复用 diff_melody/diff_tab 报告(与 CLI
同形状),喂 edited 后的草稿视图——校对进度即识别质量验收。
"""

from __future__ import annotations

import datetime
import json
import os
import threading

from flask import Flask, jsonify, request, send_from_directory

from . import __version__, proof
from .melodic_diff import diff_melody
from .tab_diff import diff_tab

_STATIC = os.path.join(os.path.dirname(__file__), "static")


def create_app(out_dir: str) -> Flask:
    app = Flask("score_workbench.webapp", static_folder=_STATIC,
                static_url_path="/static")
    app.config["SWW_OUT"] = str(out_dir)
    app.config["SWW_SESSION"] = proof.load_session(str(out_dir))
    app.config["SWW_PAGES"] = {}          # pdf_page → 渲染灰度 ndarray(缓存)
    app.config["SWW_STRIPS"] = {}         # system index → PNG bytes
    # 会话锁(评审51 #100):Flask 默认多线程,变更+持久化+快照串行化,
    # 否则并发保存互踩 proof.json。
    lock = threading.Lock()

    def sess() -> dict:
        return app.config["SWW_SESSION"]

    def persist() -> None:
        proof.save_session(sess())

    def payload(measure: int | None = None) -> dict:
        s = sess()
        errors = proof.preflight(s)
        out = {
            "tool_version": __version__,
            "source": s["layout"]["source"],
            "meta": s["meta"],
            "progress": {"confirmed": sum(s["confirmed"]),
                         "total": proof.measure_count(s)},
            "validation": errors,
            "systems": systems_view(s),
            "measures": [proof.measure_view(s, mi, errors)
                         for mi in range(proof.measure_count(s))],
        }
        if measure is not None:
            out["measure"] = proof.measure_view(s, measure)
        return out

    @app.errorhandler(KeyError)
    def _not_found(exc):
        return jsonify({"error": f"不存在:{exc}"}), 404

    # ── 静态页与图 ──────────────────────────────────────────────────

    @app.get("/")
    def index():
        return send_from_directory(_STATIC, "index.html")

    @app.get("/api/session")
    def api_session():
        return jsonify(payload())

    @app.get("/crops/<path:rel>")
    def crops(rel):
        # 证据裁图只从 out_dir/crops/ 出(URL 不带 crops/ 前缀,防越界
        # 由 safe_join 兜);layout.json 等清单文件不外送。
        return send_from_directory(os.path.join(app.config["SWW_OUT"],
                                                "crops"), rel)

    @app.get("/api/strip/<int:sys_index>.png")
    def strip(sys_index: int):
        data = app.config["SWW_STRIPS"].get(sys_index)
        if data is None:
            data = render_strip(sess(), sys_index, app.config["SWW_PAGES"],
                                app.config["SWW_STRIPS"])
        return app.response_class(data, mimetype="image/png")

    # ── 变更(全部即改即存 proof.json)──────────────────────────────

    @app.post("/api/meta")
    def api_meta():
        fields = request.get_json(force=True)
        with lock:
            proof.set_meta(sess(), fields)
            if set(fields) & {"key", "meter", "melodyAlignBeats"}:
                s = sess()
                s["confirmed"] = [False] * proof.measure_count(s)
            persist()
        return jsonify(payload())

    @app.post("/api/confirm")
    def api_confirm():
        body = request.get_json(force=True)
        with lock:
            proof.set_confirm(sess(), int(body["measure"]), bool(body["value"]))
            persist()
        return jsonify(payload(measure=int(body["measure"])))

    @app.post("/api/confirm-all")
    def api_confirm_all():
        with lock:
            proof.confirm_all(sess())
            persist()
        return jsonify(payload())

    @app.post("/api/anchor")
    def api_anchor():
        layer = request.get_json(force=True).get("layer")
        if layer not in ("melody", "tab"):
            return jsonify({"error": "layer 须 melody|tab"}), 400
        try:
            with lock:
                moved = proof.anchor_layer_to_grid(sess(), layer)
                persist()
        except ValueError as exc:
            return jsonify({"error": str(exc)}), 400
        return jsonify({**payload(), "moved": moved})

    OPS = {
        ("note", "edit"): lambda s, b: proof.edit_note(
            s, b["layer"], b["measure"], b["row"], b.get("data") or {}),
        ("note", "add"): lambda s, b: proof.add_note(
            s, b["layer"], b["measure"], b.get("data") or {}),
        ("note", "delete"): lambda s, b: proof.delete_note(
            s, b["layer"], b["measure"], b["row"]),
        ("rest", "edit"): lambda s, b: proof.edit_rest(
            s, b["layer"], b["measure"], b["row"], b.get("data") or {}),
        ("rest", "add"): lambda s, b: proof.add_rest(
            s, b["layer"], b["measure"], b.get("data") or {}),
        ("rest", "delete"): lambda s, b: proof.delete_rest(
            s, b["layer"], b["measure"], b["row"]),
        ("technique", "edit"): lambda s, b: proof.edit_technique(
            s, b["measure"], b["row"], b.get("data") or {}),
        ("technique", "add"): lambda s, b: proof.add_technique(
            s, b["measure"], b.get("data") or {}),
        ("technique", "delete"): lambda s, b: proof.delete_technique(
            s, b["measure"], b["row"]),
        ("technique", "batch"): lambda s, b: proof.batch_technique(
            s, b.get("data") or {}),
        ("x", "delete"): lambda s, b: proof.delete_x_mark(
            s, b["measure"], b["row"]),
        ("x", "expand"): lambda s, b: proof.expand_x_mark(
            s, b["measure"], b["row"], b.get("data") or {}),
        ("chord", "add"): lambda s, b: proof.add_chord(
            s, b["measure"], b.get("data") or {}),
        ("chord", "edit"): lambda s, b: proof.edit_chord(s, b["row"],
                                                         b.get("data") or {}),
        ("chord", "delete"): lambda s, b: proof.delete_chord(s, b["row"]),
    }

    @app.post("/api/edit")
    def api_edit():
        body = request.get_json(force=True)
        kind, op = body.get("kind"), body.get("op")
        if (kind, op) not in OPS:
            return jsonify({"error": f"未知操作 {kind}/{op}"}), 400
        if kind in ("note", "rest") and body.get("layer") not in ("melody",
                                                                 "tab"):
            return jsonify({"error": "layer 须 melody|tab"}), 400
        try:
            with lock:
                result = OPS[(kind, op)](sess(), body)
                _clear_stale_confirms(sess(), kind, op, body)
                persist()
        except (KeyError, TypeError, ValueError) as exc:
            return jsonify({"error": str(exc)}), 400
        out = payload(body.get("measure"))
        if isinstance(result, int):              # batch 写入条数
            out["written"] = result
        elif isinstance(result, dict):           # × 还原建音数
            out["created"] = result
        return jsonify(out)

    def _clear_stale_confirms(s, kind, op, body):
        """编辑即弃确认(评审51 #196):改过的小节以陈旧复核身份导出比
        重点一次确认更糟。行级变更清本小节;批量技巧清区间;和弦锚按
        所在小节。"""
        if kind in ("note", "rest", "x") and body.get("measure") is not None:
            proof.set_confirm(s, int(body["measure"]), False)
        elif kind == "technique":
            if op == "batch":
                d = body.get("data") or {}
                lo = int(d.get("from_measure", 0))
                hi = int(d.get("to_measure", proof.measure_count(s) - 1))
                for mi in range(lo, hi + 1):
                    if 0 <= mi < proof.measure_count(s):
                        proof.set_confirm(s, mi, False)
            elif body.get("measure") is not None:
                proof.set_confirm(s, int(body["measure"]), False)
        elif kind == "chord":
            if op == "add" and body.get("measure") is not None:
                proof.set_confirm(s, int(body["measure"]), False)
            elif op in ("edit", "delete") and body.get("row") is not None:
                idx = int(body["row"])
                if 0 <= idx < len(s["chords"]):
                    proof.set_confirm(s, s["chords"][idx]["measure"], False)

    @app.post("/api/validate")
    def api_validate():
        return jsonify({"validation": proof.preflight(sess())})

    @app.post("/api/diff")
    def api_diff():
        body = request.get_json(force=True)
        try:
            truth = _read_truth(body.get("truth") or "")
        except OSError as exc:
            return jsonify({"error": f"真值读不了:{exc}"}), 400
        except json.JSONDecodeError as exc:
            return jsonify({"error": f"真值不是 JSON:{exc}"}), 400
        s = sess()
        start = body.get("start_measure")
        chunk = body.get("chunk_beats")
        if body.get("kind") == "tab":
            report = diff_tab(proof.current_tab_draft(s), truth,
                              start_measure=0 if start is None else int(start))
        else:
            report = diff_melody(proof.current_melody_draft(s), truth,
                                 start_measure=5 if start is None else int(start),
                                 chunk_beats=4.0 if chunk is None
                                 else float(chunk))
        return jsonify(report)

    @app.post("/api/export")
    def api_export():
        force = bool((request.get_json(silent=True) or {}).get("force"))
        with lock:
            s = sess()
            confirmed = bool(s["confirmed"]) and all(s["confirmed"])
            errors = proof.preflight(s)
            if not confirmed and not force:
                return jsonify({"error": "全曲未逐小节确认,导出被拒(票面:"
                                "全曲确认 → 导出;force 可担责旁路)",
                                "validation": errors}), 409
            if errors and not force:
                return jsonify({"error": "preflight 未过,逐条消解后再导出",
                                "validation": errors}), 409
            reviewed_at = datetime.datetime.now().astimezone().isoformat(
                timespec="seconds")
            try:
                ir, skipped = proof.build_ir(s, reviewed_at=reviewed_at)
            except ValueError as exc:            # 坏 meta(如 n/8 拍号)人话拒
                return jsonify({"error": str(exc)}), 400
            path = os.path.join(app.config["SWW_OUT"], "ir.json")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(json.dumps(ir, ensure_ascii=False, indent=1) + "\n")
        return jsonify({"ok": True, "path": path, "ir": ir, "skipped": skipped})

    return app


def _read_truth(path: str) -> dict:
    """真值 JSON:绝对/相对启动目录之外,再退一层试仓库根(dev 从任意
    目录起 serve,fixture 默认路径都能命中)。"""
    candidates = [path]
    if not os.path.isabs(path):
        repo = os.path.normpath(os.path.join(
            os.path.dirname(__file__), os.pardir, os.pardir, os.pardir))
        candidates.append(os.path.join(repo, path))
    for cand in candidates:
        if os.path.isfile(cand):
            with open(cand, encoding="utf-8") as fh:
                return json.load(fh)
    raise OSError(f"找不到 {path}(试过 {candidates})")



# ── 视图/渲染 ──────────────────────────────────────────────────────────

def systems_view(session: dict) -> list:
    """系统条带元数据(左栏):块几何 + 该系统的全局小节矩形(取旋律草稿
    的全局小节序与页坐标 x;两草稿同出一 layout,系统集一致)。"""
    rects: dict[int, list] = {}
    for m in session["melody"]["measures"]:
        rects.setdefault(m["system"], []).append(
            {"index": m["index"], "x0": m["x0"], "x1": m["x1"]})
    out = []
    for page in session["layout"]["score_pages"]:
        for s in page["systems"]:
            out.append({"index": s["index"], "page": page["index"],
                        "pdf_page": page["pdf_page"], "half": page["half"],
                        "block": s["block"],
                        "measures": sorted(rects.get(s["index"], []),
                                           key=lambda r: r["x0"])})
    out.sort(key=lambda s: s["index"])
    return out


def render_strip(session: dict, sys_index: int, page_cache: dict,
                 strip_cache: dict) -> bytes:
    """系统条带 PNG:源 PDF 按 layout 的 dpi 重渲染(页缓存)→ 系统块裁
    行(上下各 6px 余量)→ PNG。页坐标系与 bbox 对位,叠图零换算。"""
    import cv2
    import numpy as np
    import pymupdf

    system = next((s for p in session["layout"]["score_pages"]
                   for s in p["systems"] if s["index"] == sys_index), None)
    if system is None:
        raise KeyError(f"系统 {sys_index} 不在 layout 里")
    pdf_page = next(p["pdf_page"] for p in session["layout"]["score_pages"]
                    for s in p["systems"] if s["index"] == sys_index)
    page_arr = page_cache.get(pdf_page)
    if page_arr is None:
        scale = session["layout"]["source"]["dpi"] / 72.0
        doc = pymupdf.open(session["layout"]["source"]["file"])
        try:
            pix = doc[pdf_page].get_pixmap(
                matrix=pymupdf.Matrix(scale, scale), colorspace=pymupdf.csGRAY)
            page_arr = np.frombuffer(pix.samples, dtype=np.uint8).reshape(
                pix.height, pix.width).copy()
        finally:
            doc.close()
        # layout 几何来自纠偏后图像(评审51 #274):条带图须施加同一变换,
        # 否则纠偏页的 bbox 叠图错位。deskew 自带小角跳过,与切分口径一致。
        from .split import deskew
        angle = next((d["angle_deg"] for d in session["layout"]["deskew"]
                      if d["pdf_page"] == pdf_page), 0.0)
        page_arr = deskew(page_arr, angle)
        page_cache[pdf_page] = page_arr
    pad = 6
    y0 = max(0, int(system["block"][0]) - pad)
    y1 = min(page_arr.shape[0], int(system["block"][1]) + 1 + pad)
    ok, buf = cv2.imencode(".png", page_arr[y0:y1, :])
    if not ok:
        raise RuntimeError("条带 PNG 编码失败")
    data = buf.tobytes()
    strip_cache[sys_index] = data
    return data
