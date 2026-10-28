/* 校对台前端(工单51):左系统条带/右小节 IR 表,点击互跳,逐小节确认。
 * 无框架 vanilla JS;所有变更 POST /api/edit 后用返回的整包 payload 重渲染
 * (localhost,数据量小,简单优先)。bbox 全程页坐标系,叠图零换算。 */
"use strict";

let S = null;            // /api/session 整包
let cur = 0;             // 当前小节
let selRow = null;       // {key, row} 右栏选中行(左栏 bbox 高亮)
let editing = null;      // {key, row|-1} 行内编辑 / 添加
let sysGeom = new Map(); // system index → {w,h,y0}(img 加载后量得)

const $ = (q, el) => (el || document).querySelector(q);
const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") n.className = v;
    else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
    else if (v !== null && v !== undefined) n.setAttribute(k, v);
  }
  for (const k of kids) if (k !== null && k !== undefined) n.append(k);
  return n;
};
const fmtNum = v => (v === null || v === undefined ? "?" :
  (Number.isInteger(v) ? v : +v.toFixed(3)));
const conf = n => (n.confidence === null || n.confidence === undefined
  ? "—" : n.confidence.toFixed(2));
const src = n => (n.manual ? `人${n.manual === true ? "" : ":" + n.manual}`
  : (n.evidence && n.evidence.confidence != null ? "识别" : "—"));

async function api(path, body) {
  const resp = await fetch(path, body === undefined
    ? {} : { method: "POST", headers: { "Content-Type": "application/json" },
             body: JSON.stringify(body) });
  const json = await resp.json();
  if (!resp.ok) {
    toast(json.error || `HTTP ${resp.status}`, true);
    if (json.validation) renderIssues(json.validation);
    throw new Error(json.error || resp.status);
  }
  return json;
}

let toastTimer = null;
function toast(msg, isErr) {
  let t = $("#toast");
  if (!t) {
    t = el("div", { id: "toast" });
    Object.assign(t.style, {
      position: "fixed", right: "18px", bottom: "18px", zIndex: 99,
      padding: "8px 14px", borderRadius: "8px", maxWidth: "460px",
      background: isErr ? "#5a2430" : "#1f4636", color: "#fff",
      border: `1px solid ${isErr ? "#a45" : "#3ecf8e"}`, whiteSpace: "pre-wrap",
    });
    document.body.append(t);
  }
  t.textContent = msg;
  t.style.display = "block";
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.style.display = "none"; }, isErr ? 6000 : 2500);
}

/* ── 表格规格(行编辑字段与列一一对应)─────────────────────────── */
const TECH_KINDS = ["roll", "strumUp", "strumDown", "shaft", "slide",
  "tremolo", "ellipse"];
