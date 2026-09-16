import 'package:flutter/foundation.dart';

import '../../media_viewer/media_source.dart';

/// 播放器能接受的唯一输入：一个待播放的视频。
///
/// 播放器不关心文件来自本地磁盘还是局域网 HTTP —— 上游（文件列表 /
/// 远端浏览页）负责把 [MediaSource] 转换成 [MediaItem]，播放器只认 [uri]。
/// 这样本地文件、HTTP、以后的 WebDAV / SMB 都能走同一条链路。
@immutable
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.uri,
    required this.isLocal,
  });

  /// 稳定标识（本地绝对路径 / 远端 URL）。
  ///
  /// 断点续播的存储 key 与播放列表高亮都以它为准，不用标题（可能重名）。
  final String id;

  /// 展示用标题（文件名）。
  final String title;

  /// media_kit 可直接打开的地址。
  final String uri;

  /// 是否本地文件。
  final bool isLocal;

  /// 由通用媒体源构造（图片 / 视频共用 [MediaSource] 抽象）。
  factory MediaItem.fromSource(MediaSource source) => switch (source) {
        LocalMediaSource(:final path, :final title) => MediaItem(
            id: path,
            title: title.isEmpty ? _baseName(path) : title,
            uri: path,
            isLocal: true,
          ),
        RemoteMediaSource(:final url, :final title) => MediaItem(
            id: url,
            title: title.isEmpty ? _baseName(url) : title,
            uri: url,
            isLocal: false,
          ),
      };

  /// 批量转换（构造播放列表）。
  static List<MediaItem> listFromSources(List<MediaSource> sources) =>
      sources.map(MediaItem.fromSource).toList(growable: false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MediaItem && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MediaItem($id)';
}

/// 从路径 / URL 中取文件名，作为缺省标题。
String _baseName(String uri) {
  final withoutQuery = uri.split('?').first;
  final idx = withoutQuery.lastIndexOf('/');
  final name =
      idx == -1 ? withoutQuery : withoutQuery.substring(idx + 1);
  if (name.isEmpty) return uri;
  return Uri.decodeComponent(name);
}
