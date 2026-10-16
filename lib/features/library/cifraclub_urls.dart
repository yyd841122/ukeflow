/// Cifra Club 站内 URL 形态判定(工单 17)。
///
/// 防御式纪律:站点导航词表由调研(2026-10-08 实抓首页导航)+常见站务词
/// 组成,漏网路径顶多是导入钮多出现一次、提取失败给可读报错——宁可
/// 少拦,不可误拦曲谱页。
library;

class CifraClubUrls {
  CifraClubUrls._();

  static const _host = 'cifraclub.com.br';

  static final Uri home = Uri.parse('https://www.cifraclub.com.br/');

  /// 站内搜索结果页(站点自带搜索表单也是跳这个形态)。
  static Uri search(String query) => Uri.parse(
    'https://www.cifraclub.com.br/busca/',
  ).replace(queryParameters: {'q': query});

  /// 搜索框输入解析(工单 17「链接导入」半边):像 http(s) 链接的输入
  /// 原样返回供 WebView 加载(粘 Cifra Club 链接直达曲谱页,含
  /// /ukulele/ 乐器版本);其余(关键词、非 http(s) scheme)返回 null
  /// 走站内搜索——scheme 白名单挡掉 javascript:/file: 之类注入面。
  static Uri? linkOrNull(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// 顶层站务/功能路径:这些开头的两段路径不是「艺人/歌曲」。
  static const _reservedTop = {
    'busca', 'assine', 'pro', 'academy', 'afinador', 'metronomo', 'blog',
    'noticias', 'novidades', 'estilos', 'mais-acessadas', 'pedir-videoaula',
    'videos', 'enviar', 'artistas', 'user', 'account', 'login', 'logout',
    'signup', 'api', 'loja', 'playlist', 'listas', 'albuns', 'album', 'app',
    'sobre', 'contato', 'privacy', 'termos', 'static', 'assets', 'jobs',
  };

  /// 曲谱页路径的第二段之后的已知后缀(备选版本页/乐器版本页)。
  static const _songSuffixes = {
    'versao',
    'ukulele', 'guitarra', 'violao', 'teclado', 'cavaco', 'baixo', 'bateria',
    'gaita', 'partitura',
  };

  /// ukulele 版变体 URL(导入优先取 ukulele 版,工单 17 用户反馈:版本
  /// 管理不该甩给用户):两段标准曲谱页拼 `/ukulele/` 后缀(存档索引证实
  /// 的形态,如 /1kilo/deixe-me-ir/ukulele/),查询串不带过去。
  /// 已是 ukulele 页、versao 变体页、非两段页 → null(不猜变体;
  /// 没有 ukulele 版的歌由调用方回退原版并告知)。
  static Uri? ukuleleVariant(Uri songUrl) {
    final segments =
        songUrl.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length != 2) return null;
    if (_reservedTop.contains(segments[0].toLowerCase())) return null;
    if (segments[1].toLowerCase() == 'ukulele') return null;
    final path = '${segments.join('/')}/ukulele/';
    // 重建干净 URL(Uri.replace 的 query:null 是「保留」,去不掉查询串)。
    return Uri(scheme: songUrl.scheme, host: songUrl.host, path: path);
  }

  /// 是否曲谱页(显示「导入此谱」的页面):cifraclub 域名下路径至少
  /// 「艺人/歌曲」两段,首两段不撞站务词,无文件名段。
  static bool isSongPage(Uri url) {
    // 整段等值或点分后缀——endsWith 裸判定会放行 x-cifraclub.com.br
    // 这类仿冒域(ADR-0002:仅 Cifra Club,无通用网页导入)。
    final host = url.host.toLowerCase();
    if (host != _host && !host.endsWith('.$_host')) return false;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return false;
    if (segments.any((s) => s.contains('.'))) return false;
    final top = segments[0].toLowerCase();
    if (_reservedTop.contains(top)) return false;
    if (_reservedTop.contains(segments[1].toLowerCase())) return false;
    if (segments.length == 2) return true;
    return segments.skip(2).every(
      (s) =>
          _songSuffixes.contains(s.toLowerCase()) ||
          int.tryParse(s) != null, // versao/versao 后的数字 id 均已在表/整型判定内。
    );
  }
}
