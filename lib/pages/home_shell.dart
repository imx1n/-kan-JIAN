import 'package:flutter/material.dart';

import '../core/store.dart';
import '../core/update_service.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import 'discover_page.dart';
import 'mine_page.dart';
import 'shelf_page.dart';
import 'update_dialog.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// 其他页面可通过它切换底部导航（例如空书架里的「去发现」）。
  static final tab = ValueNotifier<int>(0);

  /// 测试里关掉启动时的更新检查。
  static bool autoUpdateCheck = true;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _items = [('book', '书架'), ('compass', '发现'), ('person', '我的')];

  @override
  void initState() {
    super.initState();
    if (HomeShell.autoUpdateCheck) {
      // 首帧之后稍等再查，不和书架首屏的请求抢。
      Future.delayed(const Duration(seconds: 3), _autoCheck);
    }
  }

  Future<void> _autoCheck() async {
    final r = await UpdateService.instance.autoCheck();
    if (r != null && mounted) showUpdateDialog(context, r);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: HomeShell.tab,
        builder: (context, index, _) => PopScope(
          canPop: index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) HomeShell.tab.value = 0;
          },
          child: Scaffold(
            body: IndexedStack(index: index, children: const [ShelfPage(), DiscoverPage(), MinePage()]),
            bottomNavigationBar: ListenableBuilder(
              listenable: LibraryStore.instance,
              builder: (context, _) {
                final hasUpdate = LibraryStore.instance.entries.any((e) => e.hasUpdate);
                return DecoratedBox(
                  decoration: const BoxDecoration(color: Palette.bar, border: Border(top: BorderSide(color: Palette.line))),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Row(children: [
                        for (var i = 0; i < _items.length; i++)
                          Expanded(
                            child: _NavItem(
                              icon: _items[i].$1,
                              label: _items[i].$2,
                              selected: i == index,
                              // 书架有更新而用户在其他页时，书架图标上加一个锈红圆点。
                              pip: i == 0 && i != index && hasUpdate,
                              onTap: () => HomeShell.tab.value = i,
                            ),
                          ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.pip, required this.onTap});

  final String icon;
  final String label;
  final bool selected;
  final bool pip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Palette.ink : Palette.ink2;
    return Semantics(
      selected: selected,
      button: true,
      label: pip ? '$label，有更新' : label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 64,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 60,
              height: 32,
              decoration: BoxDecoration(color: selected ? Palette.tonal2 : Colors.transparent, borderRadius: BorderRadius.circular(16)),
              child: Stack(alignment: Alignment.center, children: [
                AppIcon(icon, size: 23, color: color, stroke: 1.65),
                if (pip)
                  Positioned(
                    top: 4,
                    right: 15,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: Palette.accent, shape: BoxShape.circle, border: Border.all(color: Palette.bar, width: 1.5)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}
