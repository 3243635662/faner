import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device_info.dart';

/// 目录变更事件（Server-Sent Events）客户端。
///
/// 与远端建立 `text/event-stream` 长连接，服务端在该目录内容变化时下发事件。
/// 相比客户端定时轮询：延迟更低，空闲时几乎零流量。
class EventsClient {
  /// 订阅 [device] 上 [path] 目录的变更事件。
  ///
  /// 返回的流在取消订阅时自动断开底层连接；连接失败（如未带口令）会静默结束，
  /// 调用方降级为手动刷新即可。
  Stream<void> watch(DeviceInfo device, String path, {String? token}) {
    final controller = StreamController<void>();
    HttpClient? client;
    var cancelled = false;

    Future<void> closeQuietly() async {
      if (cancelled || controller.isClosed) return;
      await controller.close();
    }

    Future<void> connect() async {
      try {
        final http = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5);
        client = http;
        final uri = Uri.parse('${device.baseUrl}/api/events').replace(
          queryParameters: {
            'path': path,
            if (token != null && token.isNotEmpty) 'token': token,
          },
        );
        final req = await http.getUrl(uri);
        req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final res = await req.close();
        if (res.statusCode != HttpStatus.ok) {
          await closeQuietly();
          return;
        }
        res
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            if (cancelled) return;
            if (line.startsWith('event:') && line.contains('change')) {
              controller.add(null);
            }
          },
          onError: (Object _) {},
          onDone: () {
            if (!cancelled) controller.close();
          },
          cancelOnError: false,
        );
      } catch (_) {
        await closeQuietly();
      }
    }

    controller.onListen = () => unawaited(connect());
    controller.onCancel = () async {
      cancelled = true;
      client?.close(force: true);
    };
    return controller.stream;
  }
}
