import '../../core/file_type.dart';

/// 文件/目录条目。`path` 为相对于共享根目录的相对路径。
class FileEntry {
  const FileEntry({
    required this.name,
    required this.path,
    required this.type,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final EntryType type;
  final int sizeBytes; // 文件夹可为 -1（未计算）
  final DateTime modifiedAt;

  bool get isFolder => type == EntryType.folder;

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        name: json['name'] as String,
        path: json['path'] as String,
        type: EntryType.values.byName(json['type'] as String),
        sizeBytes: json['sizeBytes'] as int,
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': type.name,
        'sizeBytes': sizeBytes,
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  /// 人类可读的文件大小。
  String get formattedSize {
    if (isFolder || sizeBytes < 0) return '';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = sizeBytes.toDouble();
    int i = 0;
    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }
    return '${value.toStringAsFixed(value >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
  }

  @override
  bool operator ==(Object other) =>
      other is FileEntry && other.path == path && other.type == type;

  @override
  int get hashCode => Object.hash(path, type);
}