const TABLES = {
  "melody:notes": {
    title: "旋律音", layer: "melody", kind: "note", sec: "melody",
    cols: ["度", "上点", "下点", "拍", "时值", "置信", "来源"],
    fields: [
      { k: "degree", label: "度(1-7)", type: "num" },
      { k: "dots_above", label: "上点", type: "num" },
      { k: "dots_below", label: "下点", type: "num" },
      { k: "beat", label: "拍", type: "num" },
      { k: "duration", label: "时值", type: "num" },
    ],
    fmt: n => [n.degree === null ? "?" : n.degree, n.dots_above || 0,
      n.dots_below || 0, fmtNum(n.beat), fmtNum(n.duration), conf(n), src(n)],
    rows: m => m.melody ? m.melody.notes : [],
    add: { degree: 1, dots_above: 0, dots_below: 0, beat: 0, duration: 1 },
  },
  "melody:rests": {
    title: "旋律休止(印张 0 号,声部簿记)", layer: "melody", kind: "rest",
    sec: "melody",
    cols: ["拍", "拍数", "来源"],
    fields: [{ k: "beat", label: "拍", type: "num" },
             { k: "beats", label: "拍数", type: "num" }],
    fmt: r => [fmtNum(r.beat), fmtNum(r.beats), src(r)],
    rows: m => m.melody ? m.melody.rests : [],
    add: { beat: 0, beats: 1 },
  },
  "tab:notes": {
    title: "TAB 音", layer: "tab", kind: "note", sec: "tab",
    cols: ["弦", "品", "拍", "时值", "置信", "来源"],
    fields: [{ k: "string", label: "弦(1-4)", type: "num" },
             { k: "fret", label: "品", type: "num" },
             { k: "beat", label: "拍", type: "num" },
             { k: "duration", label: "时值", type: "num" }],
    fmt: n => [n.string ?? "?", n.fret ?? "?", fmtNum(n.beat),
      fmtNum(n.duration), conf(n), src(n)],
    rows: m => m.tab ? m.tab.notes : [],
    add: { string: 1, fret: 0, beat: 0, duration: 1 },
  },
  "tab:rests": {
    title: "TAB 休止(照印张 → 显示休止)", layer: "tab", kind: "rest",
    sec: "tab",
    cols: ["种", "拍", "拍数", "来源"],
    fields: [{ k: "kind", label: "种", type: "select",
               options: ["rest8", "rest_whole"] },
             { k: "beat", label: "拍", type: "num" },
             { k: "beats", label: "拍数", type: "num" }],
    fmt: r => [r.kind, fmtNum(r.beat), fmtNum(r.beats), src(r)],
    rows: m => m.tab ? m.tab.rests : [],
    add: { kind: "rest8", beat: 0, beats: 1 },
  },
  "tab:tech": {
    title: "技巧记号", layer: "tab", kind: "technique", sec: "tab",
    cols: ["种", "拍", "止拍", "来源"],
    fields: [{ k: "kind", label: "种", type: "select", options: TECH_KINDS },
             { k: "beat", label: "拍", type: "num" },
             { k: "to_beat", label: "止拍(滑音)", type: "num" }],
    fmt: t => [t.kind, fmtNum(t.beat),
      t.to_beat === null || t.to_beat === undefined ? "—" : fmtNum(t.to_beat),
      src(t)],
    rows: m => m.tab ? m.tab.techniques : [],
    add: { kind: "strumDown", beat: 0, to_beat: null },
  },
  "chords": {
    title: "和弦锚(小节内拍)", kind: "chord", sec: "chords",
    cols: ["拍", "名", "指法 ④③②①", "基品", "来源"],
    fields: [{ k: "beat", label: "拍(小节内)", type: "num" },
             { k: "label", label: "名", type: "text" },
             { k: "frets", label: "指法(逗号分隔,×=-1)", type: "text" },
             { k: "baseFret", label: "基品", type: "num" }],
    fmt: c => [fmtNum(c.beat), c.label, c.fingering.frets.join(","),
      c.fingering.baseFret, "人"],
    rows: m => m.chords,
    rowId: c => c.index,               // 和弦行带全局序号(会话级列表)
    pack: d => ({ beat: d.beat, label: d.label, baseFret: d.baseFret,
      frets: String(d.frets).split(",").map(v => parseInt(v.trim(), 10)) }),
    unpack: c => ({ beat: c.beat, label: c.label,
      frets: c.fingering.frets.join(","), baseFret: c.fingering.baseFret }),
    add: { beat: 0, label: "C", frets: "-1,3,2,1", baseFret: 1 },
  },
};

/* ── 载入与整体渲染 ─────────────────────────────────────────────── */
async function load() {
  S = await fetch("/api/session").then(r => r.json());
  $("#src-name").textContent = S.source.file.split("/").pop();
  renderMeta(); renderIssues(S.validation);
  buildSystems(); updateOverlays(); renderPanel(); renderProgress();
  if (S.progress.total > 0) {
    const first = S.measures.findIndex(m => !m.confirmed);
    selectMeasure(first === -1 ? 0 : first, false);
  }
}

function renderMeta() {
  const m = S.meta;
  $("#m-id").value = m.id || ""; $("#m-title").value = m.title || "";
  $("#m-artist").value = m.artist || ""; $("#m-key").value = m.key || "";
  $("#m-meter").value = m.meter || "";
  $("#m-tempo").value = m.tempo ?? ""; $("#m-align").value = m.melodyAlignBeats ?? 0;
}

