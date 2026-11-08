import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'reader_theme.dart';
import 'reading_mode.dart';

/// 阅读方式的示意图标：三色纸页 + 深色箭头。
///
/// 不能用 [AppIcon]——那个走 `ColorFilter.srcIn` 单色着色，画不出「底页 / 正面
/// 纸 / 卷角」三层。这里按设计稿的 SVG 直接拼字面颜色，跟着主题和选中态换一套。
///
/// 造型来自设计稿 `reader-settings/index.html` 的 `mode-pages` 等符号：
/// 40×40 视框，纸页圆角 4，箭头粗 2.4、圆头。
class ModeGlyph extends StatelessWidget {
  const ModeGlyph({super.key, required this.mode, this.selected = false, this.size = ReaderPalette.tileGlyph});

  final ReadingMode mode;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = _GlyphColors.of(selected);
    final svg = _cache.putIfAbsent('${mode.name}@${selected ? 1 : 0}', () => _build(mode, colors));
    return SvgPicture.string(svg, width: size, height: size);
  }

  /// 同一张图在深浅色之间只有颜色不同，缓存键带上选中态就够了；
  /// 主题切换时整棵树重建，颜色靠 `ReaderPalette` 的 getter 重新求值。
  static final _cache = <String, String>{};

  static String _build(ReadingMode mode, _GlyphColors c) {
    final body = switch (mode) {
      // 从右向左就是整张图水平镜像，和设计稿的写法一致。
      ReadingMode.leftToRight => _pages(c),
      ReadingMode.rightToLeft => '<g transform="translate(40) scale(-1 1)">${_pages(c)}</g>',
      ReadingMode.vertical => _down(c),
      ReadingMode.verticalReversed => _up(c),
      ReadingMode.webtoon => _scroll(c, gap: false),
      ReadingMode.continuousVertical => _scroll(c, gap: true),
    };
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40">$body</svg>';
  }

  /// 横向翻页：一摞纸 + 一条从左掠到右的弧线箭头。
  static String _pages(_GlyphColors c) =>
      '<rect x="4" y="7" width="17" height="27" rx="4" transform="rotate(-8 12 20)" fill="${c.back}"/>'
      '<path d="M22 5h7l7 7v19a4 4 0 0 1-4 4H22a4 4 0 0 1-4-4V9a4 4 0 0 1 4-4Z" fill="${c.paper}"/>'
      '<path d="M29 5v5a2 2 0 0 0 2 2h5" fill="${c.tab}"/>'
      '<path d="M23 17h6M8 13h4" opacity=".35" fill="none" stroke="${c.ink}" stroke-width="1.65" stroke-linecap="round"/>'
      '<path d="M8 23c7 5 15 5 22 0m-5-1 5 1-1 5" fill="none" stroke="${c.ink}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>';

  /// 纵向向下：横放的纸摞 + 一路向下的箭头。
  static String _down(_GlyphColors c) =>
      '<rect x="7" y="3" width="22" height="18" rx="4" transform="rotate(-7 18 12)" fill="${c.back}"/>'
      '<path d="M12 16h12l6 6v11a4 4 0 0 1-4 4H12a4 4 0 0 1-4-4V20a4 4 0 0 1 4-4Z" fill="${c.paper}"/>'
      '<path d="M24 16v4a2 2 0 0 0 2 2h4" fill="${c.tab}"/>'
      '<path d="M14 9h6" opacity=".35" fill="none" stroke="${c.ink}" stroke-width="1.65" stroke-linecap="round"/>'
      '<path d="M17 12c-3 5-3 12 0 18m-5-3 5 3 3-5" fill="none" stroke="${c.ink}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>';

  /// 纵向向上：`_down` 的垂直镜像，箭头朝上。
  static String _up(_GlyphColors c) =>
      '<rect x="7" y="20" width="22" height="17" rx="4" transform="rotate(7 18 28)" fill="${c.back}"/>'
      '<path d="M12 3h12l6 6v11a4 4 0 0 1-4 4H12a4 4 0 0 1-4-4V7a4 4 0 0 1 4-4Z" fill="${c.paper}"/>'
      '<path d="M24 3v4a2 2 0 0 0 2 2h4" fill="${c.tab}"/>'
      '<path d="M14 31h6" opacity=".3" fill="none" stroke="${c.ink}" stroke-width="1.65" stroke-linecap="round"/>'
      '<path d="M17 29c3-5 3-12 0-18m-3 5 3-5 5 3" fill="none" stroke="${c.ink}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>';

  /// 条漫：一整条画格 + 右侧向下的箭头。
  ///
  /// [gap] 为真时画格之间留白（「条漫 · 留白」），为假时首尾相接（「无缝」）。
  /// 两种模式在真机上确实是这个差别，图标也就照实画。
  static String _scroll(_GlyphColors c, {required bool gap}) =>
      '<path d="M11 3h14a4 4 0 0 1 4 4v26a4 4 0 0 1-4 4H11a4 4 0 0 1-4-4V7a4 4 0 0 1 4-4Z" fill="${c.paper}"/>'
      '${gap ? '<rect x="11" y="8" width="14" height="8" rx="2" fill="${c.back}"/><rect x="11" y="20" width="14" height="9" rx="2" fill="${c.back}"/>' : '<rect x="11" y="7" width="14" height="11" rx="2" fill="${c.back}"/><rect x="11" y="18" width="14" height="11" rx="2" fill="${c.back}"/>'}'
      '<path d="M12 33h9" opacity=".3" fill="none" stroke="${c.ink}" stroke-width="1.65" stroke-linecap="round"/>'
      '<path d="M19 8h6v5Z" fill="${c.tab}"/>'
      '<path d="M34 12v17m-4-4 4 4 4-4" fill="none" stroke="${c.arrow}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>';
}

/// 一套图标配色。选中时纸页整体提亮一档，箭头压深。
class _GlyphColors {
  const _GlyphColors({required this.paper, required this.back, required this.tab, required this.ink, required this.arrow});

  final String paper;
  final String back;
  final String tab;
  final String ink;
  final String arrow;

  /// 条漫那个箭头画在纸页外面（背板上），所以单独一色，不能跟着纸页走。
  static _GlyphColors of(bool selected) => selected
      ? _GlyphColors(
          paper: _hex(ReaderPalette.iconSelectedPaper),
          back: _hex(ReaderPalette.iconSelectedBack),
          tab: _hex(ReaderPalette.iconSelectedTab),
          ink: _hex(ReaderPalette.iconSelectedInk),
          arrow: _hex(ReaderPalette.selectedInk),
        )
      : _GlyphColors(
          paper: _hex(ReaderPalette.iconPaper),
          back: _hex(ReaderPalette.iconBack),
          tab: _hex(ReaderPalette.iconTab),
          ink: _hex(ReaderPalette.iconInk),
          arrow: _hex(ReaderPalette.iconInk),
        );

  static String _hex(Color c) {
    final v = c.toARGB32() & 0xFFFFFF;
    return '#${v.toRadixString(16).padLeft(6, '0')}';
  }
}
