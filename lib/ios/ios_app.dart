import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models.dart';
import '../core/store.dart';
import '../core/update_service.dart';
import '../pages/update_dialog.dart' show plainNotes;
import '../ui/icons.dart';
import '../ui/theme.dart' show formatBytes;
import 'ios_detail.dart';
import 'ios_discover.dart';
import 'ios_mine.dart';
import 'ios_novel.dart';
import 'ios_reader.dart';
import 'ios_search.dart';
import 'ios_shelf.dart';
import 'ios_theme.dart';

class IosApp extends StatelessWidget {
  const IosApp({super.key});

  @override
  Widget build(BuildContext context) {
    GlassScope.reduce.value = ReaderPrefs.instance.reduceTransparency;
    return MaterialApp(
      title: '栞间',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        platform: TargetPlatform.iOS,
        scaffoldBackgroundColor: IosColors.bg,
        colorScheme: ColorScheme.fromSeed(seedColor: IosColors.accent, primary: IosColors.accent, surface: IosColors.bg),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        cupertinoOverrideTheme: const CupertinoThemeData(primaryColor: IosColors.accent),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        }),
      ),
      builder: (context, child) => GlassScope(reduce: GlassScope.reduce, child: child!),
      home: const IosShell(),
    );
  }
}

class IosShell extends StatefulWidget {
  const IosShell({super.key});

  static final tab = ValueNotifier<int>(0);

  /// 测试里关掉启动时的更新检查。
  static bool autoUpdateCheck = true;

  @override
  State<IosShell> createState() => _IosShellState();
}

class _IosShellState extends State<IosShell> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
    if (IosShell.autoUpdateCheck) Future.delayed(const Duration(seconds: 3), _autoCheck);
  }

  Future<void> _autoCheck() async {
    final r = await UpdateService.instance.autoCheck();
    if (r != null && mounted) showIosUpdateDialog(context, r);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: IosShell.tab,
        builder: (context, index, _) => Scaffold(
          body: Stack(children: [
            Positioned.fill(child: IndexedStack(index: index, children: const [IosShelfPage(), IosDiscoverPage(), IosMinePage()])),
            // 底部渐隐，让悬浮标签栏下的内容不抢视线。
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [IosColors.bg.withValues(alpha: 0), IosColors.bg.withValues(alpha: .88)],
                    ),
                  ),
                ),
              ),
            ),
            _TabDock(index: index),
          ]),
        ),
      );
}

class _TabDock extends StatelessWidget {
  const _TabDock({required this.index});

  final int index;

