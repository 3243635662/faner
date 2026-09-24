import 'dart:async';
import 'dart:io';

import 'package:nsd/nsd.dart' as nsd;

import '../../core/constants.dart';
import '../models/device_info.dart';

/// mDNS 服务发现封装（广播自己 + 扫描邻居）。
class DiscoveryService {
  nsd.Registration? _registration;
  nsd.Discovery? _discovery;
  StreamController<List<DeviceInfo>>? _controller;
  final Set<String> _myIps = <String>{};

  bool get isRegistered => _registration != null;

  /// 注册本机服务（Server 启动成功后调用）。
  Future<void> register({
    required String deviceName,
    required int port,
  }) async {
    await unregister();
    final service = nsd.Service(
      name: deviceName,
      type: AppConstants.serviceType,
      port: port,
    );
    _registration = await nsd.register(service);
  }

  /// 开始扫描，持续输出发现的设备列表（已过滤本机）。
  Stream<List<DeviceInfo>> discover() {
    _controller = StreamController<List<DeviceInfo>>();
    unawaited(refreshMyIps());
    nsd
        .startDiscovery(
          AppConstants.serviceType,
          ipLookupType: nsd.IpLookupType.v4,
        )
        .then((d) {
      _discovery = d;
      d.addServiceListener((_, _) => _emit());
      _emit();
    }).catchError((Object e) {
      if (!_controller!.isClosed) {
        _controller!.addError(e);
      }
    });
    return _controller!.stream;
  }

  void _emit() {
    final c = _controller;
    final d = _discovery;
    if (c == null || c.isClosed || d == null) return;
    final devices = <DeviceInfo>[];
    for (final s in d.services) {
      final ip = _resolveIp(s);
      if (ip == null) continue;
      if (_myIps.contains(ip)) continue; // 过滤本机自己
      devices.add(DeviceInfo(
        deviceName: s.name ?? '未知设备',
        ip: ip,
        port: s.port ?? AppConstants.basePort,
      ));
    }
    c.add(devices);
  }

  static String? _resolveIp(nsd.Service s) {
    final addrs = s.addresses;
    if (addrs != null) {
      for (final a in addrs) {
        if (a.type == InternetAddressType.IPv4) return a.address;
      }
    }
    final host = s.host;
    if (host != null && _looksLikeIp(host)) return host;
    return null;
  }

  static bool _looksLikeIp(String s) {
    final parts = s.split('.');
    return parts.length == 4 && parts.every((p) => int.tryParse(p) != null);
  }

  /// 获取本机当前所有活跃 IPv4 地址
  static Future<Set<String>> getLocalIpv4Addresses() async {
    final ips = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (final itf in interfaces) {
        for (final a in itf.addresses) {
          ips.add(a.address);
        }
      }
    } catch (_) {
      // 忽略
    }
    return ips;
  }

  Future<void> refreshMyIps() async {
    final ips = await getLocalIpv4Addresses();
    _myIps
      ..clear()
      ..addAll(ips);
  }

  void stopDiscovery() {
    final d = _discovery;
    if (d != null) {
      nsd.stopDiscovery(d).ignore();
      _discovery = null;
    }
    final c = _controller;
    if (c != null) {
      c.close().ignore();
      _controller = null;
    }
  }

  Future<void> unregister() async {
    final r = _registration;
    if (r != null) {
      _registration = null;
      try {
        await nsd.unregister(r);
      } catch (_) {
        // 忽略反注册失败
      }
    }
  }
}
