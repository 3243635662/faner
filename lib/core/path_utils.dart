/// 相对路径工具。所有相对路径统一用 `/` 分隔，不依赖平台分隔符。
library;

/// 拼接相对路径。
String joinRel(String base, String name) {
  if (base.isEmpty) return name;
  return '$base/$name';
}

/// 规范化相对路径：去首尾 `/`、折叠重复 `/`。
/// 若包含 `..` 段则返回 null（视为路径穿越）。
String? normalizeRelPath(String path) {
  var p = path.replaceAll('\\', '/').trim();
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  final segments = p.split('/');
  if (segments.any((s) => s == '..')) return null;
  return segments.where((s) => s.isNotEmpty && s != '.').join('/');
}
