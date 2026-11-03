import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastemangax/core/store.dart';
import 'package:pastemangax/pages/novel_reader_page.dart';
import 'package:pastemangax/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不依赖网络的页面：按 390×844 手机尺寸渲染，检查布局溢出和交互流程。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initStores();
  });

  Future<void> pumpReader(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: const NovelReaderPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('轻小说阅读：工具栏、外观面板、字体与排版', (tester) async {
    await pumpReader(tester);
    expect(find.text('雨停之前'), findsOneWidget);
    expect(find.text('本章已读 0%'), findsOneWidget);
    // 排版完成后页码按正文长度计算，不应停在 1 / 1。
    expect(find.text('1 / 1'), findsNothing);

    await tester.tap(find.text('外观'));
    await tester.pumpAndSettle();
    expect(find.text('阅读外观'), findsOneWidget);

    await tester.tap(find.text('夜间'));
    await tester.pumpAndSettle();
    expect(ReaderPrefs.instance.theme, 3);

    await tester.tap(find.text('字体与排版'));
    await tester.pumpAndSettle();
    expect(find.text('恢复默认排版'), findsOneWidget);

    await tester.tap(find.text('宽松'));
    await tester.tap(find.text('加粗'));
    await tester.pumpAndSettle();
    expect(ReaderPrefs.instance.line, 2);
    expect(ReaderPrefs.instance.weight, 2);

    await tester.tap(find.text('更多排版'));
    await tester.pumpAndSettle();
    expect(find.text('字间距'), findsOneWidget);

    await tester.ensureVisible(find.text('恢复默认排版'));
    await tester.tap(find.text('恢复默认排版'));
    await tester.pumpAndSettle();
    expect(ReaderPrefs.instance.line, 1);
    expect(ReaderPrefs.instance.weight, 0);
    expect(ReaderPrefs.instance.theme, 3, reason: '恢复排版不应改动配色');
  });

  testWidgets('轻小说阅读：切章、目录、查找', (tester) async {
    await pumpReader(tester);

    await tester.tap(find.byTooltip('下一章'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第二章'), findsOneWidget);
    expect(LibraryStore.instance.entry('sample-novel')?.chapterUuid, 'c1');

    await tester.tap(find.text('目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回去的方向'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第四章'), findsOneWidget);

    await tester.tap(find.text('查找'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '雨');
    await tester.tap(find.widgetWithText(TextButton, '查找'));
    await tester.pumpAndSettle();
    expect(find.textContaining('本章找到'), findsOneWidget);
  });
}
