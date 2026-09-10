import 'package:flutter/material.dart';

import '../../core/breakpoints.dart';
import '../../core/tokens.dart';

/// 响应式主从布局容器。
///
/// 宽度 >= 840dp 时左侧列表 + 右侧详情双栏；否则只显示列表。
class BrowserScaffold extends StatelessWidget {
  const BrowserScaffold({
    super.key,
    required this.list,
    required this.detail,
  });

  final Widget list;
  final Widget detail;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= Breakpoints.medium) {
          return Row(
            children: [
              Expanded(flex: 2, child: list),
              VerticalDivider(width: 1, color: AppPalette.of(context).line),
              Expanded(flex: 3, child: detail),
            ],
          );
        }
        return list;
      },
    );
  }
}
