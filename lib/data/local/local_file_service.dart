import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import '../../core/change_bus.dart';
import '../../core/file_type.dart';
import '../../core/path_utils.dart';
import '../../core/result.dart';
import '../models/file_entry.dart';

/// 本机文件系统读取/管理封装。
///
/// 上层 UI 只能调用本类暴露的抽象方法，禁止直接调用 dart:io，
/// 以便未来切换到 SAF / MediaStore 时只改这一层。
///
/// 目录列举与递归搜索在**独立 isolate** 中执行：共享目录可达数千文件，
/// 在 UI isolate 上做遍历 + 逐条 stat 会直接卡住界面。
class LocalFileService {
  /// [rootOverride] 仅用于测试或特殊挂载点：跳过外部存储探测直接使用该根目录。
  LocalFileService({String? rootOverride}) : _root = rootOverride;

  String? _root;

  /// 共享根目录绝对路径（外部存储根，如 `/storage/emulated/0`）。
  Future<String> sharedRoot() async {
    if (_root != null) return _root!;
    try {
      final ext = await getExternalStorageDirectory();
      final p = ext?.path ?? '';
      if (p.isNotEmpty) {
        final idx = p.indexOf('/Android/');
        if (idx != -1) {
          _root = p.substring(0, idx);
          return _root!;
        }
      }
    } catch (_) {
      // 回退到常见路径
    }
    _root = '/storage/emulated/0';
    return _root!;
  }

  /// 相对路径 → 绝对路径。调用前需确保 path 已通过 normalizeRelPath 校验。
  String absolutePath(String relPath) {
    final root = _root ?? '/storage/emulated/0';
    if (relPath.isEmpty) return root;
    return '$root/$relPath';
  }

  /// 目录缓存条数上限，防止长时间浏览大目录树时无限增长。
  static const int _dirCacheMaxEntries = 64;

  /// 目录缓存有效期：吸收同目录的密集重复请求（如本机与远端同时浏览）。
  static const Duration _dirCacheTtl = Duration(seconds: 4);

  final Map<String, ({DateTime time, List<FileEntry> entries})> _dirCache = {};

  void _clearCache() => _dirCache.clear();

  void _putCache(String key, List<FileEntry> entries) {
    if (_dirCache.length >= _dirCacheMaxEntries) {
      // 近似 FIFO 淘汰：Map 保持插入顺序
      _dirCache.remove(_dirCache.keys.first);
    }
    _dirCache[key] = (time: DateTime.now(), entries: entries);
  }

  Future<Result<List<FileEntry>>> listEntries(String relPath) async {
    final normalized = normalizeRelPath(relPath);
    if (normalized == null) {
      return const Err('非法路径');
    }

    final cached = _dirCache[normalized];
    if (cached != null &&
        DateTime.now().difference(cached.time) < _dirCacheTtl) {
      return Ok(cached.entries);
    }

    final root = await sharedRoot();
    try {
      final entries = await Isolate.run(() => _scanDirectory(root, normalized));
      if (entries == null) return const Err('目录不存在');
      entries.sort(_compareEntries);
      _putCache(normalized, entries);
      return Ok(entries);
    } catch (e) {
      return Err('读取目录失败：$e');
    }
  }

  /// 在当前目录下新建文件夹。
  Future<Result<void>> createFolder(String parentPath, String name) async {
    final normalized = normalizeRelPath(parentPath);
    if (normalized == null) return const Err('非法路径');
    if (name.trim().isEmpty || name.contains('/') || name.contains('\\')) {
      return const Err('名称不合法');
    }
    final root = await sharedRoot();
    final target =
        Directory('${normalized.isEmpty ? root : '$root/$normalized'}/${name.trim()}');
    try {
      if (await target.exists()) return const Err('同名文件夹已存在');
      await target.create(recursive: false);
      _clearCache();
      ChangeBus.instance.notifyDir(normalized);
      return const Ok(null);
    } catch (e) {
      return Err('创建失败：$e');
    }
  }

