import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'server/foreground_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 前台服务与主 isolate 的通信端口
  FlutterForegroundTask.initCommunicationPort();
  // 提前创建通知渠道（首次开启共享前就绪）
  ForegroundService.init();
  runApp(const ProviderScope(child: FanerApp()));
}
