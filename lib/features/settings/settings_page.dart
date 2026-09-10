import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/prompts.dart';
import '../../core/tokens.dart';
import '../../core/video_play_mode.dart';
import '../../permissions/storage_permission.dart';
import '../../providers/server_provider.dart';
import '../../providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final server = ref.watch(serverControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          _sectionHeader(context, '外观'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('跟随系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('深色'),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) => ref
                  .read(settingsProvider.notifier)
                  .setThemeMode(selection.first),
            ),
          ),
          const Divider(),
          _sectionHeader(context, '播放'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SegmentedButton<VideoPlayMode>(
              segments: const [
                ButtonSegment(
                  value: VideoPlayMode.sequential,
                  label: Text('顺序'),
                ),
                ButtonSegment(
                  value: VideoPlayMode.shuffle,
                  label: Text('随机'),
                ),
                ButtonSegment(
                  value: VideoPlayMode.loop,
                  label: Text('循环'),
                ),
              ],
              selected: {settings.videoPlayMode},
              onSelectionChanged: (selection) => ref
                  .read(settingsProvider.notifier)
                  .setVideoPlayMode(selection.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, 0),
            child: Text(
              '视频播放完毕后的连播方式（手动切换上一个/下一个不受影响）',
              style: AppTypography.caption
                  .copyWith(color: AppPalette.of(context).muted),
            ),
          ),
          const Divider(),
          _sectionHeader(context, '设备'),
          _tile(
            context,
            icon: LucideIcons.id_card,
            title: '设备名称',
            subtitle: settings.deviceName.isEmpty ? '未设置' : settings.deviceName,
            onTap: () => _editDeviceName(context, ref, settings.deviceName),
          ),
          SwitchListTile(
            secondary: const Icon(LucideIcons.wifi),
            title: const Text('局域网共享'),
            subtitle: Text(_serverSubtitle(server)),
            value: settings.serverEnabled,
            onChanged: (v) => _toggleServer(context, ref, v),
          ),
          const Divider(),
          _sectionHeader(context, '存储'),
          _tile(
            context,
            icon: LucideIcons.folder_open,
            title: '存储权限',
            subtitle: '浏览本机文件所需',
            trailing: _PermissionStatus(),
            onTap: () async {
              await StoragePermission.ensure();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('权限状态已更新')),
                );
              }
            },
          ),
          const Divider(),
          _sectionHeader(context, '关于'),
          const ListTile(
            leading: Icon(LucideIcons.info),
            title: Text('Faner'),
            subtitle: Text('轻量化局域网文件管理与媒体互看'),
          ),
          ListTile(
            leading: const Icon(LucideIcons.hash),
            title: const Text('版本'),
            subtitle: Text(AppConstants.appVersion),
          ),
        ],
      ),
    );
  }

  String _serverSubtitle(ServerState server) {
    return switch (server.status) {
      ServerStatus.running => '运行中 · 端口 ${server.port}',
      ServerStatus.starting => '正在启动…',
      ServerStatus.error => '启动失败，点击重试',
      ServerStatus.stopped => '已关闭',
    };
  }

  Future<void> _toggleServer(
      BuildContext context, WidgetRef ref, bool enabled) async {
    await ref.read(settingsProvider.notifier).setServerEnabled(enabled);
    if (enabled) {
      await ref.read(serverControllerProvider.notifier).start();
    } else {
      await ref.read(serverControllerProvider.notifier).stop();
    }
  }

  Future<void> _editDeviceName(
      BuildContext context, WidgetRef ref, String current) async {
    final name = await showTextPrompt(
      context,
      title: '设备名称',
      hint: '输入设备名称',
      initial: current,
      confirmLabel: '保存',
    );
    if (name == null || name.isEmpty) return;
    await ref.read(settingsProvider.notifier).setDeviceName(name);
    // 设备名变化后若服务器在运行，重启以重新广播
    final server = ref.read(serverControllerProvider);
    if (server.status == ServerStatus.running) {
      await ref.read(serverControllerProvider.notifier).stop();
      await ref.read(serverControllerProvider.notifier).start();
    }
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Text(
        title,
        style: TextStyle(
          color: palette.muted,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing ?? const Icon(LucideIcons.chevron_right),
      onTap: onTap,
    );
  }
}

class _PermissionStatus extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    return FutureBuilder<bool>(
      future: StoragePermission.isGranted(),
      builder: (context, snapshot) {
        final granted = snapshot.data ?? false;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              granted ? LucideIcons.circle_check : LucideIcons.circle_alert,
              color: granted ? palette.green : palette.red,
              size: 18,
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(LucideIcons.chevron_right, color: palette.muted),
          ],
        );
      },
    );
  }
}
