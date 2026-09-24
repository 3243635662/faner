import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../core/result.dart';
import '../models/device_info.dart';
import 'remote_file_client.dart';

/// 远程缩略图批量装载器。
///
/// 网格/列表一屏会请求几十张缩略图，逐张 HTTP 往返在弱网下延迟叠加严重
/// （几千次往返比带宽更致命）。这里把极短时间窗口内的请求合并成一次
/// `/api/thumbs` 调用，并做「内存 + 磁盘」两级缓存
/// （缓存键含 mtime：文件被替换后旧图自动失效）。
class ThumbnailBatchLoader {
  ThumbnailBatchLoader(this._client);

  final RemoteFileClient _client;

  /// 合批窗口：把相邻帧内产生的请求攒成一批。
  static const Duration _coalesceWindow = Duration(milliseconds: 40);

  /// 单次请求最大路径数（与服务端 maxBatchThumbnails 对齐）。
  static const int _maxBatch = 48;

  static const int _maxMemEntries = 400;

  final Map<String, Uint8List> _memCache = {};
  final Map<String, _PendingThumb> _pending = {};
  Timer? _flushTimer;
  bool _disposed = false;

  /// 取缩略图字节；未命中缓存时会与其他请求合并成批量请求。
  Future<Uint8List?> load(DeviceInfo device, String path, int mtimeMs) async {
    final key = '${device.ip}:${device.port}|$path|$mtimeMs';

    final mem = _memCache[key];
    if (mem != null) return mem;

    final disk = await _readDisk(key);
    if (disk != null) {
      _putMem(key, disk);
      return disk;
    }

    if (_disposed) return null;

    final existing = _pending[key];
    if (existing != null) return existing.completer.future;

    final pending = _PendingThumb(
      device: device,
      path: path,
      key: key,
      completer: Completer<Uint8List?>(),
    );
    _pending[key] = pending;
    _flushTimer ??= Timer(_coalesceWindow, _flush);
    return pending.completer.future;
  }

  void dispose() {
    _disposed = true;
    _flushTimer?.cancel();
    _flushTimer = null;
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) pending.completer.complete(null);
    }
    _pending.clear();
  }

  void _putMem(String key, Uint8List bytes) {
    if (_memCache.length >= _maxMemEntries) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[key] = bytes;
  }

  Future<void> _flush() async {
    _flushTimer = null;
    if (_pending.isEmpty || _disposed) return;

    // 一次批量请求只能针对同一台设备，先按设备分组。
    final groups = <String, List<_PendingThumb>>{};
    for (final pending in _pending.values) {
      groups.putIfAbsent(pending.device.baseUrl, () => []).add(pending);
    }

    for (final group in groups.values) {
      final batch = group.take(_maxBatch).toList();
      for (final pending in batch) {
        _pending.remove(pending.key);
      }
      unawaited(_dispatch(batch));
    }

    // 超出单次上限的请求留到下一批。
    if (_pending.isNotEmpty) {
      _flushTimer = Timer(_coalesceWindow, _flush);
    }
  }

  Future<void> _dispatch(List<_PendingThumb> batch) async {
    if (batch.isEmpty) return;
    final device = batch.first.device;
    final paths = batch.map((p) => p.path).toList();

    Map<String, Uint8List?>? result;
    final res = await _client.thumbnails(device, paths, max: _maxBatch);
    switch (res) {
      case Ok(:final value):
        result = value;
      case Err():
        result = null;
    }

    for (final pending in batch) {
      final bytes = result?[pending.path];
      if (bytes != null) {
        _putMem(pending.key, bytes);
        unawaited(_writeDisk(pending.key, bytes));
      }
      if (!pending.completer.isCompleted) {
        pending.completer.complete(bytes);
      }
    }
  }

  Future<Directory> _cacheDir() async {
    final temp = await getTemporaryDirectory();
    final dir = Directory('${temp.path}${Platform.pathSeparator}faner_thumbs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _diskName(String key) =>
      '${key.hashCode.toRadixString(16)}_${key.length}.bin';

  Future<Uint8List?> _readDisk(String key) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}${Platform.pathSeparator}${_diskName(key)}');
      if (await file.exists()) return await file.readAsBytes();
    } catch (_) {
      // 缓存读取失败按未命中处理
    }
    return null;
  }

  Future<void> _writeDisk(String key, Uint8List bytes) async {
    try {
      final dir = await _cacheDir();
      final file = File('${dir.path}${Platform.pathSeparator}${_diskName(key)}');
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {
      // 写缓存失败不影响展示
    }
  }
}

class _PendingThumb {
  _PendingThumb({
    required this.device,
    required this.path,
    required this.key,
    required this.completer,
  });

  final DeviceInfo device;
  final String path;
  final String key;
  final Completer<Uint8List?> completer;
}
