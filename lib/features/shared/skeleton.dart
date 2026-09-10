import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/tokens.dart';

/// 网格骨架屏（列表加载占位，带 shimmer 流光动画）。
class SkeletonGrid extends StatelessWidget {
  const SkeletonGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Shimmer.fromColors(
      baseColor: palette.panel2,
      highlightColor: palette.panel,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount =
              (constraints.maxWidth / 140).floor().clamp(2, 8);
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.md),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 1,
            ),
            itemCount: crossAxisCount * 3,
            itemBuilder: (context, index) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _box(radius: AppRadius.md),
                ),
                const SizedBox(height: AppSpacing.sm),
                _box(width: 80, height: 12, radius: AppRadius.sm),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 列表骨架屏（列表加载占位，带 shimmer 流光动画）。
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Shimmer.fromColors(
      baseColor: palette.panel2,
      highlightColor: palette.panel,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 10,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            children: [
              _box(width: 44, height: 44, radius: AppRadius.sm),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(height: 14, radius: AppRadius.sm),
                    const SizedBox(height: AppSpacing.xs),
                    _box(width: 120, height: 12, radius: AppRadius.sm),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _box({
  double? width,
  double? height,
  required double radius,
}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
