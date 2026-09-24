import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/local_file_service.dart';
import '../data/remote/discovery_service.dart';
import '../data/remote/events_client.dart';
import '../data/remote/remote_file_client.dart';
import '../data/remote/thumbnail_batch_loader.dart';
import 'credentials_provider.dart';

/// 全局服务单例。
final localFileServiceProvider =
    Provider<LocalFileService>((ref) => LocalFileService());

/// 远端请求客户端：注入已保存的共享口令，口令变更后自动重建。
final remoteFileClientProvider = Provider<RemoteFileClient>((ref) {
  final credentials = ref.watch(deviceCredentialsProvider);
  return RemoteFileClient(credentials: credentials);
});

/// 远程缩略图批量装载器（合批 + 两级缓存）。
final thumbnailBatchLoaderProvider = Provider<ThumbnailBatchLoader>((ref) {
  final client = ref.watch(remoteFileClientProvider);
  final loader = ThumbnailBatchLoader(client);
  ref.onDispose(loader.dispose);
  return loader;
});

final discoveryServiceProvider =
    Provider<DiscoveryService>((ref) => DiscoveryService());

/// 目录变更事件（SSE）客户端。
final eventsClientProvider = Provider<EventsClient>((ref) => EventsClient());