function renderProgress() {
  $("#progress").innerHTML = `已确认 <b>${S.progress.confirmed}</b>/${S.progress.total} 小节`;
}

function renderIssues(errors) {
  const box = $("#issues");
  if (!errors || !errors.length) { box.classList.add("hidden"); return; }
  box.classList.remove("hidden");
  box.replaceChildren(el("div", {},
    ...errors.map(e => el("div", {
      class: "iss",
      onclick: () => { if (e.measure) selectMeasure(e.measure - 1, true); },
    }, `${e.measure ? `第 ${e.measure} 小节 · ` : "全局 · "}${e.field} — ${e.message}`))));
}

/* ── 左栏:系统条带 + 叠图 ──────────────────────────────────────── */
function buildSystems() {
  const wrap = $("#systems");
  wrap.replaceChildren();
  for (const sys of S.systems) {
    const img = el("img", { src: `/api/strip/${sys.index}.png` });
    const svg = el("svg", { preserveAspectRatio: "none" });
    const label = el("div", { class: "sys-label" },
      `系统 ${sys.index}(谱页 ${sys.page})`);
    const box = el("div", { class: "sys", "data-sys": sys.index }, img, svg, label);
    img.addEventListener("load", () => {
      sysGeom.set(sys.index, { w: img.naturalWidth, h: img.naturalHeight,
                               y0: sys.block[0] - 6 });
      svg.setAttribute("viewBox", `0 0 ${img.naturalWidth} ${img.naturalHeight}`);
      updateOverlays();
    });
    wrap.append(box);
  }
}

function updateOverlays() {
  for (const sys of S.systems) {
    const svg = $(`.sys[data-sys="${sys.index}"] svg`);
    if (!svg) continue;
    const g = sysGeom.get(sys.index);
    if (!g) { svg.replaceChildren(); continue; }
    const kids = [];
    for (const r of sys.measures) {
      const isCur = r.index === cur;
      kids.push(el("rect", {
        class: "mrect" + (isCur ? " cur" : ""), x: r.x0, y: 0,
        width: Math.max(2, r.x1 - r.x0), height: g.h,
        "data-mi": r.index,
        onclick: () => selectMeasure(r.index, false),
      }));
    }
    const mv = S.measures[cur];
    if (mv && mv.system === sys.index) {
      for (const [key, rows] of [["melody:notes", mv.melody && mv.melody.notes],
                                 ["tab:notes", mv.tab && mv.tab.notes],
                                 ["tab:tech", mv.tab && mv.tab.techniques]]) {
        (rows || []).forEach((n, i) => {
          const b = n.evidence && n.evidence.bbox;
          if (!b) return;
          kids.push(el("rect", {
            class: "bbox" + (selRow && selRow.key === key && selRow.row === i
              ? " hot" : ""),
            x: b[0], y: b[1] - g.y0, width: b[2], height: b[3],
            "data-key": key, "data-row": i,
            onclick: e => { e.stopPropagation(); selectRow(key, i); },
          }));
        });
      }
    }
    svg.replaceChildren(...kids);
  }
}

/* ── 右栏:小节面板 ─────────────────────────────────────────────── */
function measureErrors(mv) {
  return S.validation.filter(e => e.measure === mv.index + 1);
}

function renderPanel() {
  const mv = S.measures[cur];
  if (!mv) { $("#panel").replaceChildren("无小节"); return; }
  const panel = $("#panel");
  panel.replaceChildren(
    navSection(mv),
    tableSection("melody:notes", mv),
    tableSection("melody:rests", mv),
    tableSection("tab:notes", mv),
    tableSection("tab:rests", mv),
    xSection(mv),
    tableSection("tab:tech", mv, batchForm(mv)),
    tableSection("chords", mv),
  );
}

