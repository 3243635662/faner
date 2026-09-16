import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';

import '../../../core/tokens.dart';

/// 可选播放倍速。
const List<double> kPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

/// 底部倍速选择面板；用户取消时返回 null。
Future<double?> showPlaybackSpeedSheet(
  BuildContext context, {
  required double current,
}) {
  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final palette = AppPalette.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.gauge, size: 20, color: palette.brand),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '播放倍速',
                    style: AppTypography.subtitle.copyWith(color: palette.text),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final speed in kPlaybackSpeeds)
                    ChoiceChip(
                      label: Text(_label(speed)),
                      selected: (speed - current).abs() < 0.01,
                      onSelected: (_) => Navigator.of(sheetContext).pop(speed),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// `1.0x` / `1.25x`，整数倍速不显示多余小数位。
String _label(double speed) {
  final text = speed == speed.roundToDouble()
      ? speed.toInt().toString()
      : speed.toString();
  return '${text}x';
}
