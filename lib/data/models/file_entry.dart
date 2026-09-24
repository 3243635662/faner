import '../../core/file_type.dart';

// 项目里的文件/目录数据模型
/// 文件/目录条目。`path` 为相对于共享根目录的相对路径。
class FileEntry {
  const FileEntry({
    required this.name, // 文件名
    required this.path, // 相对共享根目录的相对路径
    required this.type, // 文件类型
    required this.sizeBytes, // 文件字节大小
    required this.modifiedAt, //最后修改时间
  });

  final String name;
  final String path;
  final EntryType type;
  final int sizeBytes; // 文件夹可为 -1（未计算）
  final DateTime modifiedAt;

  bool get isFolder => type == EntryType.folder; // 是不是文件夹

  // 把服务端 HTTP API 返回的 JSON 转成 FileEntry
  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    name: json['name'] as String,
    path: json['path'] as String,
    // 从类型枚举的值列表中查找 type 属性等于传入字符串的枚举值，并返回它
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
