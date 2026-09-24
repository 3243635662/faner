import 'package:flutter/material.dart';
// 后台保活前台服务（让 Server 在锁屏后仍运行）；
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
// 状态管理（全局 Provider 容器根）；
import 'package:flutter_riverpod/flutter_riverpod.dart';
// 视频播放内核 libmpv
import 'package:media_kit/media_kit.dart';

import 'app/app.dart';
import 'server/foreground_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 视频播放内核（libmpv）必须在创建 Player 之前初始化
  MediaKit.ensureInitialized();
  // 前台服务与主 isolate 的通信端口
  FlutterForegroundTask.initCommunicationPort();
  // 提前创建通知渠道（首次开启共享前就绪）
  ForegroundService.init();
  runApp(const ProviderScope(child: FanerApp()));
}
