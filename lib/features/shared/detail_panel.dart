import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../core/file_type.dart';
import '../../core/tokens.dart';
import '../../data/models/file_entry.dart';
import '../media_player/models/media_item.dart';
import '../media_player/widgets/video_preview_panel.dart';
import '../media_viewer/image_view.dart';
import '../media_viewer/media_source.dart';

/// 平板主从布局右侧详情面板，原地预览选中项。
class DetailPanel extends StatelessWidget {
  const DetailPanel({
    super.key,
    required this.entry,
    required this.resolver,
    required this.isRemote,
    required this.onOpenFullscreen,
  });

  final FileEntry? entry;
  final String Function(FileEntry) resolver;
  final bool isRemote;

  /// 全屏打开媒体（由父级构造完整同类型列表并 push 全屏路由）。
  final void Function(FileEntry entry) onOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final current = entry;
    if (current == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.mouse_pointer_click, size: 56, color: palette.muted),
            const SizedBox(height: AppSpacing.md),
            Text('选择文件以在此预览', style: TextStyle(color: palette.muted)),
          ],
        ),
      );
    }

    // 用 path 作 key，切换选中项时强制重建播放器
    return KeyedSubtree(
      key: ValueKey(current.path),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: _buildPreview(context, current),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, FileEntry entry) {
    final palette = AppPalette.of(context);
    switch (entry.type) {
      case EntryType.folder:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.folder, size: 72, color: palette.amber),
              const SizedBox(height: AppSpacing.md),
              Text(entry.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text('点击列表中的文件夹进入', style: TextStyle(color: palette.muted)),
            ],
          ),
        );
      case EntryType.image:
        return ImageView(
          source: mediaSourceFor(entry, resolver, isRemote),
          onFullscreen: () => onOpenFullscreen(entry),
        );
      case EntryType.video:
        return VideoPreviewPanel(
          items: [MediaItem.fromSource(mediaSourceFor(entry, resolver, isRemote))],
          onOpenFullscreen: () => onOpenFullscreen(entry),
        );
      case EntryType.audio:
      // 音频文件不提供内置播放，与其它未知类型一样只展示文件信息
      case EntryType.other:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.file, size: 64, color: palette.muted),
              const SizedBox(height: AppSpacing.md),
              Text(entry.name, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${entry.formattedSize} · 暂不支持预览',
                style: TextStyle(color: palette.muted),
              ),
            ],
          ),
        );
    }
  }
}
