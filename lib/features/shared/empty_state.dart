import 'package:flutter/material.dart';

import '../../core/tokens.dart';

/// 统一的空状态/提示视图：图标 + 标题 + 副标题 + 可选操作。
///
/// 用于无文件、无设备、无权限等场景，保证全项目空态风格一致。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: palette.muted),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              style: AppTypography.subtitle.copyWith(color: palette.muted),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                style: AppTypography.caption.copyWith(color: palette.muted),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
