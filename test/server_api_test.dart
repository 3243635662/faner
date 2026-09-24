// 服务端接口契约测试：gzip 压缩、共享口令鉴权、紧凑列表格式、
// 批量缩略图、目录变更事件（SSE）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:faner/core/change_bus.dart';
import 'package:faner/core/result.dart';
import 'package:faner/data/local/local_file_service.dart';
import 'package:faner/data/models/file_entry.dart';
import 'package:faner/server/router.dart';
import 'package:faner/server/server_context.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1x1 透明 PNG（< 60KB，服务端缩略图走原图直通分支，无需解码）。
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/'
    'q842iQAAAABJRU5ErkJggg==';

void main() {
  late Directory dir;
  late HttpServer plainServer;
  late HttpServer authServer;
  const password = 'secret';
  const secretPath = '子目录/照片 1.png';

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('faner_api');
    File('${dir.path}${Platform.pathSeparator}测试 视频+1.mp4')
        .writeAsBytesSync(List<int>.generate(64, (i) => i));
    File('${dir.path}${Platform.pathSeparator}photo.png')
        .writeAsBytesSync(base64Decode(_tinyPngBase64));
    Directory('${dir.path}${Platform.pathSeparator}子目录').createSync();
    File('${dir.path}${Platform.pathSeparator}子目录${Platform.pathSeparator}照片 1.png')
        .writeAsBytesSync(base64Decode(_tinyPngBase64));
    // 根目录塞够条目，让 JSON 超过 gzip 压缩阈值（1KB）
    for (var i = 0; i < 40; i++) {
      File('${dir.path}${Platform.pathSeparator}file_$i.txt')
          .writeAsStringSync('payload $i');
    }

    // 用 rootOverride 固定共享根，避免依赖外部存储探测（测试环境无 Android）。
    ServerContext ctxWith({String? pwd}) => ServerContext(
          root: dir.path,
          deviceName: 'test-device',
          localFileService: LocalFileService(rootOverride: dir.path),
          password: pwd == null ? noPassword : () => pwd,
        );

    plainServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    plainServer.listen(Router(ctx: ctxWith()).handle);

    authServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    authServer.listen(Router(ctx: ctxWith(pwd: password)).handle);
  });

  tearDownAll(() async {
    await plainServer.close(force: true);
    await authServer.close(force: true);
    dir.deleteSync(recursive: true);
  });

  Uri uriOf(HttpServer server, String path, [Map<String, String>? query]) =>
      Uri.parse('http://127.0.0.1:${server.port}$path')
          .replace(queryParameters: query);

  /// 发请求并默认**关闭自动解压**，以便断言 gzip 相关响应头。
  Future<({int status, List<int> body, Map<String, String> headers})> send(
    Uri uri, {
    String? acceptEncoding,
    String? token,
    bool autoUncompress = false,
  }) async {
    final client = HttpClient()..autoUncompress = autoUncompress;
    final req = await client.getUrl(uri);
    if (acceptEncoding != null) {
      req.headers.set(HttpHeaders.acceptEncodingHeader, acceptEncoding);
    }
    if (token != null) req.headers.set('x-auth-token', token);
    final res = await req.close();
    final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    final headers = <String, String>{};
    res.headers.forEach((k, v) => headers[k] = v.join(','));
    client.close();
    return (status: res.statusCode, body: body, headers: headers);
  }

  Map<String, dynamic> decodeJson(List<int> body, Map<String, String> headers) {
    final raw = headers[HttpHeaders.contentEncodingHeader] == 'gzip'
        ? GZipCodec().decode(body)
        : body;
    return jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  }

  group('gzip', () {
    test('大响应在客户端声明 gzip 时压缩，并保持内容等价', () async {
      // 显式声明 identity：dart:io 的 HttpClient 默认会自动带上 gzip，
      // 这里要一个"明确不要压缩"的基线（服务端对 < 1KB 的响应也不压缩）。
      final plain = await send(
        uriOf(plainServer, '/api/list', {'path': ''}),
        acceptEncoding: 'identity',
      );
      expect(plain.status, 200);
      expect(plain.headers[HttpHeaders.contentEncodingHeader], isNull);

      final gzipped = await send(
        uriOf(plainServer, '/api/list', {'path': ''}),
        acceptEncoding: 'gzip',
      );
      expect(gzipped.status, 200);
      expect(gzipped.headers[HttpHeaders.contentEncodingHeader], 'gzip');
      // 压缩后体积必须更小
      expect(gzipped.body.length, lessThan(plain.body.length));

      final decoded = decodeJson(gzipped.body, gzipped.headers);
      final expected = decodeJson(plain.body, plain.headers);
      expect(decoded['entries'], expected['entries']);

      // 自动解压（真实客户端行为）后应能正常解析
      final auto = await send(
        uriOf(plainServer, '/api/list', {'path': ''}),
        acceptEncoding: 'gzip',
        autoUncompress: true,
      );
      final autoJson = jsonDecode(utf8.decode(auto.body)) as Map<String, dynamic>;
      expect(autoJson['entries'], expected['entries']);
    });

    test('q=0 表示客户端拒绝 gzip，服务端不得压缩', () async {
      final res = await send(
        uriOf(plainServer, '/api/list', {'path': ''}),
        acceptEncoding: 'gzip;q=0',
      );
      expect(res.status, 200);
      expect(res.headers[HttpHeaders.contentEncodingHeader], isNull);
    });
  });

  group('紧凑列表格式', () {
    test('条目省略 path、时间用 epoch 毫秒，客户端可拼回路径', () async {
      final res = await send(
        uriOf(plainServer, '/api/list', {'path': '子目录'}),
      );
      expect(res.status, 200);
      final data = decodeJson(res.body, res.headers);
      expect(data['currentPath'], '子目录');

      final entries = data['entries'] as List<dynamic>;
      expect(entries, hasLength(1));
      final first = entries.first as Map<String, dynamic>;
      // 线格式：无 path、无 ISO 字符串时间
      expect(first.containsKey('path'), isFalse);
      expect(first.containsKey('modifiedAt'), isFalse);
      expect(first['mtime'], isA<int>());

      // 客户端按 currentPath 拼回完整条目
      final entry = FileEntry.fromJson(
        first,
        dirPath: data['currentPath'] as String,
      );
      expect(entry.path, secretPath);
      expect(entry.name, '照片 1.png');
    });
  });

  group('共享口令鉴权', () {
    test('/api/info 免口令且暴露 authRequired', () async {
      final plain = await send(uriOf(plainServer, '/api/info'));
      expect(plain.status, 200);
      expect(decodeJson(plain.body, plain.headers)['authRequired'], isFalse);

      final auth = await send(uriOf(authServer, '/api/info'));
      expect(auth.status, 200);
      expect(decodeJson(auth.body, auth.headers)['authRequired'], isTrue);
    });

    test('无口令时所有接口放行', () async {
      final res = await send(uriOf(plainServer, '/api/list', {'path': ''}));
      expect(res.status, 200);
    });

    test('开启口令后未带令牌返回 401', () async {
      final res = await send(uriOf(authServer, '/api/list', {'path': ''}));
      expect(res.status, 401);
    });

    test('令牌正确时放行，错误时 401', () async {
      final byQuery = await send(
        uriOf(authServer, '/api/list', {'path': '', 'token': password}),
      );
      expect(byQuery.status, 200);

      final byHeader = await send(
        uriOf(authServer, '/api/list', {'path': ''}),
        token: password,
      );
      expect(byHeader.status, 200);

      final wrong = await send(
        uriOf(authServer, '/api/list', {'path': '', 'token': 'wrong'}),
      );
      expect(wrong.status, 401);
    });

    test('媒体接口同样受口令保护（query 令牌可用）', () async {
      final noToken = await send(
        uriOf(authServer, '/api/file', {'path': 'photo.png'}),
      );
      expect(noToken.status, 401);

      final withToken = await send(
        uriOf(authServer, '/api/file', {'path': 'photo.png', 'token': password}),
      );
      expect(withToken.status, 200);
      expect(withToken.body, base64Decode(_tinyPngBase64));
    });
  });

  group('批量缩略图 /api/thumbs', () {
    test('一次往返返回多张缩略图（base64 内嵌）', () async {
      final res = await send(Uri.parse(
        'http://127.0.0.1:${plainServer.port}/api/thumbs'
        '?path=${Uri.encodeComponent('photo.png')}'
        '&path=${Uri.encodeComponent('子目录/照片 1.png')}',
      ));
      expect(res.status, 200);
      final thumbs =
          decodeJson(res.body, res.headers)['thumbs'] as Map<String, dynamic>;
      expect(thumbs.keys, containsAll(['photo.png', secretPath]));

      final bytes = base64Decode(thumbs['photo.png'] as String);
      expect(bytes, base64Decode(_tinyPngBase64));
    });

    test('不存在 / 非法路径返回 null 而不是整批失败', () async {
      final res = await send(Uri.parse(
        'http://127.0.0.1:${plainServer.port}/api/thumbs'
        '?path=${Uri.encodeComponent('nope.png')}'
        '&path=${Uri.encodeComponent('../secret.png')}'
        '&path=${Uri.encodeComponent('photo.png')}',
      ));
      expect(res.status, 200);
      final thumbs =
          decodeJson(res.body, res.headers)['thumbs'] as Map<String, dynamic>;
      expect(thumbs['nope.png'], isNull);
      expect(thumbs['../secret.png'], isNull);
      expect(thumbs['photo.png'], isNotNull);
    });

    test('缺少 path 参数返回 400', () async {
      final res = await send(uriOf(plainServer, '/api/thumbs'));
      expect(res.status, 400);
    });
  });

  group('路径穿越防护', () {
    test('list / file / thumbnail 对 .. 一律 403', () async {
      final list = await send(uriOf(plainServer, '/api/list', {'path': '../'}));
      expect(list.status, 403);
      final file = await send(uriOf(plainServer, '/api/file', {'path': '../x.png'}));
      expect(file.status, 403);
      final thumb = await send(
        uriOf(plainServer, '/api/thumbnail', {'path': '../x.png'}),
      );
      expect(thumb.status, 403);
    });
  });

  group('目录列举（独立 isolate）', () {
    test('文件夹优先、文件按修改时间倒序，路径用 / 拼接', () async {
      final tmp = await Directory.systemTemp.createTemp('faner_list');
      addTearDown(() => tmp.deleteSync(recursive: true));
      Directory('${tmp.path}${Platform.pathSeparator}子目录').createSync();
      final older = File('${tmp.path}${Platform.pathSeparator}a.png')
        ..writeAsBytesSync([1])
        ..setLastModifiedSync(DateTime(2020, 1, 1));
      File('${tmp.path}${Platform.pathSeparator}b.png')
        ..writeAsBytesSync([2])
        ..setLastModifiedSync(DateTime(2021, 1, 1));
      expect(older.lengthSync(), 1);

      final svc = LocalFileService(rootOverride: tmp.path);
      final result = await svc.listEntries('');
      switch (result) {
        case Ok(:final value):
          // 文件夹优先；文件按修改时间倒序（b 更新）
          expect(value.map((e) => e.name).toList(), ['子目录', 'b.png', 'a.png']);
          expect(value[0].isFolder, isTrue);
          expect(value[0].sizeBytes, -1);
          // 相对路径统一用 / 分隔
          expect(value.every((e) => !e.path.contains('\\')), isTrue);
        case Err(:final message):
          fail('列举失败：$message');
      }
    });

    test('目录不存在时报错', () async {
      final tmp = await Directory.systemTemp.createTemp('faner_list_missing');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final svc = LocalFileService(rootOverride: tmp.path);
      final result = await svc.listEntries('不存在');
      expect(result.isErr, isTrue);
    });
  });

  group('目录变更事件 (SSE)', () {
    test('连接后目录变化即推送 change 事件', () async {
      final client = HttpClient();
      final req = await client
          .getUrl(uriOf(plainServer, '/api/events', {'path': ''}));
      final res = await req.close();
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'text/event-stream');

      final gotChange = Completer<void>();
      final sub = res
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.startsWith('event:') && line.contains('change')) {
          if (!gotChange.isCompleted) gotChange.complete();
        }
      });

      // 服务端有 200ms 事件合并窗口，先等过窗口再触发
      await Future<void>.delayed(const Duration(milliseconds: 350));
      ChangeBus.instance.notifyDir('');

      await gotChange.future.timeout(const Duration(seconds: 5));
      await sub.cancel();
      client.close(force: true);
    });

    test('口令保护下未带令牌的连接被拒绝', () async {
      final client = HttpClient();
      final req = await client
          .getUrl(uriOf(authServer, '/api/events', {'path': ''}));
      final res = await req.close();
      expect(res.statusCode, 401);
      client.close(force: true);
    });
  });
}
