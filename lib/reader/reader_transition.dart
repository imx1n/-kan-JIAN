import 'package:flutter/cupertino.dart';

import '../ui/icons.dart';
import '../ios/ios_theme.dart';
import 'reader_models.dart';

/// 跨话过渡页。放在上一话末页之后、下一话首页之前。
///
/// 阅读器把三话的页拼成一条连续列表（上一话的页 → 过渡页 → 当前话的页 →
/// 过渡页 → 下一话的页），所以「读完本话弹卡片点一下」的断点没了：这张卡只在
/// 目标话还没载入完、载入失败、或全书读完时才真正露面，其余时候一闪而过。
///
/// 颜色一律用深色阅读器的 [IosColors] 常量（d 系列），因为阅读区本身就是深色，
/// 不跟系统浅色模式走。
class ReaderTransition extends StatelessWidget {
  const ReaderTransition({
    super.key,
    required this.transition,
    this.onOpenChapter,
    this.onRetry,
    this.onCatalog,
    this.onBackToChapter,
    this.continuous = false,
  });

  final ChapterTransition transition;

  /// 点「接着读」时打开目标话（传 uuid）。
  final ValueChanged<String>? onOpenChapter;

  /// 目标话载入失败时的重试。
  final ValueChanged<ReaderChapter>? onRetry;

  final VoidCallback? onCatalog;
  final VoidCallback? onBackToChapter;

  /// 条漫里用（上下留白更大）。
  final bool continuous;

  @override
  Widget build(BuildContext context) {
    final to = transition.to;
    final List<Widget> children;
    if (to == null) {
      // 没有下一话：收尾页。`to` 为 null 只出现在 NextTransition 上
      //（PrevTransition 的 to 永远是上一话本身）。
      children = _end();
    } else if (to.state == ChapterState.loading) {
      children = _loading(to);
    } else if (to.state == ChapterState.error) {
      children = _error(to);
    } else {
      // 已载入 / 还没开始载入：普通过渡，条漫里会短暂滚过。
      children = _plain(to);
    }

    final box = SizedBox.expand(
      child: ColoredBox(
        color: IosColors.dBg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: children),
          ),
        ),
      ),
    );
    // 条漫里上下留白更大，卡片不贴着上一页的图。
    return continuous ? Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: box) : box;
  }

  /// 全书读完。
  List<Widget> _end() {
    final from = transition.from;
    return [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: IosColors.dMuted, width: 1.2)),
        child: const AppIcon('check', size: 18, color: IosColors.dInk, stroke: 2),
      ),
      const SizedBox(height: 14),
      const Text('阅读完成', style: TextStyle(fontSize: 13, color: IosColors.dMuted)),
      const SizedBox(height: 10),
      Text.rich(
        TextSpan(children: [
          TextSpan(text: from.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: IosColors.dInk)),
          const TextSpan(text: ' 完', style: TextStyle(fontSize: 28, color: IosColors.dMuted)),
        ]),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      Text('本话 ${from.pages?.length ?? 0} 页', style: const TextStyle(fontSize: 13, color: IosColors.dMuted)),
      const SizedBox(height: 4),
      const Text('已经是最新一话', style: TextStyle(fontSize: 15, color: IosColors.dMuted)),
      const SizedBox(height: 26),
      _capsule(),
    ];
  }

  /// 收尾页底部的两出口胶囊：返回本话 / 目录。
  Widget _capsule() => Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0x1FFFFFFF),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _capsuleItem('返回本话', onBackToChapter),
          Container(width: 0.5, height: 22, color: const Color(0x33FFFFFF)),
          _capsuleItem('目录', onCatalog),
        ]),
      );

  Widget _capsuleItem(String label, VoidCallback? onTap) => Pressable(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Center(child: Text(label, style: const TextStyle(fontSize: 15, color: IosColors.dInk))),
          ),
        ),
      );

  /// 下一话正在载入。
  List<Widget> _loading(ReaderChapter to) => [
        const CupertinoActivityIndicator(color: IosColors.dMuted, radius: 12),
        const SizedBox(height: 14),
        const Text('正在载入下一话', style: TextStyle(fontSize: 15, color: IosColors.dMuted)),
        if (to.name.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(to.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: IosColors.dInk)),
        ],
      ];

  /// 下一话载入失败。
  List<Widget> _error(ReaderChapter to) => [
        const Text('下一话没有载入', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: IosColors.dInk)),
        const SizedBox(height: 8),
        Text(
          to.error ?? '',
          maxLines: 3,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: IosColors.dMuted),
        ),
        const SizedBox(height: 20),
        Pressable(
          onTap: () => onRetry?.call(to),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: const Text('重试', style: TextStyle(fontSize: 15, color: IosColors.dInk)),
          ),
        ),
      ];

  /// 普通过渡：只说清接下来是哪一话。
  List<Widget> _plain(ReaderChapter to) => [
        Text(
          transition is PrevTransition ? '上一话已读完' : '下一话',
          style: const TextStyle(fontSize: 15, color: IosColors.dMuted),
        ),
        if (to.name.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(to.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: IosColors.dInk)),
        ],
      ];
}
