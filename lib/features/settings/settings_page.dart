import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth.dart';
import '../../core/cache_manager.dart';
import '../../core/constants.dart';
import '../../core/format.dart';
import '../../core/prompts.dart';
import '../../core/seek_sensitivity.dart';
import '../../core/tokens.dart';
import '../../core/video_play_mode.dart';
import '../../core/video_resume.dart';
import '../../permissions/storage_permission.dart';
import '../../providers/server_provider.dart';
import '../../providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final server = ref.watch(serverControllerProvider);
    final palette = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: AppSpacing.xxxl,
        ),
        children: [
          // -------------------------------------------------------------------
          // 外观
          // -------------------------------------------------------------------
          const _SettingsSectionHeader(
            title: '外观主题',
            icon: LucideIcons.palette,
          ),
          _SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(LucideIcons.sun_moon, size: 16),
                      label: Text('跟随系统'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(LucideIcons.sun, size: 16),
                      label: Text('浅色'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(LucideIcons.moon, size: 16),
                      label: Text('深色'),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) => ref
                      .read(settingsProvider.notifier)
                      .setThemeMode(selection.first),
                ),
              ),
            ],
          ),

          // -------------------------------------------------------------------
          // 网络与共享
          // -------------------------------------------------------------------
          const _SettingsSectionHeader(title: '网络与共享', icon: LucideIcons.wifi),
          _SettingsCard(
            children: [
              _SettingsSwitchTile(
                icon: LucideIcons.wifi,
                iconColor: palette.brand,
                title: '局域网共享',
                subtitleWidget: _buildServerSubtitle(server, palette),
                value:
                    server.status == ServerStatus.running ||
                    server.status == ServerStatus.starting,
                onChanged: (v) => _toggleServer(context, ref, v),
              ),
              _divider(palette),
              _SettingsSwitchTile(
                icon: LucideIcons.zap,
                iconColor: palette.amber,
                title: '启动时自动开启共享',
                subtitle: '下次进入应用时自动启动局域网共享服务',
                value: settings.autoStartServer,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setAutoStartServer(v),
              ),
              _divider(palette),
              _SettingsTile(
                icon: LucideIcons.smartphone,
                iconColor: palette.sky,
                title: '设备名称',
                subtitle: '在局域网中对其他设备展示的识别名称',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + 2,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: palette.panel2,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        settings.deviceName.isEmpty
                            ? '未设置'
                            : settings.deviceName,
                        style: AppTypography.caption.copyWith(
                          color: palette.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      LucideIcons.chevron_right,
                      size: 18,
                      color: palette.muted,
                    ),
                  ],
                ),
                onTap: () => _editDeviceName(context, ref, settings.deviceName),
              ),
              _divider(palette),
              _SettingsTile(
                icon: LucideIcons.lock,
                iconColor: palette.green,
                title: '共享密码',
                subtitle: settings.sharePassword.isEmpty
                    ? '未设置 · 同网设备可直接访问本机文件'
                    : '已开启 · 对方连接本机时需输入口令',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + 2,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: palette.panel2,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        settings.sharePassword.isEmpty ? '未设置' : '已设置',
                        style: AppTypography.caption.copyWith(
                          color: settings.sharePassword.isEmpty
                              ? palette.muted
                              : palette.green,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      LucideIcons.chevron_right,
                      size: 18,
                      color: palette.muted,
                    ),
                  ],
                ),
                onTap: () =>
                    _editSharePassword(context, ref, settings.sharePassword),
              ),
            ],
          ),

          // -------------------------------------------------------------------
          // 视频播放
          // -------------------------------------------------------------------
          const _SettingsSectionHeader(title: '视频播放', icon: LucideIcons.film),
          _SettingsCard(
            children: [
              _SegmentedSection(
                title: '连播方式',
                subtitle: '单集播放完毕后的连播动作（上一集/下一集不受影响）',
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
                    ButtonSegment(value: VideoPlayMode.loop, label: Text('循环')),
                  ],
                  selected: {settings.videoPlayMode},
                  onSelectionChanged: (selection) => ref
                      .read(settingsProvider.notifier)
                      .setVideoPlayMode(selection.first),
                ),
              ),
              _divider(palette),
              _SegmentedSection(
                title: '长按倍速',
                subtitle: '播放中长按视频画面的临时加速倍率',
                child: SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 1.5, label: Text('1.5x')),
                    ButtonSegment(value: 2.0, label: Text('2.0x')),
                    ButtonSegment(value: 3.0, label: Text('3.0x')),
                  ],
                  selected: {settings.longPressSpeed},
                  onSelectionChanged: (selection) => ref
                      .read(settingsProvider.notifier)
                      .setLongPressSpeed(selection.first),
                ),
              ),
              _divider(palette),
              _SegmentedSection(
                title: '滑动快进/快退灵敏度',
                subtitle:
                    '当前轻扫 1 厘米约跳转 ${settings.seekSensitivity.secondsPerCentimeter} 秒',
                child: SegmentedButton<SeekSensitivity>(
                  segments: [
                    for (final sensitivity in SeekSensitivity.values)
                      ButtonSegment(
                        value: sensitivity,
                        label: Text(sensitivity.label),
                      ),
                  ],
                  selected: {settings.seekSensitivity},
                  onSelectionChanged: (selection) => ref
                      .read(settingsProvider.notifier)
                      .setSeekSensitivity(selection.first),
                ),
              ),
              _divider(palette),
              _SettingsSwitchTile(
                icon: LucideIcons.clock,
                iconColor: palette.green,
                title: '记住播放进度',
                subtitle: '退出后自动记录并支持断点续播',
                value: settings.rememberProgress,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setRememberProgress(v),
              ),
              _divider(palette),
              _SettingsTile(
                icon: LucideIcons.trash,
                iconColor: palette.red,
                title: '清除播放进度',
                subtitle: '清空所有视频的历史播放进度与断点记录',
                onTap: () => _clearResume(context),
              ),
            ],
          ),

          // -------------------------------------------------------------------
          // 存储与系统
          // -------------------------------------------------------------------
          const _SettingsSectionHeader(
            title: '存储与权限',
            icon: LucideIcons.hard_drive,
          ),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: LucideIcons.folder_open,
                iconColor: palette.amber,
                title: '存储读取权限',
                subtitle: '浏览本机媒体文件与提供共享所必需',
                trailing: _PermissionStatus(),
                onTap: () async {
                  await StoragePermission.ensure();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('权限状态已更新')));
                  }
                },
              ),
              _divider(palette),
              const _CacheTile(),
            ],
          ),

          // -------------------------------------------------------------------
          // 关于
          // -------------------------------------------------------------------
          const _SettingsSectionHeader(title: '关于', icon: LucideIcons.info),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: LucideIcons.sparkles,
                iconColor: palette.brand,
                title: 'Faner',
                subtitle: '轻量化局域网文件管理与媒体互看',
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm + 2,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: palette.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'v${AppConstants.appVersion}',
                    style: AppTypography.caption.copyWith(
                      color: palette.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _divider(AppPalette palette) => Divider(
    height: 1,
    thickness: 1,
    indent: 64,
    color: palette.line.withValues(alpha: 0.5),
  );

  Widget _buildServerSubtitle(ServerState server, AppPalette palette) {
    final (dotColor, text) = switch (server.status) {
      ServerStatus.running => (palette.green, '运行中 · 端口 ${server.port}'),
      ServerStatus.starting => (palette.amber, '正在启动…'),
      ServerStatus.error => (palette.red, '启动失败，点击重试'),
      ServerStatus.stopped => (palette.muted, '已关闭'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs + 2),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: palette.muted),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleServer(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    await ref.read(settingsProvider.notifier).setServerEnabled(enabled);
    if (enabled) {
      await ref.read(serverControllerProvider.notifier).start();
    } else {
      await ref.read(serverControllerProvider.notifier).stop();
    }
  }

  Future<void> _editDeviceName(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final name = await showTextPrompt(
      context,
      title: '设备名称',
      hint: '输入设备名称',
      initial: current,
      confirmLabel: '保存',
    );
    if (name == null || name.isEmpty) return;
    await ref.read(settingsProvider.notifier).setDeviceName(name);
    final server = ref.read(serverControllerProvider);
    if (server.status == ServerStatus.running) {
      await ref.read(serverControllerProvider.notifier).stop();
      await ref.read(serverControllerProvider.notifier).start();
    }
  }

  Future<void> _editSharePassword(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final value = await showTextPrompt(
      context,
      title: '共享密码',
      hint: '留空表示关闭口令保护',
      initial: current,
      confirmLabel: '保存',
      validator: (v) {
        final p = v.trim();
        if (p.isEmpty) return null; // 允许留空以关闭口令
        if (p.length < minPasswordLength) {
          return '至少 $minPasswordLength 位';
        }
        return null;
      },
    );
    if (value == null) return;
    await ref.read(settingsProvider.notifier).setSharePassword(value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value.trim().isEmpty ? '已关闭共享口令保护' : '已开启共享口令保护',
        ),
      ),
    );
  }

  Future<void> _clearResume(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除播放进度'),
        content: const Text('确定要清空所有视频的断点记忆吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await VideoResumeStore.clearAll();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除所有视频播放进度')));
    }
  }
}

