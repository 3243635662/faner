import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/tokens.dart';
import '../controllers/media_player_controller.dart';

/// 平板横屏播放页左侧的播放列表面板（方案「平板横屏布局」）。
///
/// 面板处于深色播放器区域内，因此固定使用"黑底白字"配色，
/// 不跟随 App 的亮/暗主题，避免浅色主题下白底白字。
class PlayerPlaylistPanel extends StatelessWidget {
  const PlayerPlaylistPanel({
    super.key,
    required this.controller,
    this.width = 264,
  });

  final MediaPlayerController controller;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: width,
      color: const Color(0xFF101216),
      child: SafeArea(
        right: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final state = controller.state;
            final playlist = controller.playlist;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.list_video,
                        size: 18,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '播放列表',
                        style: AppTypography.subtitle
                            .copyWith(color: Colors.white70),
                      ),
                      const Spacer(),
                      Text(
                        '${state.index + 1}/${playlist.length}',
                        style: AppTypography.caption
                            .copyWith(color: Colors.white38),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    itemCount: playlist.length,
                    itemBuilder: (context, index) {
                      final item = playlist[index];
                      final selected = index == state.index;
                      return InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: () => controller.jumpTo(index),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            vertical: AppSpacing.xs / 2,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? palette.brand.withValues(alpha: 0.20)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: AppSpacing.xl,
                                child: Text(
                                  '${index + 1}',
                                  style: AppTypography.caption.copyWith(
                                    color: selected
                                        ? palette.brand
                                        : Colors.white38,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.body.copyWith(
                                    color: selected
                                        ? Colors.white
                                        : Colors.white70,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (selected)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    left: AppSpacing.sm,
                                  ),
                                  child: Icon(
                                    LucideIcons.volume_2,
                                    size: 16,
                                    color: palette.brand,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
