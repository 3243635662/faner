import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/prompts.dart';
import '../../core/result.dart';
import '../../data/models/device_info.dart';
import '../../providers/credentials_provider.dart';
import '../../providers/services_provider.dart';

/// 确保与 [device] 的会话已通过口令校验。
///
/// 返回 true 表示可以继续访问；false 表示用户取消或口令错误（已提示）。
/// 已保存过正确口令时会静默通过，不会每次都弹窗。
Future<bool> ensureAuthorized(
  BuildContext context,
  WidgetRef ref,
  DeviceInfo device,
) async {
  final probe = await ref.read(remoteFileClientProvider).list(device, '');
  if (probe.isOk) return true;
  if (!needsAuthorization(probe)) {
    if (!context.mounted) return false;
    _snack(context, errorMessageOf(probe) ?? '无法访问该设备');
    return false;
  }

  if (!context.mounted) return false;
  final input = await showTextPrompt(
    context,
    title: '输入「${device.deviceName}」的共享口令',
    hint: '在对方设备「设置 → 网络与共享 → 共享密码」中查看',
    confirmLabel: '连接',
    validator: (v) => v.trim().isEmpty ? '口令不能为空' : null,
  );
  if (input == null) return false;

  await ref
      .read(deviceCredentialsProvider.notifier)
      .save(device.deviceName, input);

  // 重新 read 以拿到注入了新口令的客户端实例。
  final retry = await ref.read(remoteFileClientProvider).list(device, '');
  if (retry.isOk) return true;

  await ref.read(deviceCredentialsProvider.notifier).remove(device.deviceName);
  if (!context.mounted) return false;
  _snack(
    context,
    needsAuthorization(retry)
        ? '口令不正确，请重试'
        : (errorMessageOf(retry) ?? '连接失败'),
  );
  return false;
}

/// 该失败是否属于「需要共享口令」。
bool needsAuthorization(Result<Object?> result) =>
    result is Err && result.code == ErrorCodes.unauthorized;

/// 取错误文案（成功时为 null）。
String? errorMessageOf(Result<Object?> result) =>
    result is Err ? result.message : null;

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