function navSection(mv) {
  const bad = measureErrors(mv);
  const sec = el("section", {},
    el("div", { class: "mnav" },
      el("button", { onclick: () => selectMeasure(cur - 1, true) }, "‹ 上一小节"),
      el("span", { class: "mn-title" }, `第 ${mv.index + 1} 小节`),
      el("button", { onclick: () => selectMeasure(cur + 1, true) }, "下一小节 ›"),
      el("button", {
        class: "confirm-btn" + (mv.confirmed ? " on" : ""),
        onclick: async () => {
          S = await api("/api/confirm",
            { measure: mv.index, value: !mv.confirmed });
          renderProgress();
          if (!mv.confirmed) {
            const next = S.measures.findIndex(m => !m.confirmed);
            renderPanel(); updateOverlays();
            if (next !== -1) selectMeasure(next, true);
            return;
          }
          renderPanel(); updateOverlays();
        },
      }, mv.confirmed ? "✓ 已确认" : "确认本小节"),
      el("span", { class: "badge" + (mv.melody && mv.melody.closure_ok ? " ok" : " bad") },
        `旋律闭合 ${mv.melody ? (mv.melody.closure_ok ? "✓" : "✗") : "—"}`),
      el("span", { class: "badge" + (mv.tab && mv.tab.closure_ok ? " ok" : " bad") },
        `TAB闭合 ${mv.tab ? (mv.tab.closure_ok ? "✓" : "✗") : "—"}`),
    ),
  );
  const warns = [
    ...(mv.melody ? mv.melody.warnings : []),
    ...(mv.tab ? mv.tab.warnings : []),
  ];
  if (warns.length) {
    sec.append(el("ul", { class: "warnlist" },
      ...warns.slice(0, 8).map(w => el("li", {}, w))));
  }
  if (bad.length) {
    sec.append(el("ul", { class: "errlist" },
      ...bad.map(e => el("li", {}, `${e.field}:${e.message}`))));
  }
  return sec;
}

function cellText(v, isNum) {
  const td = el("td", { class: isNum ? "num" : "" });
  td.textContent = v;
  return td;
}

function tableSection(key, mv, extra) {
  const cfg = TABLES[key];
  const rows = cfg.rows(mv);
  const sec = el("section", {},
    el("h3", {}, cfg.title, " ",
      el("span", { class: "cnt" }, `(${rows.length})`)));
  const tbl = el("table", { class: "data" },
    el("tr", {}, el("th", {}, "#"),
      ...cfg.cols.map(c => el("th", {}, c)),
      el("th", {}, "")));
  rows.forEach((r, i) => {
    const rid = cfg.rowId ? cfg.rowId(r) : i;
    if (editing && editing.key === key && editing.row === rid) {
      tbl.append(editRow(key, mv, rid, i, r));
      return;
    }
    const isSel = selRow && selRow.key === key && selRow.row === i;
    const tr = el("tr", {
      class: "rowline" + (isSel ? " sel" : ""),
      onclick: () => selectRow(key, i),
    }, cellText(i + 1, true),
      ...cfg.fmt(r).map(v => cellText(v, typeof v === "number")),
      el("td", {},
        el("button", { title: "改", onclick: e => {
          e.stopPropagation(); editing = { key, row: rid }; renderPanel();
        } }, "✎"),
        " ",
        el("button", { class: "danger", title: "删", onclick: async e => {
          e.stopPropagation();
          S = await api("/api/edit", { kind: cfg.kind, op: "delete",
            layer: cfg.layer, measure: mv.index, row: rid });
          afterMutation(mv.index);
        } }, "✗")));
    if (isSel) tr.classList.add("flash");
    tbl.append(tr);
  });
  if (editing && editing.key === key && editing.row === -1) {
    tbl.append(editRow(key, mv, -1, cfg.add));
  }
  sec.append(tbl, el("div", { class: "addform" },
    el("button", { onclick: () => { editing = { key, row: -1 }; renderPanel(); } },
      `+ 添加${cfg.title.split("(")[0]}`), extra || null));
  return sec;
}

