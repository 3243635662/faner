import 'dart:io';

import '../../core/constants.dart';
import '../server_context.dart';

/// GET /api/info
Future<void> handleInfo(HttpRequest request, ServerContext ctx) async {
  writeJson(request, {
    'deviceName': ctx.deviceName,
    'appVersion': AppConstants.appVersion,
    'sharedRootLabel': AppConstants.sharedRootLabel,
  });
}
