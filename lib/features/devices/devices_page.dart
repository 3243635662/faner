import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/prompts.dart';
import '../../core/tokens.dart';
import '../../data/models/device_info.dart';
import '../../providers/discovery_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/services_provider.dart';
import '../shared/empty_state.dart';

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(deviceListProvider);
    final server = ref.watch(serverControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('局域网')),
      body: Column(
        children: [
          _ServerStatusCard(server: server, ref: ref),
          Expanded(child: _buildBody(context, devices, ref)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddDevice(context, ref),
        icon: const Icon(LucideIcons.plus),
        label: const Text('手动连接'),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<DeviceInfo> devices, WidgetRef ref) {
    if (devices.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.tablet,
        title: '未发现局域网设备',
        subtitle: '确保两台设备在同一 Wi-Fi 下，\n或使用「手动连接」输入 IP 地址。',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final d = devices[index];
        return _DeviceCard(
          device: d,
          onTap: () => context.push('/remote', extra: d),
          onLongPress: d.isManual
              ? () => _confirmRemove(context, ref, d)
              : null,
        );
      },
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, DeviceInfo device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除设备'),
        content: Text('从最近连接中移除「${device.deviceName}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      ref.read(manualDevicesProvider.notifier).remove(device);
    }
  }

  Future<void> _showAddDevice(BuildContext context, WidgetRef ref) async {
    final result = await showFieldsPrompt(
      context,
      title: '手动连接设备',
      confirmLabel: '连接',
      fields: [
        PromptField(
          label: 'IP 地址',
          keyboardType: TextInputType.number,
          validator: (v) => v.isEmpty ? '请输入 IP 地址' : null,
        ),
        PromptField(
          label: '端口',
          initial: '${AppConstants.basePort}',
          keyboardType: TextInputType.number,
          validator: (v) =>
              int.tryParse(v) == null ? '端口号无效' : null,
        ),
      ],
    );
    if (result == null || !context.mounted) return;

    final (ip, port) = (result[0], int.parse(result[1]));
    if (!_isValidIp(ip)) {
      _showSnack(context, 'IP 地址格式不正确');
      return;
    }
    final device = DeviceInfo(deviceName: ip, ip: ip, port: port, isManual: true);

    // 先校验连通性（GET /api/info）
    _showSnack(context, '正在连接…');
    final client = ref.read(remoteFileClientProvider);
    final info = await client.fetchInfo(device);
    if (!context.mounted) return;
    info.fold(
      (remoteInfo) {
        final finalDevice = DeviceInfo(
          deviceName: remoteInfo.deviceName,
          ip: ip,
          port: port,
          isManual: true,
        );
        ref.read(manualDevicesProvider.notifier).add(finalDevice);
        _showSnack(context, '已连接 ${finalDevice.deviceName}');
      },
      (err) => _showSnack(context, '连接失败：$err'),
    );
  }

  static bool _isValidIp(String s) {
    final parts = s.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.onTap,
    this.onLongPress,
  });

  final DeviceInfo device;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.panel,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: palette.brand.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(LucideIcons.smartphone, color: palette.brand),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.deviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.subtitle.copyWith(
                            color: palette.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: device.isManual
                                    ? palette.muted
                                    : palette.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              device.isManual ? '手动 · 可能离线' : '在线',
                              style: AppTypography.caption
                                  .copyWith(color: palette.muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${device.ip}:${device.port}',
                style: AppTypography.caption.copyWith(color: palette.muted),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '浏览文件',
                    style: AppTypography.body.copyWith(
                      color: palette.brand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(LucideIcons.chevron_right, color: palette.brand, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: AppMotion.mid);
  }
}

class _ServerStatusCard extends StatelessWidget {
  const _ServerStatusCard({required this.server, required this.ref});

  final ServerState server;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (icon, text, color) = switch (server.status) {
      ServerStatus.running => (
          LucideIcons.circle_check,
          '本机共享运行中 · 端口 ${server.port}',
          palette.green
        ),
      ServerStatus.starting => (LucideIcons.hourglass, '正在启动…', palette.amber),
      ServerStatus.error => (LucideIcons.circle_alert, '共享启动失败', palette.red),
      ServerStatus.stopped => (LucideIcons.circle_pause, '本机共享已关闭', palette.muted),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: palette.text, fontWeight: FontWeight.w500),
              ),
            ),
            IconButton(
              icon: Icon(
                server.status == ServerStatus.running ? LucideIcons.square : LucideIcons.play,
                color: palette.brand,
              ),
              onPressed: () {
                if (server.status == ServerStatus.running) {
                  ref.read(serverControllerProvider.notifier).stop();
                } else {
                  ref.read(serverControllerProvider.notifier).start();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
