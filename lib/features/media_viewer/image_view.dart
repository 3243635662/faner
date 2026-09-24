import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../core/tokens.dart';
import 'media_source.dart';

/// 可复用的图片查看器：手势缩放 + 点击空白区域退出。
class ImageView extends StatefulWidget {
  const ImageView({super.key, required this.source, this.onFullscreen});

  final MediaSource source;

  /// 全屏按钮回调；null 时不显示全屏按钮（独立全屏页）。
  final VoidCallback? onFullscreen;

  @override
  State<ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends State<ImageView> {
  final GlobalKey _imageKey = GlobalKey();

  void _handleTapUp(TapUpDetails details) {
    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(details.globalPosition);
    // 点击在图片区域之外 → 退出观看
    if (!box.size.contains(local)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final image = switch (widget.source) {
      LocalMediaSource(:final path) => Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _error(palette),
        ),
      RemoteMediaSource(:final url) => CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          placeholder: (_, _) =>
              const Center(child: CircularProgressIndicator()),
          errorWidget: (_, _, _) => _error(palette),
        ),
    };
    final viewer = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _handleTapUp,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4,
        child: Center(
          child: KeyedSubtree(
            key: _imageKey,
            child: Hero(tag: 'img_${widget.source.heroTag}', child: image),
          ),
        ),
      ),
    );
    final onFullscreen = widget.onFullscreen;
    if (onFullscreen == null) return viewer;
    return Stack(
      children: [
        Positioned.fill(child: viewer),
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.md,
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: IconButton(
              icon: const Icon(LucideIcons.maximize, color: Colors.white),
              onPressed: onFullscreen,
            ),
          ),
        ),
      ],
    );
  }

  Widget _error(AppPalette palette) => Center(
        child: Icon(LucideIcons.image_off, color: palette.muted, size: 64),
      );
}
