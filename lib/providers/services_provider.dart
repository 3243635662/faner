import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/local_file_service.dart';
import '../data/remote/discovery_service.dart';
import '../data/remote/remote_file_client.dart';

/// 全局服务单例。
final localFileServiceProvider =
    Provider<LocalFileService>((ref) => LocalFileService());

final remoteFileClientProvider =
    Provider<RemoteFileClient>((ref) => RemoteFileClient());

final discoveryServiceProvider =
    Provider<DiscoveryService>((ref) => DiscoveryService());
