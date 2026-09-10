import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// 本地浏览：按路径加载文件列表。
final localBrowserProvider =
    FutureProvider.autoDispose.family<List<FileEntry>, String>((ref, path) async {
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
  final client = ref.watch(remoteFileClientProvider);
  final result = await client.list(key.device, key.path);
  return result.fold(
    (v) => v,
    (err) => throw BrowserException(err),
  );
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
  const BrowserException(this.message);

  final String message;

  @override
  String toString() => message;
}
