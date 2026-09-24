// 时间轴分组规则测试。
import 'package:faner/core/file_type.dart';
import 'package:faner/core/timeline_utils.dart';
import 'package:faner/data/models/file_entry.dart';
import 'package:flutter_test/flutter_test.dart';

FileEntry _file(String name, DateTime modifiedAt) => FileEntry(
      name: name,
      path: name,
      type: EntryType.image,
      sizeBytes: 1024,
      modifiedAt: modifiedAt,
    );

/// 与实现同源的标签规则，避免测试里写死当天日期导致跨天/跨年失败。
String _labelOf(DateTime t, DateTime now) {
  final date = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  if (date == today) return '今天';
  if (date == today.subtract(const Duration(days: 1))) return '昨天';
  if (date.year == now.year) return '${date.month}月${date.day}日';
  return '${date.year}年${date.month}月';
}

void main() {
  test('空列表返回空分组', () {
    expect(groupEntriesByTimeline(const []), isEmpty);
  });

  test('文件夹单独置顶，文件按日期倒序分组', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 9);
    final yesterday = today.subtract(const Duration(days: 1));
    final older = today.subtract(const Duration(days: 40));
    final lastYear = DateTime(now.year - 1, 1, 3);

    final entries = [
      _file('a.jpg', today),
      FileEntry(
        name: '相册',
        path: '相册',
        type: EntryType.folder,
        sizeBytes: -1,
        modifiedAt: today,
      ),
      _file('b.jpg', yesterday),
      _file('c.jpg', older),
      _file('d.jpg', lastYear),
    ];

    final sections = groupEntriesByTimeline(entries);
    final titles = sections.map((s) => s.title).toList();

    expect(titles.first, '文件夹');
    expect(sections.first.entries.single.name, '相册');
    expect(titles, [
      '文件夹',
      _labelOf(today, now),
      _labelOf(yesterday, now),
      _labelOf(older, now),
      _labelOf(lastYear, now),
    ]);

    // 每个文件只出现一次
    final total = sections.fold<int>(0, (sum, s) => sum + s.entries.length);
    expect(total, entries.length);
  });

  test('只有文件时不会出现空的文件夹分组', () {
    final now = DateTime.now();
    final sections = groupEntriesByTimeline([
      _file('a.jpg', now),
      _file('b.jpg', now.subtract(const Duration(minutes: 5))),
    ]);
    expect(sections.every((s) => s.title != '文件夹'), isTrue);
    expect(sections.first.title, '今天');
    expect(sections.first.entries, hasLength(2));
  });
}
