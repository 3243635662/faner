import 'package:flutter/material.dart';

import '../../core/tokens.dart';
import '../../data/models/file_entry.dart';
import 'file_thumbnail.dart';

/// 手机/平板通用的文件网格组件（本地/远程复用）。
class FileGridView extends StatelessWidget {
  const FileGridView({
    super.key,
    required this.entries,
    required this.fileResolver,
    required this.isRemote,
    required this.onTap,
    this.onLongPress,
    this.thumbnailResolver,
    this.selectedPath,
    this.storageKey,
    this.onDoubleTap,
  });

  final List<FileEntry> entries;

  /// 解析条目为「绝对路径（本地）」或「完整 URL（远程）」。
  final String Function(FileEntry) fileResolver;

  /// 解析视频条目为缩略图 URL（仅远程视频需要，服务端生成）。
  final String Function(FileEntry)? thumbnailResolver;
  final bool isRemote;
  final ValueChanged<FileEntry> onTap;
  final ValueChanged<FileEntry>? onLongPress;

  /// 当前选中项路径（平板双栏高亮用）。
  final String? selectedPath;

  /// 滚动位置持久化标识。挂到 [PageStorageKey] 上，使网格在布局切换
  /// （平板横竖屏双栏↔单栏）与进出目录时保留滚动位置；为空则不持久化。
  final String? storageKey;

  /// 双击列表项回调（媒体直接全屏沉浸式观看）。
  final ValueChanged<FileEntry>? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = (constraints.maxWidth / 140).floor().clamp(2, 8);
        return GridView.builder(
          key: storageKey == null
              ? null
              : PageStorageKey<String>('grid:$storageKey'),
          padding: const EdgeInsets.all(AppSpacing.md),
          physics: const AlwaysScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            childAspectRatio: 1,
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return _FileCell(
              entry: entry,
              selected: entry.path == selectedPath,
              thumbnail: FileThumbnail(
                entry: entry,
                fileResolver: fileResolver,
                isRemote: isRemote,
                thumbnailResolver: thumbnailResolver,
                iconSize: 48,
                showMeta: true,
              ),
              onTap: () => onTap(entry),
              onDoubleTap: onDoubleTap == null ? null : () => onDoubleTap!(entry),
              onLongPress: onLongPress == null ? null : () => onLongPress!(entry),
            );
          },
        );
      },
    );
  }
}

class _FileCell extends StatelessWidget {
  const _FileCell({
    required this.entry,
    required this.thumbnail,
    required this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.selected = false,
  });

  final FileEntry entry;
  final Widget thumbnail;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.panel2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: selected
                    ? Border.all(color: palette.brand, width: 2)
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: thumbnail,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(
                  color: selected ? palette.brand : palette.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
          ),
        ],
      ),
    );
  }
}
