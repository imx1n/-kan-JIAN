import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastemangax/ui/motion.dart';

/// 记录 initState 次数：被重新挂载就会多一次。
class _Probe extends StatefulWidget {
  const _Probe({required this.onInit});

  final VoidCallback onInit;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}

Widget _launcher(Route<void> Function() route) => MaterialApp(
      home: Builder(builder: (c) => TextButton(onPressed: () => Navigator.of(c).push(route()), child: const Text('go'))),
    );

void main() {
  final both = TargetPlatformVariant.only(TargetPlatform.iOS)..values.add(TargetPlatform.android);

  testWidgets('页面转场结束后不重新挂载（状态保留）', (t) async {
    var inits = 0;
    await t.pumpWidget(_launcher(() => appRoute((_) => _Probe(onInit: () => inits++))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('probe'), findsOneWidget);
    expect(inits, 1);
  }, variant: both);

  testWidgets('阅读器转场结束后不重新挂载', (t) async {
    var inits = 0;
    await t.pumpWidget(_launcher(() => readerRoute((_) => _Probe(onInit: () => inits++))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(inits, 1);
  }, variant: both);

  testWidgets('面板：进出动画结束不重新挂载，下拉超过阈值会关闭', (t) async {
    var inits = 0;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showAppSheet<void>(c, (_) => SizedBox(height: 300, width: double.infinity, child: _Probe(onInit: () => inits++))),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(inits, 1);
    await t.drag(find.text('probe'), const Offset(0, 200));
    await t.pumpAndSettle();
    expect(find.text('probe'), findsNothing);
  });

  testWidgets('首次进入动画结束后不重新挂载', (t) async {
    var inits = 0;
    await t.pumpWidget(MaterialApp(home: FadeSlideIn(delayMs: 45, child: _Probe(onInit: () => inits++))));
    await t.pumpAndSettle();
    expect(inits, 1);
  });

  testWidgets('Android 时长取 iOS 的 85%', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(Motion.ms(320), const Duration(milliseconds: 272));
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(Motion.ms(320), const Duration(milliseconds: 320));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('系统减少动态时时长为 0', (t) async {
    late Duration d;
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Builder(builder: (c) {
        d = Motion.of(c, 300);
        return const SizedBox();
      }),
    ));
    expect(d, Duration.zero);
  });

  testWidgets('搜索页：进场 260 / 退场 160，退场更快', (t) async {
    final route = searchRoute<void>((_) => const SizedBox()) as PageRoute<void>;
    expect(route.transitionDuration, Motion.ms(260));
    expect(route.reverseTransitionDuration, Motion.ms(160));
    expect(route.reverseTransitionDuration, lessThan(route.transitionDuration));
  });

  testWidgets('搜索页：从触发点展开，结束后铺满且不重新挂载', (t) async {
    var inits = 0;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (c) => Align(
          alignment: Alignment.bottomRight,
          child: SizedBox(
            width: 56,
            height: 56,
            child: TextButton(
              onPressed: () => Navigator.of(c).push(searchRoute((_) => _Probe(onInit: () => inits++), origin: rectOf(c))),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    // 转场结束：页面在、且只挂载过一次（没被结构变化重建）
    expect(find.text('probe'), findsOneWidget);
    expect(inits, 1);
    // 结束时缩放必须是 1：留在 0.92 就是整页永远偏小
    final scales = t.widgetList<Transform>(find.byType(Transform)).map((w) => w.transform.getMaxScaleOnAxis()).toList();
    expect(scales.every((s) => (s - 1).abs() < 0.001), isTrue);
  });
}
