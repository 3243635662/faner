import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/auth.dart';
import '../../core/result.dart';
import '../models/device_info.dart';
import '../models/file_entry.dart';

/// 远端设备 `/api/info` 返回内容。
class RemoteInfo {
  const RemoteInfo({
    required this.deviceName,
    required this.appVersion,
    required this.sharedRootLabel,
    required this.authRequired,
  });

  final String deviceName;
  final String appVersion;
  final String sharedRootLabel;

  /// 对方是否开启了口令保护（连接前即可得知，用于提前索要口令）。
  final bool authRequired;
}

/// 封装对远端 Faner 设备的 HTTP 请求（Dio）。
class RemoteFileClient {
  RemoteFileClient({this.credentials = const {}})
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 10),
            // 配合服务端的 gzip 压缩：3000+ 条目的目录列表 JSON 体积骤降 80%～90%。
            headers: const {HttpHeaders.acceptEncodingHeader: 'gzip'},
          ),
        );

  final Dio _dio;

  /// 设备名 → 共享口令（由 deviceCredentialsProvider 注入）。
  final Map<String, String> credentials;

  /// 取该设备已保存的口令（未保存返回 null）。
  String? tokenOf(DeviceInfo device) {
    final t = credentials[device.deviceName];
    return (t == null || t.isEmpty) ? null : t;
  }

  Map<String, dynamic>? _authHeaders(DeviceInfo device) {
    final t = tokenOf(device);
    return t == null ? null : {authHeaderName: t};
  }

  /// 媒体地址（图片/视频）无法自定义 header，口令走 query 参数。
  String _withToken(DeviceInfo device, String url) {
    final t = tokenOf(device);
    if (t == null) return url;
    return '$url&$authQueryParam=${Uri.encodeComponent(t)}';
  }

  /// 请求 `/api/info`，同时用于连通性校验。
  Future<Result<RemoteInfo>> fetchInfo(DeviceInfo device) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${device.baseUrl}/api/info',
        options: Options(responseType: ResponseType.json),
      );
      final data = res.data;
      if (data == null) return const Err('响应为空');
      return Ok(RemoteInfo(
        deviceName: data['deviceName'] as String? ?? device.deviceName,
        appVersion: data['appVersion'] as String? ?? '',
        sharedRootLabel: data['sharedRootLabel'] as String? ?? '',
        authRequired: data['authRequired'] as bool? ?? false,
      ));
    } on DioException catch (e) {
      return _toError(e);
    } catch (e) {
      return Err('请求失败：$e');
    }
  }

  Future<Result<List<FileEntry>>> list(DeviceInfo device, String path) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${device.baseUrl}/api/list',
        queryParameters: {'path': path},
        options: Options(
          responseType: ResponseType.json,
          headers: _authHeaders(device),
        ),
      );
      final data = res.data;
      if (data == null) return const Err('响应为空');
      // 紧凑线格式省略了每个条目的 path，用服务端下发的父目录拼回。
      final dirPath = data['currentPath'] as String? ?? path;
      final raw = data['entries'] as List<dynamic>? ?? const [];
      return Ok(raw
          .map((e) =>
              FileEntry.fromJson(e as Map<String, dynamic>, dirPath: dirPath))
          .toList());
    } on DioException catch (e) {
      debugPrint(
        '[Faner] 请求列表失败 ${device.baseUrl}/api/list?path=$path → '
        '${e.type} (${e.message})',
      );
      return _toError(e);
    } catch (e) {
      return Err('读取失败：$e');
    }
  }

  Future<Result<List<FileEntry>>> search(DeviceInfo device, String query) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${device.baseUrl}/api/search',
        queryParameters: {'q': query},
        options: Options(
          responseType: ResponseType.json,
          headers: _authHeaders(device),
        ),
      );
      final data = res.data;
      if (data == null) return const Err('响应为空');
      final raw = data['entries'] as List<dynamic>? ?? const [];
      return Ok(raw
          .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
          .toList());
    } on DioException catch (e) {
      return _toError(e);
    } catch (e) {
      return Err('搜索失败：$e');
    }
  }

  /// 批量拉取缩略图：一次往返拿回数十张，避免弱网下逐张请求的延迟叠加。
  Future<Result<Map<String, Uint8List?>>> thumbnails(
    DeviceInfo device,
    List<String> paths, {
    int max = 48,
  }) async {
    if (paths.isEmpty) return const Ok(<String, Uint8List?>{});
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${device.baseUrl}/api/thumbs',
        queryParameters: {'path': paths.take(max).toList()},
        options: Options(
          responseType: ResponseType.json,
          headers: _authHeaders(device),
          receiveTimeout: const Duration(seconds: 30),
        ),
      );
      final raw = res.data?['thumbs'] as Map<String, dynamic>? ?? const {};
      final out = <String, Uint8List?>{};
      raw.forEach((k, v) {
        // 单个条目解码失败不应拖垮整批
        out[k] = v is String ? _tryDecode(v) : null;
      });
      return Ok(out);
    } on DioException catch (e) {
      return _toError(e);
    } catch (e) {
      return Err('读取缩略图失败：$e');
    }
  }

  /// 组装文件下载 URL（供图片/视频播放器直接使用）。
  String fileUrl(DeviceInfo device, String path) => _withToken(
        device,
        '${device.baseUrl}/api/file?path=${Uri.encodeComponent(path)}',
      );

  /// 组装缩略图 URL（服务端原生生成 PNG/JPEG）。
  String thumbnailUrl(DeviceInfo device, String path) => _withToken(
        device,
        '${device.baseUrl}/api/thumbnail?path=${Uri.encodeComponent(path)}',
      );

  /// 组装目录变更事件（SSE）地址。
  Uri eventsUri(DeviceInfo device, String path) {
    final token = tokenOf(device);
    return Uri.parse('${device.baseUrl}/api/events').replace(
      queryParameters: {
        'path': path,
        authQueryParam: ?token,
      },
    );
  }

  static Uint8List? _tryDecode(String base64) {
    try {
      return base64Decode(base64);
    } catch (_) {
      return null;
    }
  }

  Err<T> _toError<T>(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const Err('连接超时，请确认设备在线');
      case DioExceptionType.connectionError:
        return const Err('无法连接到设备');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == HttpStatus.unauthorized) {
          return const Err('需要共享口令', code: ErrorCodes.unauthorized);
        }
        if (code == HttpStatus.notFound) return const Err('路径不存在');
        if (code == HttpStatus.forbidden) return const Err('访问被拒绝');
        return Err('服务返回错误（$code）');
      default:
        return const Err('网络错误');
    }
  }
}
