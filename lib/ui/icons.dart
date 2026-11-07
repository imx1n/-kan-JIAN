import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 线性图标：24×24 视框、圆头描边。
const _paths = <String, String>{
  'search': '<circle cx="10.8" cy="10.8" r="6.8"/><path d="m16 16 4.5 4.5"/>',
  'left': '<path d="m14.5 5-7 7 7 7"/>',
  'right': '<path d="m9 5 7 7-7 7"/>',
  'arrow': '<path d="M4 12h15m-6-6 6 6-6 6"/>',
  'book': '<path d="M3 4.5c3.5-.8 6.5.2 9 2 2.5-1.8 5.5-2.8 9-2V20c-3.5-.8-6.5.2-9 2-2.5-1.8-5.5-2.8-9-2zM12 6.5V22"/>',
  'person': '<circle cx="12" cy="7.5" r="3.5"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
  'more': '<circle cx="5" cy="12" r="1" fill="#000"/><circle cx="12" cy="12" r="1" fill="#000"/><circle cx="19" cy="12" r="1" fill="#000"/>',
  'bookmark': '<path d="M6 3h12v19l-6-4-6 4z"/>',
  'bookmarkFilled': '<path d="M6 3h12v19l-6-4-6 4z" fill="#000"/>',
  'list': '<path d="M8 5h13M8 12h13M8 19h13M3 5h.1M3 12h.1M3 19h.1"/>',
  'down': '<path d="m6 9 6 6 6-6"/>',
  'check': '<path d="m5 12 4 4L19 6"/>',
  'expand': '<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/>',
  'sun': '<circle cx="12" cy="12" r="4"/><path d="M12 1v2m0 18v2M1 12h2m18 0h2M4.2 4.2l1.4 1.4m12.8 12.8 1.4 1.4m0-15.6-1.4 1.4M5.6 18.4l-1.4 1.4"/>',
  'grid': '<rect x="3.5" y="3.5" width="6" height="6" rx="1.5"/><rect x="14.5" y="3.5" width="6" height="6" rx="1.5"/><rect x="3.5" y="14.5" width="6" height="6" rx="1.5"/><rect x="14.5" y="14.5" width="6" height="6" rx="1.5"/>',
  'close': '<path d="m6 6 12 12M18 6 6 18"/>',
  'type': '<path d="M4 5h12M10 5v15M6 20h8M4 5v3m12-3v3M18 12h3m-3 4h3m-3 4h3"/>',
  'previous': '<path d="M6 5v14m12-14L9 12l9 7z"/>',
  'next': '<path d="M18 5v14M6 5l9 7-9 7z"/>',
  'minus': '<path d="M5 12h14"/>',
  'plus': '<path d="M5 12h14M12 5v14"/>',
  'sort': '<path d="M7 4v16m0 0-3-3m3 3 3-3M17 20V4m0 0-3 3m3-3 3 3"/>',
  'compass': '<circle cx="12" cy="12" r="9"/><path d="m15.8 8.2-2.4 5.2-5.2 2.4 2.4-5.2z"/>',
  'moreV': '<circle cx="12" cy="5" r="1.1" fill="#000"/><circle cx="12" cy="12" r="1.1" fill="#000"/><circle cx="12" cy="19" r="1.1" fill="#000"/>',
  'back': '<path d="M20 12H5m6-6-6 6 6 6"/>',
  'locate': '<circle cx="12" cy="12" r="3.2"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/><circle cx="12" cy="12" r="7"/>',
  'direction': '<path d="M20 7H5m4-4L5 7l4 4M4 17h15m-4-4 4 4-4 4"/>',
  'image': '<rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="1.8"/><path d="m21 16-5-5-9 9"/>',
  'download': '<path d="M12 3v12m-5-5 5 5 5-5"/><path d="M4 16v3a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-3"/>',
  'github': '<path d="M9 19c-4.3 1.4-4.3-2.5-6-3m12 5v-3.5c0-1 .1-1.4-.5-2 2.8-.3 5.5-1.4 5.5-6a4.6 4.6 0 0 0-1.3-3.2 4.2 4.2 0 0 0-.1-3.2s-1.1-.3-3.5 1.3a12.3 12.3 0 0 0-6.2 0C6.5 2.8 5.4 3.1 5.4 3.1a4.2 4.2 0 0 0-.1 3.2A4.6 4.6 0 0 0 4 9.5c0 4.6 2.7 5.7 5.5 6-.6.6-.6 1.2-.5 2V21"/>',
  'wifiOff': '<path d="M2 8.8a15 15 0 0 1 5.3-3.1M10.7 5a15 15 0 0 1 11.3 3.8M5 12.5a10 10 0 0 1 3.8-2.3M15.5 10.4A10 10 0 0 1 19 12.5M8.5 16a5 5 0 0 1 7 0M12 20h.01M3 3l18 18"/>',
  'history': '<path d="M3.5 12a8.5 8.5 0 1 0 2.5-6M3 4v4.5h4.5"/><path d="M12 7.5V12l3 2"/>',
  'database': '<ellipse cx="12" cy="5.5" rx="7.5" ry="2.8"/><path d="M4.5 5.5v13c0 1.5 3.4 2.8 7.5 2.8s7.5-1.3 7.5-2.8v-13M4.5 12c0 1.5 3.4 2.8 7.5 2.8s7.5-1.3 7.5-2.8"/>',
  'route': '<circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="6" r="2.5"/><path d="M8.5 18H15a3.5 3.5 0 0 0 0-7H9a3.5 3.5 0 0 1 0-7h6.5"/>',
  'play': '<path d="M7 4.5v15l12.5-7.5z" fill="#000"/>',
  // iOS：SF Symbols 风格；选中的标签用实心（镂空用 evenodd，避免着色后细节消失）
  'chevronLeft': '<path d="m15 4.5-7.5 7.5 7.5 7.5" stroke-width="2.1"/>',
  'chevronRight': '<path d="m9 5 7 7-7 7" stroke-width="2"/>',
  'ellipsis': '<circle cx="5.5" cy="12" r="1.6" fill="#000" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="#000" stroke="none"/><circle cx="18.5" cy="12" r="1.6" fill="#000" stroke="none"/>',
  'xmark': '<path d="m7 7 10 10M17 7 7 17" stroke-width="2"/>',
  'settings': '<path d="M4 6h4m5 0h7M4 12h10m5 0h1M4 18h2m5 0h9"/><circle cx="10.5" cy="6" r="2.5"/><circle cx="16.5" cy="12" r="2.5"/><circle cx="8.5" cy="18" r="2.5"/>',
  'bookFill': '<path fill="#000" stroke="none" d="M3 4.5c3.5-.8 6.5.2 8.3 1.5v15.4C8.8 19.8 6 19.3 3 20zM12.7 6c2.3-1.3 5.3-2.3 8.3-1.5V20c-3-.7-5.8-.2-8.3 1.4z"/>',
  'compassFill': '<path fill="#000" fill-rule="evenodd" stroke="none" d="M12 2.5a9.5 9.5 0 1 0 0 19 9.5 9.5 0 0 0 0-19zm3.8 5.7-2.4 5.2-5.2 2.4 2.4-5.2z"/>',
  'personFill': '<circle cx="12" cy="7.5" r="4" fill="#000" stroke="none"/><path d="M3.5 21.5v-1.5a8.5 8.5 0 0 1 17 0v1.5z" fill="#000" stroke="none"/>',
  'pages': '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M12 3v18"/>',
  'scroll': '<rect x="6" y="2.5" width="12" height="8" rx="1.5"/><rect x="6" y="13.5" width="12" height="8" rx="1.5"/>',
  'lock': '<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  'refresh': '<path d="M20 11a8 8 0 1 0-2.3 5.7M20 4v7h-7"/>',
  'trend': '<path d="m3 17 6-6 4 4 8-8M15 7h6v6"/>',
  'globe': '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.7 5.6 3.7 9s-1.2 6.4-3.7 9c-2.5-2.6-3.7-5.6-3.7-9S9.5 5.6 12 3z"/>',
  'trash': '<path d="M4 7h16M10 11v6m4-6v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  'info': '<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5h.01"/>',
  'clock': '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  // 阅读方式：圆角纸页 + 粗箭头（卡通式，实心浅填充）
  'modeLtr': '<rect x="2.8" y="4.4" width="9" height="15.2" rx="3.2" fill="#000" fill-opacity=".2" stroke-width="1.7"/><path d="M14.6 12h6.4m-2.9-2.9L21 12l-2.9 2.9" stroke-width="2.1"/>',
  'modeRtl': '<rect x="12.2" y="4.4" width="9" height="15.2" rx="3.2" fill="#000" fill-opacity=".2" stroke-width="1.7"/><path d="M9.4 12H3m2.9-2.9L3 12l2.9 2.9" stroke-width="2.1"/>',
  'modeTtb': '<rect x="4.4" y="2.8" width="15.2" height="9" rx="3.2" fill="#000" fill-opacity=".2" stroke-width="1.7"/><path d="M12 14.6v6.4m-2.9-2.9L12 21l2.9-2.9" stroke-width="2.1"/>',
  'modeBtt': '<rect x="4.4" y="12.2" width="15.2" height="9" rx="3.2" fill="#000" fill-opacity=".2" stroke-width="1.7"/><path d="M12 9.4V3m-2.9 2.9L12 3l2.9 2.9" stroke-width="2.1"/>',
  'modeWebtoon': '<rect x="3.6" y="2.8" width="16.8" height="5.6" rx="2.8" fill="#000" fill-opacity=".2" stroke-width="1.5"/><rect x="3.6" y="9.2" width="16.8" height="5.6" rx="2.8" fill="#000" fill-opacity=".2" stroke-width="1.5"/><rect x="3.6" y="15.6" width="16.8" height="5.6" rx="2.8" fill="#000" fill-opacity=".2" stroke-width="1.5"/>',
  'modeStrip': '<rect x="3.6" y="2.6" width="16.8" height="5" rx="2.5" fill="#000" fill-opacity=".2" stroke-width="1.5"/><rect x="3.6" y="9.5" width="16.8" height="5" rx="2.5" fill="#000" fill-opacity=".2" stroke-width="1.5"/><rect x="3.6" y="16.4" width="16.8" height="5" rx="2.5" fill="#000" fill-opacity=".2" stroke-width="1.5"/>',
};

final _cache = <String, String>{};

class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size = 24, this.color, this.stroke = 1.65});

  final String name;
  final double size;
  final Color? color;
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final svg = _cache.putIfAbsent(
      '$name@$stroke',
      () => '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" '
          'stroke-width="$stroke" stroke-linecap="round" stroke-linejoin="round">${_paths[name] ?? ''}</svg>',
    );
    final c = color ?? IconTheme.of(context).color ?? const Color(0xFF17181C);
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}