function editRow(key, mv, row, dispRow, data) {
  const cfg = TABLES[key];
  const inputs = {};
  const values = cfg.unpack ? cfg.unpack(data) : data;
  const tr = el("tr", { class: "editing" }, cellText(row === -1 ? "+" : row + 1, true));
  for (const f of cfg.fields) {
    const td = el("td");
    const input = f.type === "select"
      ? el("select", {}, ...f.options.map(o => el("option", { value: o }, o)))
      : el("input", { class: "w-num", placeholder: f.label });
    if (f.type === "select") input.value = values[f.k] ?? f.options[0];
    else input.value = values[f.k] ?? "";
    inputs[f.k] = input;
    td.append(input);
    tr.append(td);
  }
  tr.append(el("td", {},
    el("button", {
      class: "primary",
      onclick: async e => {
        e.stopPropagation();
        const payload = {};
        for (const [k, inp] of Object.entries(inputs)) {
          payload[k] = inp.value === "" ? null : inp.value;
        }
        const body = { kind: cfg.kind, op: row === -1 ? "add" : "edit",
          layer: cfg.layer, measure: mv.index, row,
          data: cfg.pack ? cfg.pack(payload) : payload };
        S = await api("/api/edit", body);
        editing = null;
        afterMutation(mv.index);
      },
    }, "存"),
    " ",
    el("button", { onclick: e => {
      e.stopPropagation(); editing = null; renderPanel();
    } }, "✗")));
  return tr;
}

function xSection(mv) {
  const marks = mv.tab ? mv.tab.x_marks : [];
  const sec = el("section", {},
    el("h3", {}, "× 拨痕证据", " ", el("span", { class: "cnt" }, `(${marks.length})`),
      " ", el("span", { class: "hint", style: "font-weight:400" },
        "照读谱法不落音;还原为音须查和弦指形")));
  const tbl = el("table", { class: "data" },
    el("tr", {}, el("th", {}, "#"), el("th", {}, "种"), el("th", {}, "弦"),
      el("th", {}, "拍"), el("th", {}, "")));
  marks.forEach((x, i) => {
    if (editing && editing.key === "x-expand" && editing.row === i) {
      tbl.append(xExpandRow(mv, i, x));
      return;
    }
    tbl.append(el("tr", { class: "rowline" }, cellText(i + 1, true),
      cellText(x.kind), cellText((x.strings || []).join(",") || "?"),
      cellText(fmtNum(x.beat), true),
      el("td", {},
        el("button", { title: "按和弦还原为音", onclick: () => {
          editing = { key: "x-expand", row: i }; renderPanel();
        } }, "还原"),
        " ",
        el("button", { class: "danger", title: "丢弃(非拨痕)", onclick: async e => {
          e.stopPropagation();
          S = await api("/api/edit", { kind: "x", op: "delete",
            measure: mv.index, row: i });
          afterMutation(mv.index);
        } }, "✗"))));
  });
  sec.append(tbl);
  return sec;
}

function xExpandRow(mv, row, x) {
  const label = el("input", { class: "w-num", style: "width:70px",
    placeholder: "和弦名", value: "" });
  const frets = el("input", { class: "w-num", style: "width:110px",
    placeholder: "④③②①,×=-1", value: "-1,4,4,2" });
  const base = el("input", { class: "w-num", value: "1" });
  const tr = el("tr", { class: "editing" }, cellText(row + 1, true),
    cellText(x.kind), cellText((x.strings || []).join(",") || "?"),
    cellText(fmtNum(x.beat), true),
    el("td", { style: "white-space:nowrap" },
      label, " ", frets, " 基品 ", base, " ",
      el("button", { class: "primary", onclick: async e => {
        e.stopPropagation();
        const fl = frets.value.split(",").map(v => parseInt(v.trim(), 10));
        S = await api("/api/edit", { kind: "x", op: "expand",
          measure: mv.index, row,
          data: { label: label.value, frets: fl,
                  baseFret: parseInt(base.value, 10) || 1 } });
        editing = null;
        toast(`× 已还原为 ${S.created ? S.created.created : 0} 个音`);
        afterMutation(mv.index);
      } }, "还原为音"),
      " ",
      el("button", { onclick: e => {
        e.stopPropagation(); editing = null; renderPanel();
      } }, "✗")));
  return tr;
}

