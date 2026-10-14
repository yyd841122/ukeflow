/// Cifra Club 页内提取脚本(工单 17):在 WebView 里执行,从当前曲谱页
/// DOM 提取行结构,返回 JSON 字符串(形状见 core/chart/cifra_extract.dart
/// 的 decodeCifraPayload;失败返回 {error: <code>})。
///
/// 防御式纪律(调研 2026-10-08 + 2026-06 存档页两种形态都兼容):
/// - 内容容器:优先 `pre[data-chord-content]`(调研形态),退回「b 元素
///   最多的 pre」(2026-06 存档为裸 pre)。
/// - 行切分:文本节点内的 \n 与 <br> 都切行;`<div>` 直接子元素自成一行
///   (调研形态按行分 div)。
/// - 和弦:`<b>` 元素,名字取 data-chord-name > data-chord-original-text >
///   文本内容(调研:CSS 类名是混淆的,只有 data-* 相对稳定)。
/// - 元数据:ld+json 的 MusicRecording 优先,退回 document.title 的
///   「歌名 - 艺人 - Cifra Club」形态。
library;

const cifraExtractScript = '''
(function() {
  try {
    function chordNameOf(el) {
      return (el.getAttribute('data-chord-name')
        || el.getAttribute('data-chord-original-text')
        || el.textContent || '').trim();
    }
    // 和弦名形状:根音(A-G 可带升降号)+ quality 字符表。
    // 「Baby」「Be」这类加粗歌词词首字母也是 A-G,形状对不上即拒。
    // (Dart 侧的同类判定见 core/chart/cifra_extract.dart 的
    // _chordTokenRe——两处判的是同一个问题,改动请两边对齐。)
    var CHORD_SHAPE = /^[A-G][#b]?(m|maj|min|dim|aug|sus|add|M)?[0-9()#b+-]*(\\/[A-G][0-9()#b+-]*)?\$/;
    function looksChord(el) {
      if (el.getAttribute('data-chord-name')
        || el.getAttribute('data-chord-original-text')) {
        // data-* 属性是站点自己标的(调研:类名混淆只有 data-* 稳定),直接信。
        var d = chordNameOf(el);
        return d.length > 0 && d.length <= 24;
      }
      var n = chordNameOf(el);
      return n.length > 0 && n.length <= 24 && CHORD_SHAPE.test(n);
    }
    var pre = document.querySelector('pre[data-chord-content]');
    if (!pre) {
      var pres = document.querySelectorAll('pre');
      var best = null, bestCount = 0;
      for (var i = 0; i < pres.length; i++) {
        var count = pres[i].querySelectorAll('b').length;
        if (count > bestCount) { best = pres[i]; bestCount = count; }
      }
      pre = best;
    }
    if (!pre) return JSON.stringify({error: 'no-content'});
    var lines = [], cur = [];
    function flush() { lines.push(cur); cur = []; }
    function walk(node) {
      switch (node.nodeType) {
        case 3:
          var parts = (node.nodeValue || '').split('\\n');
          for (var i = 0; i < parts.length; i++) {
            if (i > 0) flush();
            if (parts[i].length) cur.push(parts[i]);
          }
          break;
        case 1:
          var tag = node.tagName;
          if (tag === 'BR') { flush(); break; }
          if (tag === 'B' && looksChord(node)) {
            cur.push({c: chordNameOf(node), s: node.textContent || ''});
            break;
          }
          if (tag === 'SCRIPT' || tag === 'STYLE') break;
          if (tag === 'DIV') { flush(); }
          for (var c = node.firstChild; c; c = c.nextSibling) walk(c);
          if (tag === 'DIV') { flush(); }
          break;
      }
    }
    for (var n = pre.firstChild; n; n = n.nextSibling) walk(n);
    flush();
    var hasChord = false;
    for (var l = 0; l < lines.length && !hasChord; l++) {
      for (var s = 0; s < lines[l].length; s++) {
        if (typeof lines[l][s] === 'object') { hasChord = true; break; }
      }
    }
    if (!hasChord) return JSON.stringify({error: 'no-chords'});
    var title = null, artist = null;
    try {
      var lds = document.querySelectorAll('script[type="application/ld+json"]');
      for (var j = 0; j < lds.length; j++) {
        var data = JSON.parse(lds[j].textContent);
        var rec = (data && data['@type'] === 'MusicRecording')
          ? data
          : (data && data.mainEntity && data.mainEntity['@type'] === 'MusicRecording'
            ? data.mainEntity : null);
        if (rec && rec.name) {
          title = rec.name;
          artist = (rec.byArtist && rec.byArtist.name) ? rec.byArtist.name : null;
          break;
        }
      }
    } catch (e) {}
    if (!title) {
      var parts = (document.title || '').split(' - ');
      if (parts.length >= 3) { title = parts[0].trim(); artist = parts[1].trim(); }
      else if (parts.length === 2) { title = parts[0].trim(); }
    }
    return JSON.stringify({title: title, artist: artist, lines: lines});
  } catch (e) {
    return JSON.stringify({error: 'exception: ' + (e && e.message ? e.message : String(e))});
  }
})()
''';
