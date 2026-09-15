import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'toast.dart';

/// 应用内自动更新:检查 GitHub Releases 最新版本,下载并安装。
/// - Windows:下载 littlelaw-windows-x64-setup.exe 并启动安装程序;
/// - Android:下载 app-arm64-v8a-release.apk 并拉起系统安装器;
/// - 其他平台:仅提示有新版本。
///
/// 安全约束:
///  - 下载 URL 必须是 https 且 host ∈ GitHub 官方域名白名单;
///  - 下载完成强制校验 GitHub API 提供的 sha256 digest,不匹配删除拒装;
///  - 产物落在本端数据目录 tmp 下,不进系统共享临时目录。
class AppUpdate {
  AppUpdate({
    required this.version,
    required this.assetName,
    required this.url,
    required this.sizeBytes,
    required this.notes,
    required this.sha256Hex,
  });

  final String version; // 2.5.0(无 v 前缀)
  final String assetName;
  final String url; // 直链(browser_download_url)
  final int sizeBytes;
  final String notes;
  final String sha256Hex; // 产物 sha256(十六进制),来自 GitHub API digest
}

/// 检查结果三态(检查失败 ≠ 已是最新)。
enum UpdateCheckStatus { available, upToDate, error }

class UpdateCheckResult {
  UpdateCheckResult(this.status, [this.update, this.errorText]);
  final UpdateCheckStatus status;
  final AppUpdate? update;
  final String? errorText;
}

class Updater {
  static const repo = 'guaixian/LittleLaw';
  static const _api = 'https://api.github.com/repos/$repo/releases/latest';

  static const _channel = MethodChannel('dev.littlelaw/share');

  /// 当前应用版本(与 pubspec 同步维护;发布时一起改)。
  static const currentVersion = '2.6.1';

  /// 下载源白名单:只允许 GitHub 官方域名,防 API/链路被劫持后跳到任意主机。
  static const _allowedHosts = {
    'github.com',
    'objects.githubusercontent.com',
    'release-assets.githubusercontent.com',
    'api.github.com',
  };

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

  /// 查询最新版本。检查失败时返回 error 态(区别于"已是最新")。
  static Future<UpdateCheckResult> checkLatest() async {
    try {
      final json = await _getJson(_api);
      final tag = (json['tag_name'] ?? '') as String;
      if (!tag.startsWith('v')) {
        return UpdateCheckResult(
            UpdateCheckStatus.error, null, 'Release 标签无效: "$tag"');
      }
      final latest = tag.substring(1);
      if (_ver(latest) <= _ver(currentVersion)) {
        return UpdateCheckResult(UpdateCheckStatus.upToDate);
      }

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
      if (hit == null) {
        return UpdateCheckResult(
            UpdateCheckStatus.error, null, 'Release 缺少产物 $want');
      }
      final url = (hit['browser_download_url'] ?? '') as String;
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.isScheme('https') ||
          !_allowedHosts.contains(uri.host)) {
        return UpdateCheckResult(
            UpdateCheckStatus.error, null, '下载地址不受信任: $url');
      }
      // digest 形如 "sha256:<hex>";缺失/格式不对即拒绝(fail-closed,无哈希不安装)。
      final digest = (hit['digest'] ?? '') as String;
      final sha256Hex = digest.startsWith('sha256:') ? digest.substring(7) : '';
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256Hex)) {
        return UpdateCheckResult(
            UpdateCheckStatus.error, null, 'Release 产物缺少有效的 sha256 摘要,拒绝安装');
      }
      return UpdateCheckResult(
        UpdateCheckStatus.available,
        AppUpdate(
          version: latest,
          assetName: want,
          url: url,
          sizeBytes: (hit['size'] as num?)?.toInt() ?? 0,
          notes: ((json['body'] ?? '') as String)
              .split('\n')
              .take(12)
              .join('\n'),
          sha256Hex: sha256Hex,
        ),
      );
    } catch (e) {
      return UpdateCheckResult(UpdateCheckStatus.error, null, '$e');
    }
  }

  /// 下载到数据目录下的 tmp(不进系统共享临时目录),校验 sha256 后返回本地路径。
  /// [progress] 回调 (已下载, 总量)。
  static Future<String> download(AppUpdate u, String dataDir,
      void Function(int done, int total) progress) async {
    final tmpDir = Directory('$dataDir/tmp');
    if (!tmpDir.existsSync()) tmpDir.createSync(recursive: true);
    final file = File('${tmpDir.path}/${u.assetName}');
    final sink = file.openWrite();
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await client.getUrl(Uri.parse(u.url));
      final res = await req.close().timeout(const Duration(minutes: 10));
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
      client = null;

      // 完整性校验:哈希不匹配即删除拒装(防 Release 被替换/下载链路劫持)。
      final actual = await _sha256OfFile(file);
      if (!_hexEqualsConstTime(actual, u.sha256Hex)) {
        try {
          file.deleteSync();
        } catch (_) {}
        throw '安装包校验失败(sha256 不匹配),已删除';
      }
      return file.path;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      client?.close(force: true);
      try {
        if (file.existsSync()) file.deleteSync();
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

  /// 安装包遗留清理(启动时/安装后调用;Windows 安装器运行中删除可能失败,容忍)。
  static void cleanupInstallers(String dataDir, {String? exceptPath}) {
    try {
      final tmpDir = Directory('$dataDir/tmp');
      if (!tmpDir.existsSync()) return;
      final keep = exceptPath == null
          ? null
          : File(exceptPath).absolute.path.toLowerCase();
      for (final f in tmpDir.listSync()) {
        final name = f.path.replaceAll('\\', '/').split('/').last;
        final isSetup =
            name.startsWith('littlelaw-') && name.endsWith('.exe');
        final isApk = name.startsWith('app-') && name.endsWith('.apk');
        if (!isSetup && !isApk) continue;
        if (keep != null &&
            f is File &&
            f.absolute.path.toLowerCase() == keep) {
          continue;
        }
        try {
          f.deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
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

  /// 流式 sha256(避免整包读入内存)。
  static Future<String> _sha256OfFile(File f) async {
    final out = _DigestCollector();
    final input = sha256.startChunkedConversion(out);
    await f.openRead().listen(input.add).asFuture<void>();
    input.close();
    return out.hash ?? '';
  }
}

class _DigestCollector implements Sink<Digest> {
  String? hash;

  @override
  void add(Digest data) => hash = data.toString();

  @override
  void close() {}
}

bool _hexEqualsConstTime(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
