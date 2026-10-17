/// Cifra Club 搜索的页内脚本(工单 27)。
///
/// 真机逆向(2026-10-17,工单 27 机检 dump):站点已是 Next.js SPA,
/// `/busca/?q=` 直载是 404 壳;搜索浮层由站点自家代码在**页内**向
/// `https://solr.sscdn.co/cc/c7/?q=<q>&limit=30` 发请求取结构化 JSON
/// (Solr 形状,响应头 `access-control-allow-origin: *`)。本文件照
/// 抄该端点:在 WebView 当前页里 fetch——一切提取只在 WebView 里发生
/// (ADR-0002 不破:站点主域从不被 Dart 侧直连,搜索也不导航)。
///
/// 响应 doc 字段(实证):`txt` 歌名、`art` 艺人、`dns` 艺人 slug、
/// `url` 歌曲 slug、`tipo` 条目类型('2'=Música 歌页、'6'=Álbum 专辑,
/// 专辑页对导入管线无用,过滤)。
///
/// 契约(decodeCifraSearchPayload 消费):
/// - start 脚本:kick 页内 fetch,结果写 `window.__ukeSearch`(JSON
///   字符串);页内 `__ukeSeq` 自防——新一轮搜索自增 seq,旧 fetch
///   落地时发现 seq 已变就丢弃,不会覆盖新搜索的结果。
/// - poll 脚本:读 `window.__ukeSearch`,没有/还没写 → `pending`。
///   终态:`{"status":"ok","hits":[{t,a,u}]}`(u=站内路径)或
///   `{"status":"zero"}`(命中为空)。
///   fetch 失败(网络/端点失效)→ `pending`,由编排的 re-kick/超时
///   收口成「搜索失败」。
library;

import 'dart:convert';

/// kick 脚本:启动对 solr 端点的页内 fetch。[query] 按调用时刻的查询词
/// JSON 编码内嵌(安全经桥传递)。
String cifraSearchStartScript(String query) => '''
(function() {
  try {
    var q = ${jsonEncode(query)};
    window.__ukeSeq = (window.__ukeSeq || 0) + 1;
    var seq = window.__ukeSeq;
    window.__ukeSearch = null;
    fetch('https://solr.sscdn.co/cc/c7/?limit=30&q=' + encodeURIComponent(q))
      .then(function(r) { return r.json(); })
      .then(function(j) {
        if (window.__ukeSeq !== seq) return;
        var docs = (j.response && j.response.docs) || [];
        var hits = [];
        for (var i = 0; i < docs.length; i++) {
          var d = docs[i];
          if (String(d.tipo) !== '2') continue;
          if (!d.dns || !d.url || !d.txt) continue;
          hits.push({t: String(d.txt), a: d.art ? String(d.art) : null,
            u: '/' + d.dns + '/' + d.url + '/'});
        }
        window.__ukeSearch = JSON.stringify(hits.length
          ? {status: 'ok', hits: hits}
          : {status: 'zero'});
      })
      .catch(function(e) {
        if (window.__ukeSeq !== seq) return;
        window.__ukeSearch = JSON.stringify({status: 'pending'});
      });
    return JSON.stringify({status: 'started'});
  } catch (e) {
    return JSON.stringify({error: 'exception: ' + (e && e.message ? e.message : String(e))});
  }
})()
''';

/// 轮询脚本:读 start 脚本的落点,没写就是 pending。
const cifraSearchPollScript = '''
(function() {
  try {
    var v = window.__ukeSearch;
    return v == null ? JSON.stringify({status: 'pending'}) : v;
  } catch (e) {
    return JSON.stringify({error: 'exception: ' + (e && e.message ? e.message : String(e))});
  }
})()
''';
