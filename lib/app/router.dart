import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/models/device_info.dart';
import '../features/devices/devices_page.dart';
import '../features/local_browser/local_browser_page.dart';
import '../features/media_viewer/audio_player_page.dart';
import '../features/media_viewer/image_viewer_page.dart';
import '../features/media_viewer/media_source.dart';
import '../features/media_viewer/video_player_page.dart';
import '../features/remote_browser/remote_browser_page.dart';
import '../features/settings/settings_page.dart';
import '../home/home_shell.dart';
import '../providers/browser_provider.dart';

/// 全局路由表（Navigator 2.0 / go_router）。
///
/// - 底部导航三个 tab 用 [StatefulShellRoute] 承载，切 tab 保持各自状态；
/// - 远程浏览器与媒体查看页是顶级全屏路由，系统返回键会正确回退到列表。
final GoRouter appRouter = GoRouter(
  initialLocation: '/files',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          HomeShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/files',
            builder: (context, state) => const LocalBrowserPage(),
            // 系统返回键：路径非空时回上级目录，而不是退出应用
            // （PopScope 与 go_router 存在兼容性问题，改用 onExit 拦截）
            onExit: (context, state) {
              final container = ProviderScope.containerOf(context,
                  listen: false);
              final path = container.read(localPathProvider);
              if (path.isNotEmpty) {
                container
                    .read(localPathProvider.notifier)
                    .set(_parentOf(path));
                return false;
              }
              return true;
            },
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/devices',
            builder: (context, state) => const DevicesPage(),
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ]),
      ],
    ),
    GoRoute(
      path: '/remote',
      builder: (context, state) =>
          RemoteBrowserPage(device: state.extra! as DeviceInfo),
      onExit: (context, state) {
        final container = ProviderScope.containerOf(context, listen: false);
        final path = container.read(remotePathProvider);
        if (path.isNotEmpty) {
          container.read(remotePathProvider.notifier).set(_parentOf(path));
          return false;
        }
        return true;
      },
    ),
    GoRoute(
      path: '/image',
      builder: (context, state) {
        final extra = state.extra!
            as ({List<MediaSource> items, int index, bool fromSplit});
        return ImageViewerPage(
          items: extra.items,
          initialIndex: extra.index,
          fromSplit: extra.fromSplit,
        );
      },
    ),
    GoRoute(
      path: '/video',
      builder: (context, state) {
        final extra = state.extra!
            as ({List<MediaSource> items, int index, bool fromSplit});
        return VideoPlayerPage(
          items: extra.items,
          initialIndex: extra.index,
          fromSplit: extra.fromSplit,
        );
      },
    ),
    GoRoute(
      path: '/audio',
      builder: (context, state) {
        final source = state.extra! as MediaSource;
        return AudioPlayerPage(source: source);
      },
    ),
  ],
);

/// 返回父路径（'a/b/c' -> 'a/b'，'a' -> ''）。
String _parentOf(String path) {
  final idx = path.lastIndexOf('/');
  return idx == -1 ? '' : path.substring(0, idx);
}
