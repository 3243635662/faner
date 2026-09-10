import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/file_type.dart';
import '../../core/path_utils.dart';
import '../../core/result.dart';
import '../models/file_entry.dart';

/// 本机文件系统读取/管理封装。
///
/// 上层 UI 只能调用本类暴露的抽象方法，禁止直接调用 dart:io，
/// 以便未来切换到 SAF / MediaStore 时只改这一层。
class LocalFileService {
  LocalFileService();

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

  Future<Result<List<FileEntry>>> listEntries(String relPath) async {
    final normalized = normalizeRelPath(relPath);
    if (normalized == null) {
      return const Err('非法路径');
    }
    final root = await sharedRoot();
    final dir = Directory(relPath.isEmpty ? root : '$root/$normalized');
    try {
      if (!await dir.exists()) return const Err('目录不存在');
      final entities = <FileSystemEntity>[];
      await for (final e in dir.list(followLinks: false)) {
        entities.add(e);
      }
      final entries = <FileEntry>[];
      for (final e in entities) {
        final stat = await e.stat();
        final name = _basename(e.path);
        final isDir = e is Directory;
        entries.add(FileEntry(
          name: name,
          path: joinRel(normalized, name),
          type: isDir ? EntryType.folder : fileTypeFromName(name),
          sizeBytes: isDir ? -1 : stat.size,
          modifiedAt: stat.modified,
        ));
      }
      entries.sort(_compareEntries);
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
    final target = Directory('${normalized.isEmpty ? root : '$root/$normalized'}/${name.trim()}');
    try {
      if (await target.exists()) return const Err('同名文件夹已存在');
      await target.create(recursive: false);
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
    final results = <FileEntry>[];
    const maxResults = 200;
    const maxDepth = 8;
    final dirs = <String>['']; // 相对路径栈（空字符串=根）
    while (dirs.isNotEmpty && results.length < maxResults) {
      final rel = dirs.removeLast();
      final abs = rel.isEmpty ? root : '$root/$rel';
      List<FileSystemEntity> entities;
      try {
        entities = await Directory(abs).list(followLinks: false).toList();
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
            final stat = await _safeStat(e);
            results.add(FileEntry(
              name: name,
              path: joinRel(rel, name),
              type: EntryType.folder,
              sizeBytes: -1,
              modifiedAt: stat.modified,
            ));
          }
          continue;
        }
        if (name.toLowerCase().contains(q)) {
          final stat = await _safeStat(e);
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
    return Ok(results);
  }

  // ---- 内部工具 ----

  static int _compareEntries(FileEntry a, FileEntry b) {
    if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
    if (a.isFolder) return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return b.modifiedAt.compareTo(a.modifiedAt);
  }

  static bool _shouldSkipDir(String name) =>
      name.startsWith('.') || name == 'Android' || name == 'lost+found';

  static Future<FileStat> _safeStat(FileSystemEntity e) async {
    try {
      return await e.stat();
    } catch (_) {
      return FileStat.statSync(e.path);
    }
  }

  static String _basename(String p) {
    final idx = p.lastIndexOf('/');
    return idx == -1 ? p : p.substring(idx + 1);
  }

  static String _dirname(String p) {
    final idx = p.lastIndexOf('/');
    return idx == -1 ? '' : p.substring(0, idx);
  }

  static FileSystemEntity _entityFor(String path, FileSystemEntityType type) =>
      type == FileSystemEntityType.directory ? Directory(path) : File(path);
}
