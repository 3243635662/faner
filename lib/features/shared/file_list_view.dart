import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../core/format.dart';
import '../../core/timeline_utils.dart';
import '../../core/tokens.dart';
import '../../data/models/file_entry.dart';
import 'file_thumbnail.dart';

/// 文件列表视图（列表布局，展示名称 + 大小 + 修改时间，支持时间轴分组展示）。
class FileListView extends StatelessWidget {
  const FileListView({
    super.key,
    required this.entries,
    required this.fileResolver,
    required this.isRemote,
    required this.onTap,
    this.onLongPress,
    this.thumbnailResolver,
    this.thumbnailLoader,
    this.selectedPath,
    this.storageKey,
    this.onDoubleTap,
    this.groupByTimeline = false,
  });

  final List<FileEntry> entries;
  final String Function(FileEntry) fileResolver;
  final String Function(FileEntry)? thumbnailResolver;

  /// 远程缩略图批量装载器（可选）。
  final Future<Uint8List?> Function(FileEntry)? thumbnailLoader;
  final bool isRemote;
  final ValueChanged<FileEntry> onTap;
  final ValueChanged<FileEntry>? onLongPress;

  /// 当前选中项路径（平板双栏高亮用）。
  final String? selectedPath;

  /// 滚动位置持久化标识。挂到 [PageStorageKey] 上，使列表在布局切换
  /// （平板横竖屏双栏↔单栏）与进出目录时保留滚动位置；为空则不持久化。
  final String? storageKey;

  /// 双击列表项回调（媒体直接全屏沉浸式观看）。
  final ValueChanged<FileEntry>? onDoubleTap;

  /// 是否启用时间轴分组展示
  final bool groupByTimeline;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    if (!groupByTimeline) {
      return ListView.separated(
        key: storageKey == null
            ? null
            : PageStorageKey<String>('list:$storageKey'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: entries.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: palette.line),
        itemBuilder: (context, index) {
          final entry = entries[index];
          return _FileListTile(
            entry: entry,
            selected: entry.path == selectedPath,
            thumbnail: FileThumbnail(
              entry: entry,
              fileResolver: fileResolver,
              isRemote: isRemote,
              thumbnailResolver: thumbnailResolver,
              thumbnailLoader: thumbnailLoader,
              iconSize: 40,
            ),
            onTap: () => onTap(entry),
            onDoubleTap: onDoubleTap == null ? null : () => onDoubleTap!(entry),
            onLongPress: onLongPress == null ? null : () => onLongPress!(entry),
          );
        },
      );
    }

    final sections = groupEntriesByTimeline(entries);
    return CustomScrollView(
      key: storageKey == null
          ? null
          : PageStorageKey<String>('list_tl:$storageKey'),
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        for (final section in sections) ...[
          SliverToBoxAdapter(
            child: Container(
              color: palette.panel,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Text(
                    section.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: palette.text,
                        ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '(${section.entries.length})',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.muted,
                        ),
                  ),
                ],
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = section.entries[index];
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FileListTile(
                      entry: entry,
                      selected: entry.path == selectedPath,
                      thumbnail: FileThumbnail(
                        entry: entry,
                        fileResolver: fileResolver,
                        isRemote: isRemote,
                        thumbnailResolver: thumbnailResolver,
                        thumbnailLoader: thumbnailLoader,
                        iconSize: 40,
                      ),
                      onTap: () => onTap(entry),
                      onDoubleTap:
                          onDoubleTap == null ? null : () => onDoubleTap!(entry),
                      onLongPress:
                          onLongPress == null ? null : () => onLongPress!(entry),
                    ),
                    if (index < section.entries.length - 1)
                      Divider(height: 1, color: palette.line),
                  ],
                );
              },
              childCount: section.entries.length,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
      ],
    );
  }
}

class _FileListTile extends StatelessWidget {
  const _FileListTile({
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
    final subtitle = entry.isFolder
        ? '文件夹 · ${formatDateTime(entry.modifiedAt)}'
        : '${entry.formattedSize} · ${formatDateTime(entry.modifiedAt)}';
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected ? palette.brand.withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: thumbnail,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                          color: selected ? palette.brand : palette.text,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: palette.muted),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevron_right, color: palette.muted),
          ],
        ),
      ),
    );
  }
}
