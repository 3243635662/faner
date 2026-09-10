import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../core/file_type.dart';
import '../../core/tokens.dart';
import '../../core/video_thumbnail.dart';
import '../../data/models/file_entry.dart';

/// 文件缩略图 / 图标组件（网格与列表复用）。
///
/// 图片与远程视频直接铺满显示；本地视频用原生缩略图（磁盘缓存）；
/// 远程图片/缩略图走 [CachedNetworkImage] 做磁盘缓存，减少重复下载与解码。
class FileThumbnail extends StatelessWidget {
  const FileThumbnail({
    super.key,
    required this.entry,
    required this.fileResolver,
    required this.isRemote,
    this.thumbnailResolver,
    this.iconSize = 44,
  });

  final FileEntry entry;
  final String Function(FileEntry) fileResolver;
  final bool isRemote;
  final String Function(FileEntry)? thumbnailResolver;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (entry.type == EntryType.image) {
      final url = fileResolver(entry);
      return Hero(
        tag: 'img_$url',
        child: isRemote
            ? _network(url, palette)
            : Image.file(
                File(url),
                fit: BoxFit.cover,
                cacheWidth: 240,
                cacheHeight: 240,
                errorBuilder: (_, _, _) => _fallback(palette),
              ),
      );
    }
    if (entry.type == EntryType.video) {
      if (isRemote) {
        final resolver = thumbnailResolver;
        if (resolver != null) {
          return _network(resolver(entry), palette);
        }
      } else {
        return VideoThumbnail(path: fileResolver(entry));
      }
    }
    return _fallback(palette);
  }

  Widget _network(String url, AppPalette palette) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 240,
      placeholder: (_, _) => ColoredBox(color: palette.panel2),
      errorWidget: (_, _, _) => _fallback(palette),
    );
  }

  Widget _fallback(AppPalette palette) => Center(child: _icon(palette));

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
