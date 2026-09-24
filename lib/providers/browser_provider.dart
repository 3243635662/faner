import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/result.dart';
import '../data/models/device_info.dart';
import '../data/models/file_entry.dart';
import 'services_provider.dart';

/// 本地浏览：当前相对路径。
final localPathProvider =
    NotifierProvider<LocalPathNotifier, String>(LocalPathNotifier.new);

class LocalPathNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String path) => state = path;
}

/// 远程浏览：当前路径（全局，供 go_router onExit 拦截系统返回键）。
final remotePathProvider =
    NotifierProvider<RemotePathNotifier, String>(RemotePathNotifier.new);

class RemotePathNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String path) => state = path;
}

/// 本地浏览：按路径加载文件列表。
final localBrowserProvider =
    FutureProvider.autoDispose.family<List<FileEntry>, String>((ref, path) async {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 3), () => link.close());
  ref.onDispose(() => timer.cancel());

  final svc = ref.watch(localFileServiceProvider);
  final result = await svc.listEntries(path);
  return result.fold(
    (v) => v,
    (err) => throw BrowserException(err),
  );
});

/// 远程浏览的缓存键（设备 + 路径）。
class RemoteBrowseKey {
  const RemoteBrowseKey(this.device, this.path);

  final DeviceInfo device;
  final String path;

  @override
  bool operator ==(Object other) =>
      other is RemoteBrowseKey &&
      other.device == device &&
      other.path == path;

  @override
  int get hashCode => Object.hash(device, path);
}

/// 远程浏览：按设备 + 路径加载文件列表。
final remoteBrowserProvider = FutureProvider.autoDispose
    .family<List<FileEntry>, RemoteBrowseKey>((ref, key) async {
  // 保持缓存 5 分钟，避免全屏预览媒体后返回列表反复闪现骨架屏
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), () => link.close());
  ref.onDispose(() => timer.cancel());

  final client = ref.watch(remoteFileClientProvider);
  final result = await client.list(key.device, key.path);
  switch (result) {
    case Ok(:final value):
      return value;
    case Err(:final message, :final code):
      // 保留错误码（如 unauthorized），供页面区分「需要口令」与普通失败。
      throw BrowserException(message, code: code);
  }
});

/// 平板主从布局中"当前选中项"，供左右面板共享。
final selectedEntryProvider =
    NotifierProvider<SelectedEntryNotifier, FileEntry?>(SelectedEntryNotifier.new);

class SelectedEntryNotifier extends Notifier<FileEntry?> {
  @override
  FileEntry? build() => null;

  void select(FileEntry? entry) => state = entry;
}

/// 浏览错误，UI 层统一展示。
class BrowserException implements Exception {
  const BrowserException(this.message, {this.code});

  final String message;

  /// 机器可读错误码（如 [ErrorCodes.unauthorized]）。
  final String? code;

  @override
  String toString() => message;
}
