import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastemangax/core/store.dart';
import 'package:pastemangax/ui/cover_frame.dart';
import 'package:pastemangax/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 封面书本框是纯绘制层，widget 测试里也会走一遍 paint，
/// 尺寸极值（40px 行内封面、1080 宽的平板封面）都不能抛异常。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 偏好写入默认去抖 320ms，用例结束时会挂着定时器。
    ReaderPrefs.debounce = false;
    await initStores();
  });
  tearDown(() => ReaderPrefs.debounce = true);

  Future<void> render(WidgetTester tester, double w) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: CoverImage(url: 'sample:雨停之前', width: w, height: coverHeightFor(w)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('封面框：默认关闭时不挂绘制层', (tester) async {
    ReaderPrefs.instance.coverFrame = false;
    await render(tester, 74);
    expect(find.byType(CoverFrame), findsNothing);
  });

  testWidgets('封面框：打开后各尺寸都能绘制', (tester) async {
    ReaderPrefs.instance.coverFrame = true;
    // 开关是全局状态，中途失败也要复位，别漏给后面的用例。
    addTearDown(() => ReaderPrefs.instance.coverFrame = false);
    for (final w in <double>[40, 46, 64, 96, 110, 112, 124, 320]) {
      await render(tester, w);
      expect(tester.takeException(), isNull, reason: '${w}px 封面');
      expect(find.byType(CoverFrame), findsOneWidget);
    }
  });

  testWidgets('封面框：没有真实封面时不铺纸纹', (tester) async {
    ReaderPrefs.instance.coverFrame = true;
    addTearDown(() => ReaderPrefs.instance.coverFrame = false);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: CoverImage(url: '', title: '雨停之前', width: 110, height: 152))),
    ));
    await tester.pumpAndSettle();
    final frame = tester.widget<CoverFrame>(find.byType(CoverFrame));
    expect(frame.plain, isTrue, reason: '平底书名卡上不该有颗粒');
  });

  testWidgets('封面框：切换开关会立刻重建封面', (tester) async {
    ReaderPrefs.instance.coverFrame = false;
    await render(tester, 110);
    expect(find.byType(CoverFrame), findsNothing);

    ReaderPrefs.instance.coverFrame = true;
    await tester.pumpAndSettle();
    expect(find.byType(CoverFrame), findsOneWidget);

    ReaderPrefs.instance.coverFrame = false;
    await tester.pumpAndSettle();
    expect(find.byType(CoverFrame), findsNothing);
  });
}