  /// 重命名文件/目录。
  Future<Result<void>> rename(String relPath, String newName) async {
    final normalized = normalizeRelPath(relPath);
    if (normalized == null) return const Err('非法路径');
    if (normalized.isEmpty) return const Err('根目录不可重命名');
    if (newName.trim().isEmpty || newName.contains('/') || newName.contains('\\')) {
      return const Err('名称不合法');
    }
    final root = await sharedRoot();
    final src = FileSystemEntity.typeSync('$root/$normalized');
    final parent = _dirname(normalized);
    final destPath = joinRel(parent, newName.trim());
    try {
      final from = _entityFor('$root/$normalized', src);
      final toPath = '$root/$destPath';
      if (FileSystemEntity.typeSync(toPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        return const Err('同名文件已存在');
      }
      await from.rename(toPath);
      _clearCache();
      ChangeBus.instance.notifyDir(parent);
      return const Ok(null);
    } catch (e) {
      return Err('重命名失败：$e');
    }
  }

  /// 删除文件/目录（目录递归删除）。
  Future<Result<void>> delete(String relPath) async {
    final normalized = normalizeRelPath(relPath);
    if (normalized == null) return const Err('非法路径');
    if (normalized.isEmpty) return const Err('根目录不可删除');
    final root = await sharedRoot();
    try {
      final type = FileSystemEntity.typeSync('$root/$normalized', followLinks: false);
      if (type == FileSystemEntityType.notFound) return const Err('目标不存在');
      if (type == FileSystemEntityType.directory) {
        await Directory('$root/$normalized').delete(recursive: true);
      } else {
        await File('$root/$normalized').delete();
      }
      _clearCache();
      ChangeBus.instance.notifyDir(_dirname(normalized));
      return const Ok(null);
    } catch (e) {
      return Err('删除失败：$e');
    }
  }

  /// 在共享根目录内递归搜索，按名称匹配（大小写不敏感）。
  Future<Result<List<FileEntry>>> search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const Ok([]);
    final root = await sharedRoot();
    try {
      final results = await Isolate.run(() => _searchSync(root, q));
      return Ok(results);
    } catch (e) {
      return Err('搜索失败：$e');
    }
  }

  static FileSystemEntity _entityFor(String path, FileSystemEntityType type) =>
      type == FileSystemEntityType.directory ? Directory(path) : File(path);
}

// ---------------------------------------------------------------------------
// 以下为在独立 isolate 中执行的纯 dart:io 逻辑（不得捕获上层对象）
// ---------------------------------------------------------------------------

/// 列举目录并按需 stat。返回 null 表示目录不存在。
List<FileEntry>? _scanDirectory(String root, String normalized) {
  final dir = Directory(normalized.isEmpty ? root : '$root/$normalized');
  if (!dir.existsSync()) return null;
  final entries = <FileEntry>[];
  for (final e in dir.listSync(followLinks: false)) {
    final name = _basename(e.path);
    final isDir = e is Directory;
    final stat = _safeStat(e);
    entries.add(FileEntry(
      name: name,
      path: joinRel(normalized, name),
      type: isDir ? EntryType.folder : fileTypeFromName(name),
      sizeBytes: isDir ? -1 : stat.size,
      modifiedAt: stat.modified,
    ));
  }
  return entries;
}

/// 递归搜索（BFS，深度与结果数均有上限，避免极端目录树失控）。
List<FileEntry> _searchSync(String root, String q) {
  final results = <FileEntry>[];
  const maxResults = 200;
  const maxDepth = 8;
  final dirs = <String>['']; // 相对路径栈（空字符串 = 根）
  while (dirs.isNotEmpty && results.length < maxResults) {
    final rel = dirs.removeLast();
    final abs = rel.isEmpty ? root : '$root/$rel';
    List<FileSystemEntity> entities;
    try {
      entities = Directory(abs).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    final depth = rel.isEmpty ? 0 : rel.split('/').length;
    for (final e in entities) {
      if (results.length >= maxResults) break;
      final name = _basename(e.path);
      final isDir = e is Directory;
      if (isDir) {
        if (depth < maxDepth && !_shouldSkipDir(name)) {
          dirs.add(joinRel(rel, name));
        }
        if (name.toLowerCase().contains(q)) {
          results.add(FileEntry(
            name: name,
            path: joinRel(rel, name),
            type: EntryType.folder,
            sizeBytes: -1,
            modifiedAt: _safeStat(e).modified,
          ));
        }
        continue;
      }
      if (name.toLowerCase().contains(q)) {
        final stat = _safeStat(e);
        results.add(FileEntry(
          name: name,
          path: joinRel(rel, name),
          type: fileTypeFromName(name),
          sizeBytes: stat.size,
          modifiedAt: stat.modified,
        ));
      }
    }
  }
  results.sort(_compareEntries);
  return results;
}

({int size, DateTime modified}) _safeStat(FileSystemEntity e) {
  try {
    final stat = e.statSync();
    return (size: stat.size, modified: stat.modified);
  } catch (_) {
    return (size: -1, modified: DateTime.fromMillisecondsSinceEpoch(0));
  }
}

int _compareEntries(FileEntry a, FileEntry b) {
  if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
  if (a.isFolder) {
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }
  return b.modifiedAt.compareTo(a.modifiedAt);
}

bool _shouldSkipDir(String name) =>
    name.startsWith('.') || name == 'Android' || name == 'lost+found';

/// 同时兼容 `/` 与 `\`（Windows 下 listSync 返回的路径用反斜杠）。
final RegExp _sepPattern = RegExp(r'[/\\]');

String _basename(String p) {
  final idx = p.lastIndexOf(_sepPattern);
  return idx == -1 ? p : p.substring(idx + 1);
}

String _dirname(String p) {
  final idx = p.lastIndexOf(_sepPattern);
  return idx == -1 ? '' : p.substring(0, idx);
}
