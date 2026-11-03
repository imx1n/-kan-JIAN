import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pastemangax/core/shelf_sync.dart';
import 'package:pastemangax/core/store.dart';
import 'package:pastemangax/ios/ios_app.dart';
import 'package:pastemangax/ios/ios_mine.dart';
import 'package:pastemangax/ios/ios_novel.dart';
import 'package:pastemangax/ios/ios_shelf.dart';
import 'package:pastemangax/ios/ios_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 以 iOS 平台运行的组件测试。
void iosTest(String name, WidgetTesterCallback body) => testWidgets(name, body, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

/// iOS 界面：按 iPhone 16（393×852）渲染，检查布局溢出与关键交互。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: '栞间', packageName: 'com.pastemangax.reader', version: '0.3.0', buildNumber: '3', buildSignature: '');
    await initStores();
    ShelfSync.enabled = false;
    IosShell.autoUpdateCheck = false;
    IosShell.tab.value = 0;
    GlassScope.reduce.value = false;
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.iOS),
      builder: (context, c) => GlassScope(reduce: GlassScope.reduce, child: c!),
      home: Scaffold(body: child),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  ShelfEntry manga(String id, {int latest = 10, int seen = 10, bool started = false, String status = '連載中'}) => ShelfEntry(
        id: id,
        kind: ShelfKind.manga,
        name: '作品$id',
        cover: '',
        author: '作者',
        status: status,
        latestChapter: '第$latest话',
        latestUpdated: '2026-11-03',
        latestCount: latest,
        seenCount: seen,
        chapterUuid: started ? 'u$id' : null,
        chapterName: started ? '第245话' : null,
        page: 2,
        pageCount: 16,
        progress: started ? .19 : 0,
      );

  iosTest('书架：首次使用', (tester) async {
    await pump(tester, const IosShelfPage());
    expect(find.text('好故事，从第一本开始'), findsOneWidget);
    await tester.tap(find.text('去发现'));
    expect(IosShell.tab.value, 1);
  });

  iosTest('书架：最近在读、有更新、筛选', (tester) async {
    final store = LibraryStore.instance;
    store.put(manga('a', started: true));
    store.put(manga('b', latest: 12, seen: 10));
    store.put(manga('c', status: '已完結'));
    await pump(tester, const IosShelfPage());

    expect(find.text('最近在读'), findsOneWidget);
    expect(find.text('第245话  第 3 / 16 页'), findsOneWidget);
    expect(find.text('新 2 话'), findsOneWidget);
    expect(find.text('我的藏书'), findsOneWidget);

    await tester.tap(find.text('已完结'));
    await tester.pump();
    expect(find.text('作品c'), findsWidgets);
    expect(find.text('作品b'), findsNothing);
  });

  iosTest('标签栏：三个标签 + 搜索', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const IosApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('书架'), findsWidgets);
    expect(find.bySemanticsLabel('搜索'), findsWidgets);
    await tester.tap(find.text('我的').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(IosShell.tab.value, 2);
  });

  iosTest('我的：分组设置、版本号', (tester) async {
    await pump(tester, const IosMinePage());
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('漫画翻页方向'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('当前 v0.3.0'), 200);
    expect(find.textContaining('当前 v0.3.0'), findsOneWidget);
  });

  iosTest('小说：阅读外观 → 字体与排版，减少透明度', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, c) => GlassScope(reduce: GlassScope.reduce, child: c!),
      home: const IosNovelPage(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('雨停之前'), findsWidgets);
    expect(find.text('1  /  1'), findsNothing);

    await tester.tap(find.text('阅读设置'));
    await tester.pumpAndSettle();
    expect(find.text('阅读外观'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('暖纸'));
    await tester.pumpAndSettle();
    expect(ReaderPrefs.instance.theme, 1);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    expect(ReaderPrefs.instance.reduceTransparency, isTrue);
    expect(GlassScope.reduce.value, isTrue);

    await tester.tap(find.text('字体与排版'));
    await tester.pumpAndSettle();
    expect(find.text('阅读字体'), findsOneWidget);
    await tester.tap(find.text('黑体'));
    await tester.pumpAndSettle();
    expect(ReaderPrefs.instance.font, 1);
    await tester.tap(find.text('恢复默认排版'));
    await tester.pumpAndSettle();
    expect(ReaderPrefs.instance.font, 0);
    expect(ReaderPrefs.instance.lineHeight, 1.85);
  });
}
