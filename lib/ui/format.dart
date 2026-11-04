// 人气、日期、文件大小的显示格式。

String formatPopular(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000000) return '${(n / 10000).round()}万';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
  return '$n';
}

/// `2026-11-03` → 今天 / 昨天 / 11月3日 / 2025年10月。
String formatDay(String ymd, {DateTime? now}) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  final today = now ?? DateTime.now();
  final diff = DateTime(today.year, today.month, today.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  return d.year == today.year ? '${d.month}月${d.day}日' : '${d.year}年${d.month}月';
}

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).round()} KB';
  return '$bytes B';
}
