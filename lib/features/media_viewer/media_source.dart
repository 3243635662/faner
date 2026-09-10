import '../../data/models/file_entry.dart';

/// 媒体数据源：本地绝对路径 或 远端 URL。
sealed class MediaSource {
  const MediaSource({this.title = ''});

  /// 媒体标题（文件名），用于播放器显示。
  final String title;

  /// Hero 动画 tag：与文件缩略图保持一致。
  String get heroTag;
}

class LocalMediaSource extends MediaSource {
  const LocalMediaSource(this.path, {super.title});

  final String path;

  @override
  String get heroTag => path;
}

class RemoteMediaSource extends MediaSource {
  const RemoteMediaSource(this.url, {super.title});

  final String url;

  @override
  String get heroTag => url;
}

/// 根据条目与解析器构造媒体源。
MediaSource mediaSourceFor(
  FileEntry entry,
  String Function(FileEntry) resolver,
  bool isRemote,
) {
  final value = resolver(entry);
  return isRemote
      ? RemoteMediaSource(value, title: entry.name)
      : LocalMediaSource(value, title: entry.name);
}
