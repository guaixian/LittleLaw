import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// 采集本机机型(显示用),规则:
///  - Android: "Xiaomi 13"(品牌+型号去重)
///  - iOS:     "iPhone 17 Pro Max"(机器码映射市场名,未知回退机器码)
///  - Windows: "Windows 10 Pro"
///  - macOS:   "MacBook Pro" / "Mac mini"
///  - Linux:   发行版名
Future<String> gatherDeviceModel() async {
  final info = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final a = await info.androidInfo;
      final brand = a.brand.trim();
      final model = a.model.trim();
      if (model.isEmpty) return brand.isEmpty ? 'Android 设备' : brand;
      // 型号已含品牌则直接用型号。
      if (brand.isEmpty || model.toLowerCase().startsWith(brand.toLowerCase())) {
        return model;
      }
      return '$brand $model';
    }
    if (Platform.isIOS) {
      final i = await info.iosInfo;
      final machine = i.utsname.machine;
      return iphoneMarketingName(machine);
    }
    if (Platform.isWindows) {
      final w = await info.windowsInfo;
      if (w.productName.isNotEmpty) return w.productName;
      return 'Windows ${w.majorVersion}';
    }
    if (Platform.isMacOS) {
      final m = await info.macOsInfo;
      return m.model.isNotEmpty ? m.model : 'Mac';
    }
    if (Platform.isLinux) {
      final l = await info.linuxInfo;
      return l.prettyName.isNotEmpty ? l.prettyName : 'Linux';
    }
  } catch (_) {}
  return 'Unknown';
}

/// 桌面端缺省设备名:系统版本-计算机名(计算机名即用户自定义)。
/// 移动端由核心引擎按 "平台-型号" 生成。
Future<String?> gatherDesktopDefaultName() async {
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isWindows) {
      final w = await info.windowsInfo;
      final model =
          w.productName.isNotEmpty ? w.productName : 'Windows ${w.majorVersion}';
      return '$model-${w.computerName}';
    }
    if (Platform.isMacOS) {
      final m = await info.macOsInfo;
      final model = m.model.isNotEmpty ? m.model : 'Mac';
      return '$model-${m.computerName}';
    }
    if (Platform.isLinux) {
      final l = await info.linuxInfo;
      return '${l.prettyName}-${l.machineId ?? "device"}';
    }
  } catch (_) {}
  return null; // 移动端走引擎默认
}

/// 平台标签(卡片显示用)。
String platformLabel(String platform) => switch (platform) {
      'android' => '安卓',
      'ios' => 'iOS',
      'windows' => 'Windows',
      'macos' => 'macOS',
      'linux' => 'Linux',
      _ => platform,
    };

/// iPhone 机器码 → 市场名(近年型号,尽力而为;未知回退原机器码)。
String iphoneMarketingName(String machine) {
  const map = {
    'iPhone13,1': 'iPhone 12 mini',
    'iPhone13,2': 'iPhone 12',
    'iPhone13,3': 'iPhone 12 Pro',
    'iPhone13,4': 'iPhone 12 Pro Max',
    'iPhone14,2': 'iPhone 13 Pro',
    'iPhone14,3': 'iPhone 13 Pro Max',
    'iPhone14,4': 'iPhone 13 mini',
    'iPhone14,5': 'iPhone 13',
    'iPhone14,6': 'iPhone SE (第3代)',
    'iPhone14,7': 'iPhone 14',
    'iPhone14,8': 'iPhone 14 Plus',
    'iPhone15,2': 'iPhone 14 Pro',
    'iPhone15,3': 'iPhone 14 Pro Max',
    'iPhone15,4': 'iPhone 15',
    'iPhone15,5': 'iPhone 15 Plus',
    'iPhone16,1': 'iPhone 15 Pro',
    'iPhone16,2': 'iPhone 15 Pro Max',
    'iPhone17,1': 'iPhone 16 Pro',
    'iPhone17,2': 'iPhone 16 Pro Max',
    'iPhone17,3': 'iPhone 16',
    'iPhone17,4': 'iPhone 16 Plus',
    'iPhone18,1': 'iPhone 17 Pro',
    'iPhone18,2': 'iPhone 17 Pro Max',
    'iPhone18,3': 'iPhone 17',
    'iPhone18,4': 'iPhone Air',
  };
  if (map.containsKey(machine)) return map[machine]!;
  // iPad 兜底:直接显示机器码。
  return machine.isNotEmpty ? machine : 'iPhone';
}
