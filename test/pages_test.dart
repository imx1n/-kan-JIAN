import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pastemangax/core/shelf_sync.dart';
import 'package:pastemangax/core/store.dart';
import 'package:pastemangax/core/update_service.dart';
import 'package:pastemangax/pages/home_shell.dart';
import 'package:pastemangax/pages/mine_page.dart';
import 'package:pastemangax/pages/shelf_page.dart';
import 'package:pastemangax/pages/update_dialog.dart';
import 'package:pastemangax/ui/theme.dart';
import 'package:pastemangax/ui/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不依赖网络的页面：按 390×844 手机尺寸渲染，检查布局溢出与关键交互。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: '栞间', packageName: 'com.pastemangax.reader', version: '0.2.0', buildNumber: '2', buildSignature: '');
    await initStores();
    ShelfSync.enabled = false;
    HomeShell.autoUpdateCheck = false;
    HomeShell.tab.value = 0;
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: child)));
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
        chapterName: started ? '第3话' : null,
        page: 2,
        pageCount: 16,
        progress: started ? .19 : 0,
      );

  testWidgets('标签和角标宽度跟随文字，不会在 Wrap 里撑满整行', (tester) async {
    await pump(tester, const Wrap(children: [Pill('連載中'), NewBadge('新 2 话')]));
    expect(tester.getSize(find.byType(Pill)).width, lessThan(120));
    expect(tester.getSize(find.byType(NewBadge)).width, lessThan(120));
  });

  testWidgets('书架：空的时候显示首次使用说明', (tester) async {
    await pump(tester, const ShelfPage());
    expect(find.text('书架还空着'), findsOneWidget);
    expect(find.text('去发现'), findsOneWidget);
    await tester.tap(find.text('去发现'));
    expect(HomeShell.tab.value, 1);
  });

  testWidgets('书架：继续阅读、有更新、筛选', (tester) async {
    final store = LibraryStore.instance;
    store.put(manga('a', started: true));
    store.put(manga('b', latest: 12, seen: 10));
    store.put(manga('c', status: '已完結'));
    await pump(tester, const ShelfPage());

    expect(find.text('继续阅读'), findsOneWidget);
    expect(find.text('第3话 · 第 3 / 16 页'), findsOneWidget);
    expect(find.text('新 2 话'), findsOneWidget);

    // 没有封面时占位封面上也会显示书名，所以同一部作品可能匹配到两处。
    await tester.tap(find.text('有更新').first);
    await tester.pump();
    expect(find.text('作品b'), findsWidgets);
    expect(find.text('作品c'), findsNothing);

    await tester.tap(find.text('已完结'));
    await tester.pump();
    expect(find.text('作品c'), findsWidgets);
    expect(find.text('作品b'), findsNothing);

    // 筛选胶囊一行放不下，轻小说要先横向滚出来。
    await tester.ensureVisible(find.text('轻小说'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('轻小说'));
    await tester.pump();
    expect(find.text('打开示例《雨停之前》'), findsOneWidget);
  });

  testWidgets('我的：版本号、阅读默认值', (tester) async {
    await pump(tester, const MinePage());
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('当前 v0.2.0'), findsOneWidget);

    await tester.tap(find.text('省流'));
    await tester.pump();
    expect(ReaderPrefs.instance.mangaSaver, isTrue);

    await tester.tap(find.text('从左向右'));
    await tester.pump();
    expect(ReaderPrefs.instance.mangaRtl, isFalse);

    await tester.scrollUntilVisible(find.text('项目主页'), 200);
    expect(find.textContaining('github.com/luminacry/-kan-JIAN'), findsOneWidget);
  });

  testWidgets('更新弹窗：内容与「跳过此版本」', (tester) async {
    final r = UpdateService.resolve(200, {
      'tag_name': 'v0.3.0',
      'name': 'v0.3.0',
      'body': '- 书架可以按更新时间排序\n- 阅读器新增省流画质',
      'html_url': 'https://github.com/luminacry/-kan-JIAN/releases/tag/v0.3.0',
      'published_at': '2026-11-05T08:00:00Z',
      'assets': [
        {'name': 'kanjian-0.3.0.apk', 'size': 19293798, 'browser_download_url': 'https://example.com/a.apk'},
      ],
    }, '0.2.0');
    await pump(tester, Builder(builder: (context) => TextButton(onPressed: () => showUpdateDialog(context, r), child: const Text('open'))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('发现新版本 v0.3.0'), findsOneWidget);
    expect(find.textContaining('APK 18.4 MB'), findsOneWidget);
    expect(find.textContaining('• 阅读器新增省流画质'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);

    await tester.tap(find.text('跳过此版本'));
    await tester.pumpAndSettle();
    expect(ReaderPrefs.instance.skipVersion, '0.3.0');
    expect(find.text('发现新版本 v0.3.0'), findsNothing);
  });
}
