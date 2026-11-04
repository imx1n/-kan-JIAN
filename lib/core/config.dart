/// 数据源与网络配置。
class AppConfig {
  AppConfig._();

  /// 按顺序尝试；`results == null` 视为被拦，自动换下一个主机。
  static const apiHosts = <String>[
    'https://www.manga2026.xyz', // 首选：无签名校验
    'https://api.copy202601.com', // 兜底（目前会返回 results:null）
  ];

  /// 全链路通用请求头（缺任何一项都会静默返回空列表）。
  static const apiHeaders = <String, String>{
    'User-Agent': 'COPY/3.1.0',
    'source': 'copyApp',
    'platform': '3',
    'region': '0',
    'version': '3.1.0',
    'versioncode': '84',
    'accept': 'application/json',
    'referer': 'com.copymanga.app-3.1.0',
  };

  /// 网页端主机：账号登录走这里（App 端登录需要额外的加密值，没有打通）。
  static const webHost = 'https://www.copy4000.com';

  static const imageHeaders = <String, String>{'User-Agent': 'COPY/3.1.0'};

  /// 编译期默认代理，例如 MuMu 内访问宿主机 Clash：
  /// `flutter run --dart-define=PROXY=10.0.2.2:7897`
  static const defaultProxy = String.fromEnvironment('PROXY');

  /// 应用更新从这个仓库的 GitHub Releases 获取。
  static const githubRepo = 'luminacry/-kan-JIAN';
  static const githubPage = 'https://github.com/$githubRepo';
  static const releasesApi = 'https://api.github.com/repos/$githubRepo/releases/latest';

  /// 题材筛选（`/api/v3/comics?theme=`）。名称与 path_word 取自 `filter/book/tags`，漫画列表同样适用。
  static const themes = <(String, String)>[
    ('愛情', 'aiqing'), ('校園', 'xiaoyuan'), ('奇幻', 'qihuan'), ('青春', 'qingchun'), ('後宮', 'hougong'),
    ('戰鬥', 'zhandou'), ('歡樂向', 'huanlexiang'), ('冒險', 'maoxian'), ('懸疑', 'xuanyi'), ('科幻', 'kehuan'),
    ('穿越', 'chuanyue'), ('青梅竹馬', 'qingmeizhuma'), ('人外', 'renwai'), ('魔法', 'mofa'), ('百合', 'baihe'),
  ];
}
