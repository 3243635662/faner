import 'dart:io';

import '../../core/constants.dart';
import '../server_context.dart';

/// GET /api/info
///
/// 唯一**不需要口令**的接口：既用于连通性校验，也让连接方在输入口令前
/// 就知道对方是否开启了口令保护。
Future<void> handleInfo(HttpRequest request, ServerContext ctx) async {
  writeJson(request, {
    'deviceName': ctx.deviceName,
    'appVersion': AppConstants.appVersion,
    'sharedRootLabel': AppConstants.sharedRootLabel,
    'authRequired': ctx.authRequired,
  });
}
