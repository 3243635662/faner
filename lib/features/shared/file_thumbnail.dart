import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../core/file_type.dart';
import '../../core/format.dart';
import '../../core/media_metadata.dart';
import '../../core/tokens.dart';
import '../../core/video_thumbnail.dart';
import '../../data/models/file_entry.dart';

/// 文件缩略图 / 图标组件（网格视图与列表视图复用同一组件）。
///
/// 设计要点：
/// - 图片与远程视频：直接铺满显示（远程走网络缓存）。
/// - 本地视频：用原生缩略图（[VideoThumbnail]，磁盘缓存到本地）。
/// - 远程图片/缩略图：走 [CachedNetworkImage] 做磁盘缓存，减少重复下载与解码开销。
/// - 其他类型（文件夹、音频、未知文件）：退化为类型图标。
class FileThumbnail extends StatelessWidget {
  /// 创建文件缩略图组件。
  ///
  /// [entry]             当前要展示的文件条目（含类型、名称、远程/本地等元信息）。
  /// [fileResolver]      把 entry 解析为本地路径或远程 URL 的函数；
  ///                     本地场景返回磁盘绝对路径，远程场景返回 http(s) 地址。
  /// [isRemote]          是否为远程文件（true 走网络，false 读本地磁盘）。
  /// [thumbnailResolver] 远程视频缩略图解析器（可选）；
  ///                     仅 isRemote==true 且服务端能提供缩略图 URL 时使用，
  ///                     为 null 时远程视频退化为类型图标。
  /// [iconSize]          退化图标（文件夹/音频等）的边长尺寸，默认 44。
  /// [showMeta]          是否在右下角叠加元数据角标（目前仅本地视频显示时长），默认 false。
  const FileThumbnail({
    super.key,
    required this.entry,
    required this.fileResolver,
    required this.isRemote,
    this.thumbnailResolver,
    this.iconSize = 44,
    this.showMeta = false,
  });

  /// 当前要展示的文件条目（含类型、名称、远程/本地等元信息）。
  final FileEntry entry;

  /// 把 entry 解析为本地路径或远程 URL 的函数。
  /// 本地场景下返回磁盘绝对路径；远程场景下返回 http(s) 地址。
  final String Function(FileEntry) fileResolver;

  /// 是否为远程文件（走网络，而非本地磁盘）。
  final bool isRemote;

  /// 远程视频缩略图解析器（可选）。
  /// 仅当 isRemote==true 且远程服务端能提供缩略图 URL 时使用；
  /// 为 null 时远程视频将退化为类型图标。
  final String Function(FileEntry)? thumbnailResolver;

  /// 退化图标（文件夹/音频等）的边长尺寸，默认 44。
  final double iconSize;

  /// 是否在右下角叠加元数据角标（目前仅本地视频显示时长）。
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    // 取当前主题的调色板（来自 tokens.dart 的 AppPalette），供图标/占位色使用。
    final palette = AppPalette.of(context);

    // —— 图片类型 ——
    if (entry.type == EntryType.image) {
      final url = fileResolver(entry);
      return Hero(
        // Hero 动画 tag，用于点击图片放大到详情页时的共享元素过渡。
        tag: 'img_$url',
        child: isRemote
            // 远程图片：走网络缓存组件，磁盘 + 内存双缓存。
            ? _network(url, palette)
            // 本地图片：直接读文件，cacheWidth/Height 限制解码尺寸以省内存。
            : Image.file(
                File(url),
                fit: BoxFit.cover,
                cacheWidth: 240,
                cacheHeight: 240,
                // 解码/读取失败时退化为类型图标，避免出现红屏。
                errorBuilder: (_, _, _) => _fallback(palette),
              ),
      );
    }

    // —— 视频类型 ——
    if (entry.type == EntryType.video) {
      if (isRemote) {
        // 远程视频：若服务端提供了缩略图 URL 则显示，否则退化。
        final resolver = thumbnailResolver;
        if (resolver != null) {
          return _network(resolver(entry), palette);
        }
      } else {
        // 本地视频：用原生缩略图组件（内部已做磁盘缓存）。
        final thumb = VideoThumbnail(path: fileResolver(entry));
        // 不需要角标时直接返回缩略图即可。
        if (!showMeta) return thumb;
        // 需要角标时在缩略图右下角叠加视频时长标签。
        return Stack(
          fit: StackFit.expand,
          children: [
            thumb,
            Positioned(
              right: AppSpacing.xs,
              bottom: AppSpacing.xs,
              // 角标内会异步探测时长；无本地路径或探测失败则自动隐藏。
              child: _VideoDurationBadge(path: fileResolver(entry)),
            ),
          ],
        );
      }
    }

    // —— 其他（文件夹 / 音频 / 未知）—— 退化为类型图标。
    return _fallback(palette);
  }

  /// 远程资源通用渲染：网络图片 + 缓存 + 占位/错误兜底。
  Widget _network(String url, AppPalette palette) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      // 内存缓存限制解码宽度，避免大图占用过多内存。
      memCacheWidth: 240,
      // 加载中占位：用面板色块填充，保持布局稳定。
      placeholder: (_, _) => ColoredBox(color: palette.panel2),
      // 加载失败同样退化为图标，不抛红屏。
      errorWidget: (_, _, _) => _fallback(palette),
    );
  }

  /// 退化布局：居中显示类型图标。
  Widget _fallback(AppPalette palette) => Center(child: _icon(palette));

  /// 按文件类型返回对应图标、颜色与尺寸。
  Icon _icon(AppPalette palette) => switch (entry.type) {
        EntryType.folder =>
          Icon(LucideIcons.folder, color: palette.amber, size: iconSize),
        EntryType.video =>
          Icon(LucideIcons.circle_play, color: palette.brand, size: iconSize),
        EntryType.audio =>
          Icon(LucideIcons.music, color: palette.sky, size: iconSize),
        _ => Icon(LucideIcons.file, color: palette.muted, size: iconSize),
      };
}

/// 视频时长角标（本地视频，右下角）。
///
/// 通过 [fetchVideoDuration] 异步探测本地视频时长，
/// 成功则显示 "mm:ss" 文本，失败/无时长则返回一个零尺寸占位（不显示）。
class _VideoDurationBadge extends StatelessWidget {
  const _VideoDurationBadge({required this.path});

  /// 本地视频的绝对路径，交给时长探测模块解析。
  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Duration?>(
      // 绑定异步探测任务；模块内部带缓存与串行队列，重复构建不会重复探测。
      future: fetchVideoDuration(path),
      builder: (context, snapshot) {
        final duration = snapshot.data;
        // 未完成（data 为 null）或探测失败：不占空间。
        if (duration == null) return const SizedBox.shrink();
        // 成功：格式化为 "mm:ss" 并交给角标控件渲染。
        return _Badge(text: formatDuration(duration));
      },
    );
  }
}

/// 半透明黑底 + 白色小字的右下角角标。
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  /// 角标显示的文本（如视频时长 "12:34"）。
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      // 内边距走设计 Token（AppSpacing），避免魔法数字。
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        // 半透明黑色背景，保证在任意画面内容上可读。
        color: Colors.black54,
        // 圆角走设计 Token（AppRadius）。
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: AppTypography.caption.copyWith(
          color: Colors.white,
          fontSize: 11,
        ),
      ),
    );
  }
}
