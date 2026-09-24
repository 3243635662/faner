/// 通用格式化工具。
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) {
    // padLeft是不足指定的位数就补指定的字符
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 格式化文件修改时间：今天显示「今天 HH:mm」，跨年显示完整日期。
String formatDateTime(DateTime dt) {
  final now = DateTime.now();
  final hm =
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return '今天 $hm';
  }
  final md =
      '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  if (dt.year == now.year) {
    return '$md $hm';
  }
  return '${dt.year}-$md $hm';
}

/// 人类可读的字节大小格式化（如 "12.5 MB"、"450 KB"）。
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(value >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

