import '../data/models/file_entry.dart';

/// 时间轴分组结果
class TimelineSection {
  const TimelineSection({
    required this.title,
    required this.entries,
  });

  final String title;
  final List<FileEntry> entries;
}

/// 将文件条目按时间维度智能聚合。
///
/// 规则：
/// 1. 如果存在文件夹，单独聚合到「文件夹」组置顶，便于层级导航。
/// 2. 文件按修改时间分类：
///    - 属于当天：显示「今天」
///    - 属于前一天：显示「昨天」
///    - 属于当年其他日期：显示「M月d日」
///    - 属于往年：显示「yyyy年M月」
List<TimelineSection> groupEntriesByTimeline(List<FileEntry> entries) {
  if (entries.isEmpty) return const [];

  final folders = <FileEntry>[];
  final files = <FileEntry>[];

  for (final e in entries) {
    if (e.isFolder) {
      folders.add(e);
    } else {
      files.add(e);
    }
  }

  final sections = <TimelineSection>[];

  if (folders.isNotEmpty) {
    sections.add(TimelineSection(
      title: '文件夹',
      entries: folders,
    ));
  }

  if (files.isEmpty) return sections;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  // 按日期归类映射（保持先后插入顺序）
  final groups = <String, List<FileEntry>>{};

  for (final file in files) {
    final t = file.modifiedAt;
    final fileDate = DateTime(t.year, t.month, t.day);

    String label;
    if (fileDate == today) {
      label = '今天';
    } else if (fileDate == yesterday) {
      label = '昨天';
    } else if (fileDate.year == now.year) {
      label = '${fileDate.month}月${fileDate.day}日';
    } else {
      label = '${fileDate.year}年${fileDate.month}月';
    }

    groups.putIfAbsent(label, () => []).add(file);
  }

  for (final entry in groups.entries) {
    sections.add(TimelineSection(
      title: entry.key,
      entries: entry.value,
    ));
  }

  return sections;
}