function batchForm(mv) {
  const kind = el("select", {}, ...TECH_KINDS.map(k => el("option", { value: k }, k)));
  const beat = el("input", { class: "w-num", value: "0", title: "小节内拍位" });
  const from = el("input", { class: "w-num", value: "1", title: "起小节(1 起)" });
  const to = el("input", { class: "w-num", value: String(S.progress.total),
    title: "止小节(含)" });
  return [
    el("button", { onclick: async e => {
      e.stopPropagation();
      const n = await api("/api/edit", { kind: "technique", op: "batch",
        data: { kind: kind.value, beat: parseFloat(beat.value),
                from_measure: parseInt(from.value, 10) - 1,
                to_measure: parseInt(to.value, 10) - 1 } });
      S = n; editing = null;
      toast(`批量写入 ${n.written} 个小节`);
      afterMutation(mv.index);
    } }, "批量写入每小节 →"),
    kind, "拍", beat, "小节", from, "到", to,
  ];
}

/* ── 互跳与变更收尾 ─────────────────────────────────────────────── */
function selectMeasure(mi, scroll) {
  if (!S.measures.length) return;
  cur = Math.max(0, Math.min(S.measures.length - 1, mi));
  selRow = null;
  editing = null;
  updateOverlays(); renderPanel();
  if (scroll) {
    const mv = S.measures[cur];
    const sysEl = $(`.sys[data-sys="${mv.system}"]`);
    if (sysEl) sysEl.scrollIntoView({ block: "nearest", behavior: "smooth" });
    $("#panel").scrollTop = 0;
  }
}

function selectRow(key, row) {
  selRow = { key, row };
  updateOverlays(); renderPanel();
  const sel = $("#panel tr.sel");
  if (sel) sel.scrollIntoView({ block: "nearest" });
}

function afterMutation(mi) {
  renderIssues(S.validation); renderProgress();
  updateOverlays();
  cur = Math.max(0, Math.min(S.measures.length - 1, mi ?? cur));
  renderPanel();
}

async function runDiff(kind) {
  const body = kind === "tab"
    ? { kind, truth: $("#diff-tab-truth").value,
        start_measure: parseInt($("#diff-tab-start").value, 10) || 0 }
    : { kind, truth: $("#diff-melody-truth").value,
        start_measure: parseInt($("#diff-melody-start").value, 10) || 5,
        chunk_beats: parseFloat($("#diff-melody-chunk").value) || 4 };
  const rep = await api("/api/diff", body);
  $("#diff-result").replaceChildren(diffReport(kind, rep));
}

function pct(ok, total) {
  if (!total) return "—";
  const p = Math.round(100 * ok / total);
  return el("span", { class: p >= 90 ? "bad-good" : p >= 60 ? "bad-mid" : "bad-bad" },
    `${ok}/${total} = ${p}%`);
}

