import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/store.dart';
import '../core/update_service.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';

/// Release 说明是 Markdown；弹窗里只需要可读的纯文本：去掉标题井号、把列表符号换成圆点。
String plainNotes(String md) => md
    .split('\n')
    .map((l) => l.trimRight())
    .map((l) => l.replaceFirst(RegExp(r'^#{1,6}\s*'), ''))
    .map((l) => l.replaceFirst(RegExp(r'^\s*[-*+]\s+'), '• '))
    .map((l) => l.replaceAll(RegExp(r'\*\*|__|`'), ''))
    .join('\n')
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// 发现新版本时的弹窗：版本号、大小、发布日期、更新内容，以及「跳过此版本 / 以后 / 下载」。
Future<void> showUpdateDialog(BuildContext context, UpdateResult r) {
  final release = r.release!;
  final meta = [
    '当前 v${r.current}',
    if (release.apkSize != null) 'APK ${formatBytes(release.apkSize!)}',
    if (release.publishedAt != null) '${release.publishedAt!.month}月${release.publishedAt!.day}日发布',
  ].join(' · ');
  final notes = plainNotes(release.notes);
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      icon: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: Palette.tonal2, shape: BoxShape.circle),
        child: const AppIcon('download', size: 22, color: Palette.sageInk),
      ),
      title: Text('发现新版本 v${release.version}', textAlign: TextAlign.center),
      titleTextStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Palette.ink),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(meta, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Palette.ink3)),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(color: Palette.tonal, borderRadius: BorderRadius.circular(12)),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('更新内容', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(notes.isEmpty ? release.title : notes, style: const TextStyle(fontSize: 14, height: 1.7, color: Palette.ink2)),
            ]),
          ),
        ),
        if (release.apkUrl == null) ...[
          const SizedBox(height: 10),
          const Text('这个版本没有附带 APK，将打开 Release 页面。', style: TextStyle(fontSize: 12, color: Palette.ink3)),
        ],
      ]),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () {
            ReaderPrefs.instance.skipVersion = release.version;
            Navigator.pop(dialog);
          },
          style: TextButton.styleFrom(foregroundColor: Palette.ink2),
          child: const Text('跳过此版本'),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: () => Navigator.pop(dialog), style: TextButton.styleFrom(foregroundColor: Palette.ink), child: const Text('以后')),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialog);
              final ok = await launchUrl(Uri.parse(release.downloadUrl), mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('无法打开浏览器，下载地址：${release.downloadUrl}')));
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Palette.ink),
            child: const Text('下载'),
          ),
        ]),
      ],
    ),
  );
}

/// 「我的」里的手动检查：有新版本弹窗，其余情况用提示条说明结果。
Future<UpdateResult> runManualUpdateCheck(BuildContext context) async {
  final r = await UpdateService.instance.check();
  if (!context.mounted) return r;
  if (r.status == UpdateStatus.available) {
    await showUpdateDialog(context, r);
  } else {
    final text = switch (r.status) {
      UpdateStatus.upToDate => '已是最新版本 v${r.current}',
      UpdateStatus.noRelease => '${r.message}，当前 v${r.current}',
      _ => r.message ?? '检查更新失败',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
  return r;
}
