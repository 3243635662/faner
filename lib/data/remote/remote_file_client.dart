import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/result.dart';
import '../models/device_info.dart';
import '../models/file_entry.dart';

/// 远端设备 `/api/info` 返回内容。
class RemoteInfo {
  const RemoteInfo({
    required this.deviceName,
    required this.appVersion,
    required this.sharedRootLabel,
  });

  final String deviceName;
  final String appVersion;
  final String sharedRootLabel;
}

/// 封装对远端 Faner 设备的 HTTP 请求（Dio）。
class RemoteFileClient {
  RemoteFileClient()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 15),
            sendTimeout: const Duration(seconds: 10),
          ),
        );

  final Dio _dio;

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
      ));
    } on DioException catch (e) {
      return Err(_friendlyError(e));
    } catch (e) {
      return Err('请求失败：$e');
    }
  }

  Future<Result<List<FileEntry>>> list(DeviceInfo device, String path) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${device.baseUrl}/api/list',
        queryParameters: {'path': path},
        options: Options(responseType: ResponseType.json),
      );
      final data = res.data;
      if (data == null) return const Err('响应为空');
      final raw = data['entries'] as List<dynamic>? ?? const [];
      return Ok(raw
          .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
          .toList());
    } on DioException catch (e) {
      debugPrint(
        '[Faner] 请求列表失败 ${device.baseUrl}/api/list?path=$path → '
        '${e.type} (${e.message})',
      );
      return Err(_friendlyError(e));
    } catch (e) {
      return Err('读取失败：$e');
    }
  }

  Future<Result<List<FileEntry>>> search(DeviceInfo device, String query) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '${device.baseUrl}/api/search',
        queryParameters: {'q': query},
        options: Options(responseType: ResponseType.json),
      );
      final data = res.data;
      if (data == null) return const Err('响应为空');
      final raw = data['entries'] as List<dynamic>? ?? const [];
      return Ok(raw
          .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
          .toList());
    } on DioException catch (e) {
      return Err(_friendlyError(e));
    } catch (e) {
      return Err('搜索失败：$e');
    }
  }

  /// 组装文件下载 URL（供图片/视频/音频播放器直接使用）。
  String fileUrl(DeviceInfo device, String path) =>
      '${device.baseUrl}/api/file?path=${Uri.encodeComponent(path)}';

  /// 组装视频缩略图 URL（服务端原生生成 JPEG）。
  String thumbnailUrl(DeviceInfo device, String path) =>
      '${device.baseUrl}/api/thumbnail?path=${Uri.encodeComponent(path)}';

  static String _friendlyError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接超时，请确认设备在线';
      case DioExceptionType.connectionError:
        return '无法连接到设备';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        if (code == 404) return '路径不存在';
        if (code == 403) return '访问被拒绝';
        return '服务返回错误（$code）';
      default:
        return '网络错误';
    }
  }
}
