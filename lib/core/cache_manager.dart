import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'image_thumbnail.dart';
import 'video_thumbnail.dart';

/// 缓存管理服务：提供磁盘与内存缓存的大小计算与一键清空能力。
class AppCacheManager {
  const AppCacheManager._();

  /// 计算当前所有图片、视频缩略图及网络缓存占用的磁盘字节数。
  static Future<int> getCacheSizeBytes() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      if (!await cacheDir.exists()) return 0;
      return await _dirSize(cacheDir);
    } catch (_) {
      return 0;
    }
  }

  /// 一键清理所有本地磁盘与内存缓存。
  ///
  /// 返回清理前占用的字节数。
  static Future<int> clearAllCache() async {
    final beforeBytes = await getCacheSizeBytes();

    // 1. 清理临时目录下的所有磁盘缓存（包括 CachedNetworkImage、image_thumbs、video_thumbs 等）
    try {
      final temp = await getTemporaryDirectory();
      if (await temp.exists()) {
        await for (final entity in temp.list(followLinks: false)) {
          try {
            if (entity is Directory) {
              await entity.delete(recursive: true);
            } else if (entity is File) {
              await entity.delete();
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 2. 清空 Flutter 引擎内存图片缓存
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}

    // 3. 清理缩略图自定义内存缓存
    clearImageThumbnailMemCache();
    clearVideoThumbnailMemCache();

    return beforeBytes;
  }

  static Future<int> _dirSize(Directory dir) async {
    int total = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }
}

/// 缓存大小 Provider，用于在 UI（设置页）响应式展示并刷新。
final cacheSizeProvider =
    AsyncNotifierProvider<CacheSizeNotifier, int>(CacheSizeNotifier.new);

class CacheSizeNotifier extends AsyncNotifier<int> {
  @override
  Future<int> build() async => AppCacheManager.getCacheSizeBytes();

  /// 刷新缓存大小读数
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(AppCacheManager.getCacheSizeBytes);
  }

  /// 执行一键清理并重置大小
  Future<int> clear() async {
    state = const AsyncLoading();
    final clearedBytes = await AppCacheManager.clearAllCache();
    state = const AsyncData(0);
    return clearedBytes;
  }
}