// -----------------------------------------------------------------------------
// 卡片与组件定义 (Modern Grouped Cards & Squircles)
// -----------------------------------------------------------------------------

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.line.withValues(alpha: 0.6)),
        boxShadow: AppShadow.sm(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _IconSquircle extends StatelessWidget {
  const _IconSquircle({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _SettingsSectionHeader extends StatelessWidget {
  const _SettingsSectionHeader({required this.title, this.icon});

  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: palette.muted),
            const SizedBox(width: AppSpacing.xs + 2),
          ],
          Text(
            title,
            style: TextStyle(
              color: palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 2,
      ),
      leading: _IconSquircle(icon: icon, color: iconColor),
      title: Text(
        title,
        style: AppTypography.subtitle.copyWith(
          fontWeight: FontWeight.w600,
          color: palette.text,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: AppTypography.caption.copyWith(color: palette.muted),
            ),
      trailing:
          trailing ??
          (onTap != null
              ? Icon(LucideIcons.chevron_right, size: 18, color: palette.muted)
              : null),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  const _SettingsSwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.subtitleWidget,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 2,
      ),
      secondary: _IconSquircle(icon: icon, color: iconColor),
      title: Text(
        title,
        style: AppTypography.subtitle.copyWith(
          fontWeight: FontWeight.w600,
          color: palette.text,
        ),
      ),
      subtitle:
          subtitleWidget ??
          (subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: AppTypography.caption.copyWith(color: palette.muted),
                )),
      value: value,
      onChanged: onChanged,
      activeTrackColor: palette.brand,
    );
  }
}

