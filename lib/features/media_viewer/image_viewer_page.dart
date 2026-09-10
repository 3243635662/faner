import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import 'media_source.dart';

/// 沉浸式图片查看页：左右滑动切换 + 点击空白退出。
class ImageViewerPage extends StatefulWidget {
  const ImageViewerPage({
    super.key,
    required this.items,
    required this.initialIndex,
  });

  final List<MediaSource> items;
  final int initialIndex;

  @override
  State<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends State<ImageViewerPage> {
  late final PageController _pageController;
  late int _currentIndex;
  final Map<int, double> _aspectRatios = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadAspectRatio(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _loadAspectRatio(int index) {
    if (index < 0 || index >= widget.items.length) return;
    if (_aspectRatios.containsKey(index)) return;
    final source = widget.items[index];
    final ImageProvider<Object> provider = switch (source) {
      LocalMediaSource(:final path) => FileImage(File(path)),
      RemoteMediaSource(:final url) => NetworkImage(url),
    };
    final stream = provider.resolve(const ImageConfiguration());
    stream.addListener(ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        if (info.image.width > 0 && info.image.height > 0) {
          setState(() {
            _aspectRatios[index] = info.image.width / info.image.height;
          });
        }
      },
      onError: (_, _) {},
    ));
  }

  void _onTapUp(
    BuildContext context,
    TapUpDetails details,
    PhotoViewControllerValue controllerValue,
  ) {
    final viewport = MediaQuery.of(context).size;
    final aspect = _aspectRatios[_currentIndex];
    if (aspect == null) return; // 图片尺寸未知时不退出
    final scale = controllerValue.scale ?? 1.0;
    // contain 后的图片尺寸
    final Size imgSize = viewport.width / viewport.height > aspect
        ? Size(viewport.height * aspect, viewport.height)
        : Size(viewport.width, viewport.width / aspect);
    final scaled = imgSize * scale;
    final center = Offset(viewport.width / 2, viewport.height / 2) +
        controllerValue.position;
    final rect = Rect.fromCenter(
      center: center,
      width: scaled.width,
      height: scaled.height,
    );
    if (!rect.contains(details.globalPosition)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PhotoViewGallery.builder(
        scrollPhysics: const BouncingScrollPhysics(),
        builder: (context, index) {
          final source = widget.items[index];
          return PhotoViewGalleryPageOptions(
            imageProvider: switch (source) {
              LocalMediaSource(:final path) => FileImage(File(path)),
              RemoteMediaSource(:final url) => NetworkImage(url),
            },
            heroAttributes: PhotoViewHeroAttributes(tag: 'img_${source.heroTag}'),
            minScale: PhotoViewComputedScale.contained * 0.8,
            maxScale: PhotoViewComputedScale.covered * 4,
            onTapUp: _onTapUp,
          );
        },
        itemCount: widget.items.length,
        pageController: _pageController,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          _loadAspectRatio(index);
        },
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        loadingBuilder: (context, progress) =>
            const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
