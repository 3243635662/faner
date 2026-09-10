// 临时冒烟测试：验证 /api/file 全量与 Range 请求是否正常。
import 'dart:io';

import 'package:faner/data/local/local_file_service.dart';
import 'package:faner/server/router.dart';
import 'package:faner/server/server_context.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late HttpServer server;
  final content = List<int>.generate(1000, (i) => i % 251);

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('faner_smoke');
    // 中文 + 空格 + 加号的文件名
    File(
      '${dir.path}${Platform.pathSeparator}测试 图片+1.mp4',
    ).writeAsBytesSync(content);
    final ctx = ServerContext(
      root: dir.path,
      deviceName: 'smoke',
      localFileService: LocalFileService(),
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(Router(ctx: ctx).handle);
  });

  tearDownAll(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  Future<(int, List<int>, Map<String, String>)> get(String url,
      {String? range}) async {
    final client = HttpClient();
    final req = await client.getUrl(Uri.parse(url));
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    final headers = <String, String>{};
    res.headers.forEach((k, v) => headers[k] = v.join(','));
    client.close();
    return (res.statusCode, body, headers);
  }

  test('/api/file 全量请求（模拟 Image.network）', () async {
    // 与 RemoteFileClient.fileUrl 相同的 URL 构造方式
    final url =
        'http://127.0.0.1:${server.port}/api/file?path=${Uri.encodeComponent('测试 图片+1.mp4')}';
    final (status, body, headers) = await get(url);
    expect(status, 200);
    expect(body, content);
    expect(headers['content-type'], 'video/mp4');
    expect(headers['accept-ranges'], 'bytes');
  });

  test('/api/file Range bytes=0-（模拟 video_player 探测）', () async {
    final url =
        'http://127.0.0.1:${server.port}/api/file?path=${Uri.encodeComponent('测试 图片+1.mp4')}';
    final (status, body, headers) = await get(url, range: 'bytes=0-');
    expect(status, 206);
    expect(body, content);
    expect(headers['content-range'], 'bytes 0-999/1000');
  });

  test('/api/file Range bytes=100-199（模拟拖动进度条）', () async {
    final url =
        'http://127.0.0.1:${server.port}/api/file?path=${Uri.encodeComponent('测试 图片+1.mp4')}';
    final (status, body, headers) = await get(url, range: 'bytes=100-199');
    expect(status, 206);
    expect(body, content.sublist(100, 200));
    expect(headers['content-range'], 'bytes 100-199/1000');
  });

  test('/api/file 后缀 Range bytes=-50', () async {
    final url =
        'http://127.0.0.1:${server.port}/api/file?path=${Uri.encodeComponent('测试 图片+1.mp4')}';
    final (status, body, _) = await get(url, range: 'bytes=-50');
    expect(status, 206);
    expect(body, content.sublist(950));
  });
}
