import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'toast.dart';

/// 应用内自动更新:检查 GitHub Releases 最新版本,下载并安装。
/// - Windows:下载 littlelaw-windows-x64-setup.exe 并启动安装程序;
/// - Android:下载 app-arm64-v8a-release.apk 并拉起系统安装器;
/// - 其他平台:仅提示有新版本。
class AppUpdate {
  AppUpdate({
    required this.version,
    required this.assetName,
    required this.url,
    required this.sizeBytes,
    required this.notes,
  });

  final String version; // 2.5.0(无 v 前缀)
  final String assetName;
  final String url; // 直链(browser_download_url)
  final int sizeBytes;
  final String notes;
}

class Updater {
  static const repo = 'guaixian/LittleLaw';
  static const _api = 'https://api.github.com/repos/$repo/releases/latest';

  static const _channel = MethodChannel('dev.littlelaw/share');

  /// 当前应用版本(与 pubspec 同步维护;发布时一起改)。
  static const currentVersion = '2.5.0';

  static int _ver(String v) {
    final parts = v
        .split(RegExp(r'[.+-]'))
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts[0] * 1000000 + parts[1] * 1000 + parts[2];
  }

  /// 查询最新版本;无更新/网络失败返回 null。
  static Future<AppUpdate?> checkLatest() async {
    try {
      final json = await _getJson(_api);
      final tag = (json['tag_name'] ?? '') as String;
      if (!tag.startsWith('v')) return null;
      final latest = tag.substring(1);
      if (_ver(latest) <= _ver(currentVersion)) return null;

      // 按平台挑产物。
      String want;
      if (Platform.isWindows) {
        want = 'littlelaw-windows-x64-setup.exe';
      } else if (Platform.isAndroid) {
        want = 'app-arm64-v8a-release.apk';
      } else if (Platform.isMacOS) {
        want = 'littlelaw-macos.dmg';
      } else {
        want = 'littlelaw-linux-amd64.deb';
      }
      final assets = (json['assets'] ?? []) as List;
      Map? hit;
      for (final a in assets) {
        if ((a['name'] ?? '') == want) {
          hit = a as Map;
          break;
        }
      }
      if (hit == null) return null;
      return AppUpdate(
        version: latest,
        assetName: want,
        url: hit['browser_download_url'] as String,
        sizeBytes: (hit['size'] as num?)?.toInt() ?? 0,
        notes: ((json['body'] ?? '') as String)
            .split('\n')
            .take(12)
            .join('\n'),
      );
    } catch (_) {
      return null;
    }
  }

  /// 下载到缓存目录,返回本地路径。[progress] 回调 (已下载, 总量)。
  static Future<String> download(
      AppUpdate u, void Function(int done, int total) progress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${u.assetName}');
    final sink = file.openWrite();
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(u.url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      var done = 0;
      final total = res.contentLength > 0 ? res.contentLength : u.sizeBytes;
      await for (final chunk in res) {
        sink.add(chunk);
        done += chunk.length;
        progress(done, total);
      }
      await sink.flush();
      await sink.close();
      client.close();
      return file.path;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        file.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  /// 安装/启动安装程序。
  static Future<void> install(String path) async {
    if (Platform.isWindows) {
      // Inno Setup 安装器接管(用户按提示完成覆盖安装)。
      await Process.start(path, const [], mode: ProcessStartMode.detached);
      return;
    }
    if (Platform.isAndroid) {
      await _channel.invokeMethod('installApk', {'path': path});
      return;
    }
    showToast('该平台请手动下载更新包', type: ToastType.info);
  }

  static Future<Map<String, dynamic>> _getJson(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'littlelaw-updater');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final body = await res.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
