import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/breakpoints.dart';
import '../providers/server_provider.dart';
import '../providers/settings_provider.dart';

/// 底部导航 / 侧边栏壳，承载三个 tab（文件 / 设备 / 设置）。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await ref.read(settingsProvider.notifier).ensureLoaded();
    if (!mounted) return;
    final settings = ref.read(settingsProvider);
    if (settings.autoStartServer) {
      ref.read(serverControllerProvider.notifier).start();
    }
  }

  void _onDestinationSelected(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = widget.navigationShell;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= Breakpoints.compact;
        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: nav.currentIndex,
                  onDestinationSelected: _onDestinationSelected,
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(LucideIcons.folder),
                      selectedIcon: Icon(LucideIcons.folder),
                      label: Text('文件'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(LucideIcons.tablet),
                      selectedIcon: Icon(LucideIcons.tablet),
                      label: Text('设备'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(LucideIcons.settings),
                      selectedIcon: Icon(LucideIcons.settings),
                      label: Text('设置'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: nav),
              ],
            ),
          );
        }
        return Scaffold(
          body: nav,
          bottomNavigationBar: NavigationBar(
            selectedIndex: nav.currentIndex,
            onDestinationSelected: _onDestinationSelected,
            destinations: const [
              NavigationDestination(
                icon: Icon(LucideIcons.folder),
                selectedIcon: Icon(LucideIcons.folder),
                label: '文件',
              ),
              NavigationDestination(
                icon: Icon(LucideIcons.tablet),
                selectedIcon: Icon(LucideIcons.tablet),
                label: '设备',
              ),
              NavigationDestination(
                icon: Icon(LucideIcons.settings),
                selectedIcon: Icon(LucideIcons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }
}