function diffReport(kind, rep) {
  const box = el("div");
  const s = rep.summary || {};
  if (kind === "melody") {
    const pairs = (s.degree_ok || 0) + (s.degree_bad || 0);
    box.append(el("div", {}, "度数 ", pct(s.degree_ok, pairs), " · 拍位 ",
      pct(s.beat_ok, (s.beat_ok || 0) + (s.beat_bad || 0)), " · 时值 ",
      pct(s.duration_ok, s.duration_compared), " · 八度点 ",
      pct(s.octave_ok, (s.octave_ok || 0) + (s.octave_bad || 0)),
      ` · 草稿尾部超出 ${s.tail_notes_beyond_truth || 0} 音不比`));
  } else {
    const f1 = v => v == null ? "—" : v.toFixed(3);
    box.append(el("div", {}, "数字正确率 ", pct(s.digit_ok, s.digit_matched),
      `(配对 ${s.digit_matched},草稿 ${s.draft_notes},同弦错位 ${s.string_mismatch})`,
      ` · 时值 ${rep.duration ? rep.duration.ok + "/" + rep.duration.compared : "—"}`,
      rep.rests ? ` · 休止 P=${f1(rep.rests.precision)} R=${f1(rep.rests.recall)}` : "",
      rep.techniques ? ` · 技巧 F1=${f1(rep.techniques.f1)}(P=${f1(rep.techniques.precision)} R=${f1(rep.techniques.recall)})` : ""));
    if (rep.techniques && rep.techniques.by_kind) {
      for (const [k, v] of Object.entries(rep.techniques.by_kind)) {
        if (v.tp || v.fp || v.fn) {
          box.append(el("div", { style: "color:var(--dim)" },
            `· ${k}: tp ${v.tp} fp ${v.fp} fn ${v.fn} F1=${f1(v.f1)}`));
        }
      }
    }
  }
  const hot = rep.chunks ? rep.chunks.filter(c => c.mismatches) : rep.hotspots || [];
  if (hot.length) {
    box.append(el("h3", { style: "margin:8px 0 4px" }, `热点 ${hot.length} 条`));
    const tbl = el("table", { class: "data" });
    for (const h of hot.slice(0, 40)) {
      if (h.mismatches) {
        for (const m of h.mismatches.slice(0, 4)) {
          tbl.append(el("tr", {},
            cellText(`truth 第${h.truth_measure}小节 ↔ 草稿 m${h.draft_measures}`),
            cellText(`${m.field}@${m.beat ?? "?"} 草:${m.draft} 真:${m.truth}`)));
        }
      } else {
        tbl.append(el("tr", {},
          cellText(`${h.field}@b${h.beat ?? "?"} 弦${h.string ?? "?"}`),
          cellText(`草:${h.draft} 真:${h.truth}`)));
      }
    }
    box.append(tbl);
  } else {
    box.append(el("div", { style: "color:var(--ok)" }, "无热点,逐位全对"));
  }
  return box;
}

/* ── 顶栏动作 ───────────────────────────────────────────────────── */
for (const [id, key] of [["m-id", "id"], ["m-title", "title"],
                         ["m-artist", "artist"], ["m-key", "key"],
                         ["m-meter", "meter"], ["m-tempo", "tempo"],
                         ["m-align", "melodyAlignBeats"]]) {
  $("#" + id).addEventListener("change", async e => {
    S = await api("/api/meta", { [key]: e.target.value });
    renderIssues(S.validation); renderProgress();
    toast("曲头已存");
  });
}
$("#btn-anchor-melody").onclick = async () => {
  const r = await api("/api/anchor", { layer: "melody" });
  S = r; afterMutation(cur); toast(`旋律层重锚 ${r.moved} 个小节`);
};
$("#btn-anchor-tab").onclick = async () => {
  const r = await api("/api/anchor", { layer: "tab" });
  S = r; afterMutation(cur); toast(`TAB 层重锚 ${r.moved} 个小节`);
};
$("#btn-validate").onclick = async () => {
  const r = await api("/api/validate");
  renderIssues(r.validation);
  toast(r.validation.length ? `${r.validation.length} 条阻塞错误(见顶部)` : "校验通过,可导出");
};
$("#btn-diff").onclick = () => $("#diff-panel").classList.toggle("hidden");
$("#btn-export").onclick = async () => {
  const r = await fetch("/api/export", { method: "POST",
    headers: { "Content-Type": "application/json" }, body: "{}" });
  const json = await r.json();
  if (r.status === 409) {
    renderIssues(json.validation);
    toast(`preflight 未过(${json.validation.length} 条),已列顶部;确要强行导出加 force`, true);
    return;
  }
  if (!r.ok) { toast(json.error || `HTTP ${r.status}`, true); return; }
  const blob = new Blob([JSON.stringify(json.ir, null, 1)], { type: "application/json" });
  const a = el("a", { href: URL.createObjectURL(blob),
    download: `${S.meta.id || "ir"}.json` });
  a.click();
  toast(`已导出 ${json.path}(下载为 ${S.meta.id}.json)`);
};

document.addEventListener("keydown", e => {
  const tag = (document.activeElement || {}).tagName;
  if (tag === "INPUT" || tag === "SELECT" || tag === "TEXTAREA") return;
  if (e.key === "ArrowLeft") selectMeasure(cur - 1, true);
  if (e.key === "ArrowRight") selectMeasure(cur + 1, true);
});

load().catch(err => {
  $("#panel").textContent = `载入失败:${err}`;
});
