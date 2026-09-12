import 'dart:io';

import 'package:flutter/services.dart';

/// 热点直传(无共同路由器场景):Android 程序化开/加热点;
/// iOS/桌面端由 UI 引导用户走系统设置(见 hotspot_page.dart)。
class HotspotInfo {
  HotspotInfo({required this.ssid, required this.password});
  final String ssid;
  final String password;

  /// 标准 WiFi 二维码内容(手机相机可直接扫)。
  String get wifiQr => 'WIFI:T:WPA;S:$ssid;P:$password;;';
}

class HotspotManager {
  static const _channel = MethodChannel('dev.littlelaw/hotspot');

  /// 程序化热点仅 Android 支持;iOS 只能手动开个人热点,桌面用系统功能。
  static bool get isProgrammaticSupported => Platform.isAndroid;

  /// 创建热点(仅 Android)。需已授予定位/附近设备权限。
  static Future<HotspotInfo> startHotspot() async {
    final res = await _channel.invokeMethod<Map>('startHotspot');
    final map = res?.cast<Object?, Object?>() ?? const {};
    final ssid = map['ssid'] as String?;
    final pass = map['password'] as String?;
    if (ssid == null || pass == null) {
      throw StateError('热点已开启但未取到 SSID/密码');
    }
    return HotspotInfo(ssid: ssid, password: pass);
  }

  static Future<void> stopHotspot() => _channel.invokeMethod('stopHotspot');

  /// 加入指定热点(仅 Android 10+)。成功后引擎流量自动走该网络。
  static Future<void> joinHotspot(String ssid, String password) =>
      _channel.invokeMethod('joinHotspot', {'ssid': ssid, 'password': password});

  /// 离开热点(恢复原网络)。
  static Future<void> leaveHotspot() => _channel.invokeMethod('leaveHotspot');
}