class _SegmentedSection extends StatelessWidget {
  const _SegmentedSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTypography.subtitle.copyWith(
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.caption.copyWith(color: palette.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
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
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: (granted ? palette.green : palette.amber).withValues(
                  alpha: 0.12,
                ),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    granted
                        ? LucideIcons.circle_check
                        : LucideIcons.circle_alert,
                    color: granted ? palette.green : palette.amber,
                    size: 14,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    granted ? '已授权' : '去授权',
                    style: AppTypography.caption.copyWith(
                      color: granted ? palette.green : palette.amber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(LucideIcons.chevron_right, size: 18, color: palette.muted),
          ],
        );
      },
    );
  }
}

class _CacheTile extends ConsumerWidget {
  const _CacheTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final cacheState = ref.watch(cacheSizeProvider);

    final String sizeText = cacheState.when(
      data: (bytes) => formatBytes(bytes),
      loading: () => '计算中...',
      error: (_, _) => '未知',
    );

    return _SettingsTile(
      icon: LucideIcons.trash,
      iconColor: palette.sky,
      title: '媒体与网络缓存',
      subtitle: '包括缩略图与网络原图缓存（当前：$sizeText）',
      trailing: TextButton(
        onPressed: cacheState.isLoading
            ? null
            : () => _handleClear(context, ref, cacheState.value ?? 0),
        child: const Text('清理'),
      ),
      onTap: cacheState.isLoading
          ? null
          : () => _handleClear(context, ref, cacheState.value ?? 0),
    );
  }

  Future<void> _handleClear(
    BuildContext context,
    WidgetRef ref,
    int currentBytes,
  ) async {
    if (currentBytes <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前暂无需要清理的缓存')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: Text(
          '确定要清空 ${formatBytes(currentBytes)} 的媒体缓存吗？\n'
          '清理后缩略图和图片将在浏览时按需重新加载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final clearedBytes = await ref.read(cacheSizeProvider.notifier).clear();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已成功释放 ${formatBytes(clearedBytes)} 缓存空间')),
      );
    }
  }
}