  static const _items = [('book', 'bookFill', '书架'), ('compass', 'compassFill', '发现'), ('person', 'personFill', '我的')];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 18,
      right: 18,
      bottom: bottom > 0 ? bottom - 6 : 16,
      height: 64,
      child: ListenableBuilder(
        listenable: LibraryStore.instance,
        builder: (context, _) {
          final hasUpdate = LibraryStore.instance.entries.any((e) => e.hasUpdate);
          return Row(children: [
            Expanded(
              child: Glass(
                radius: 32,
                padding: const EdgeInsets.all(5),
                child: LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth / 3;
                    return Stack(children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        left: w * index,
                        top: 0,
                        bottom: 0,
                        width: w,
                        child: DecoratedBox(decoration: BoxDecoration(color: const Color(0x1A747070), borderRadius: BorderRadius.circular(27))),
                      ),
                      Row(children: [
                        for (var i = 0; i < _items.length; i++)
                          Expanded(
                            child: Pressable(
                              haptic: true,
                              semanticLabel: i == 0 && hasUpdate && index != 0 ? '${_items[i].$3}，有更新' : _items[i].$3,
                              onTap: () => IosShell.tab.value = i,
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Stack(clipBehavior: Clip.none, children: [
                                  AppIcon(i == index ? _items[i].$2 : _items[i].$1, size: 23, color: i == index ? IosColors.accent : IosColors.tab, stroke: 1.7),
                                  if (i == 0 && hasUpdate && index != 0)
                                    Positioned(
                                      top: -1,
                                      right: -3,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(color: IosColors.accent, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                                      ),
                                    ),
                                ]),
                                const SizedBox(height: 2),
                                Text(_items[i].$3,
                                    style: TextStyle(fontSize: 11, height: 14 / 11, color: i == index ? IosColors.accent : IosColors.tab, fontWeight: i == index ? FontWeight.w600 : FontWeight.w500)),
                              ]),
                            ),
                          ),
                      ]),
                    ]);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Pressable(
              semanticLabel: '搜索',
              onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const IosSearchPage())),
              child: const Glass(
                radius: 32,
                child: SizedBox.square(dimension: 64, child: Center(child: AppIcon('search', size: 25, color: IosColors.ink, stroke: 1.8))),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/* ───────── 导航 ───────── */

ComicBrief briefOfEntry(ShelfEntry e) => ComicBrief(name: e.name, pathWord: e.id, cover: e.cover, authors: [e.author]);

Future<void> iosOpenDetail(BuildContext context, ComicBrief comic) =>
    Navigator.of(context).push(CupertinoPageRoute(builder: (_) => IosDetailPage(comic: comic)));

Future<void> iosOpenReader(BuildContext context, {required ComicBrief comic, required String group, required String chapterUuid, int initialPage = 0}) =>
    Navigator.of(context).push(CupertinoPageRoute(
      builder: (_) => IosReaderPage(comic: comic, group: group, chapterUuid: chapterUuid, initialPage: initialPage),
    ));

Future<void> iosOpenNovel(BuildContext context) => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const IosNovelPage()));

/// 继续阅读：小说进阅读器，漫画有进度进阅读器，否则进详情。
Future<void> iosContinue(BuildContext context, ShelfEntry e) {
  if (e.kind == ShelfKind.novel) return iosOpenNovel(context);
  if (e.chapterUuid == null) return iosOpenDetail(context, briefOfEntry(e));
  return iosOpenReader(context, comic: briefOfEntry(e), group: e.group ?? 'default', chapterUuid: e.chapterUuid!, initialPage: e.page);
}

/* ───────── 更新 ───────── */

Future<void> showIosUpdateDialog(BuildContext context, UpdateResult r) {
  final release = r.release!;
  final meta = [
    '当前 v${r.current}',
    if (release.packageSize != null) '安装包 ${formatBytes(release.packageSize!)}',
    if (release.publishedAt != null) '${release.publishedAt!.month}月${release.publishedAt!.day}日发布',
  ].join(' · ');
  final notes = plainNotes(release.notes);
  return showCupertinoDialog<void>(
    context: context,
    builder: (dialog) => CupertinoAlertDialog(
      title: Text('发现新版本 v${release.version}'),
      content: Column(children: [
        const SizedBox(height: 4),
        Text(meta, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 200),
          child: SingleChildScrollView(child: Text(notes.isEmpty ? release.title : notes, textAlign: TextAlign.left, style: const TextStyle(fontSize: 13, height: 1.5))),
        ),
      ]),
      actions: [
        CupertinoDialogAction(
          onPressed: () {
            ReaderPrefs.instance.skipVersion = release.version;
            Navigator.pop(dialog);
          },
          child: const Text('跳过此版本'),
        ),
        CupertinoDialogAction(onPressed: () => Navigator.pop(dialog), child: const Text('以后')),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.pop(dialog);
            launchUrl(Uri.parse(release.downloadUrl), mode: LaunchMode.externalApplication);
          },
          child: const Text('下载'),
        ),
      ],
    ),
  );
}

/// 「我的」里的手动检查。
Future<UpdateResult> iosManualUpdateCheck(BuildContext context) async {
  final r = await UpdateService.instance.check();
  if (!context.mounted) return r;
  if (r.status == UpdateStatus.available) {
    await showIosUpdateDialog(context, r);
  } else {
    showIosToast(context, switch (r.status) {
      UpdateStatus.upToDate => r.message ?? '已是最新版本 v${r.current}',
      UpdateStatus.noRelease => '仓库还没有发布版本',
      _ => r.message ?? '检查更新失败',
    });
  }
  return r;
}
