import 'dart:convert';
import 'dart:io';

import 'package:lzma/lzma.dart';

import 'base45.dart';

/// OOB(带外)引导包:通过二维码 / NFC / 复制粘贴等带外通道交换,
/// 用于远程配对与 WebRTC 信令。物理/人工通道天然抗中间人,
/// 包内证书指纹成为之后所有连接的信任锚。
///
/// 编码格式:
///   LLB3 = base45(lzma(JSON))  —— 当前默认,LZMA 高压缩 + QR 字母数字
///          模式(97% 编码效率),同等内容二维码面积最小;
///   LLB2 = base64url(gzip(JSON)) —— 兼容解码;
///   LLB1 = base64url(JSON)      —— 兼容解码。
class OobBlob {
  OobBlob({
    required this.type,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.fingerprint,
    required this.token,
    this.deviceModel = '',
    this.certDer = const [],
    this.sdp,
    this.candidates = const [],
    this.rendezvousUrl,
    this.addresses = const [],
    int? createdAtMs,
  }) : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  static const typeOffer = 'offer';
  static const typeAnswer = 'answer';
  static const currentVersion = 1;

  final String type;

  // ---- 设备身份 ----
  final String deviceId;
  final String deviceName;
  final String platform;
  final String fingerprint; // 自签证书 SHA-256,hex
  final String deviceModel; // 机型

  /// 证书 DER(base64 传输)。配对后令牌轮换(ECDH 派生)的公钥来源;
  /// 旧版本引导包可能为空(轮换退化为令牌原文派生)。
  final List<int> certDer;

  /// 共享会话令牌(hex)。offer 方生成,answer 方必须原样回显(证明往返)。
  final String token;

  // ---- WebRTC 信令(可选;近场扫码直连局域网时为空) ----
  final String? sdp;
  final List<String> candidates;

  /// 邀请方使用的中转服务器地址(有值表示:应答可经该服务器信令推回,
  /// 受邀方无需手动回传)。受邀方未配置服务器时可临时连接此地址回传。
  final String? rendezvousUrl;

  /// 局域网地址候选(host:port)。近场扫码场景下可跳过 WebRTC 直连 gRPC。
  final List<String> addresses;

  final int createdAtMs;

  bool get isOffer => type == typeOffer;
  bool get isAnswer => type == typeAnswer;
  bool get hasRtc => sdp != null && sdp!.isNotEmpty;

  // ------------------------------------------------------------ 编解码

  /// 编码为可粘贴/可上二维码的字符串:gzip 压缩后 base64url。
  /// 候选以紧凑数组 [candidate, mid, index] 存储,进一步压缩体积。
  String encode() {
    final compactCandidates = candidates.map((c) {
      try {
        final map = jsonDecode(c) as Map<String, dynamic>;
        return [map['candidate'] ?? '', map['sdpMid'] ?? '', map['sdpMLineIndex'] ?? 0];
      } catch (_) {
        return [c, '', 0];
      }
    }).toList();
    final json = jsonEncode({
      'v': currentVersion,
      'type': type,
      'device': {
        'id': deviceId,
        'name': deviceName,
        'platform': platform,
        'fpr': fingerprint,
        'model': deviceModel,
        if (certDer.isNotEmpty) 'crt': base64Url.encode(certDer),
      },
      'token': token,
      if (sdp != null) 'rtc': {'sdp': sdp, 'candidates': compactCandidates},
      if (rendezvousUrl != null && rendezvousUrl!.isNotEmpty)
        'rvu': rendezvousUrl,
      if (addresses.isNotEmpty) 'addr': addresses,
      'ts': createdAtMs,
    });
    return 'LLB3.${Base45.encode(lzma.encode(utf8.encode(json)))}';
  }

  /// 解码并校验(兼容 LLB3 / LLB2 / LLB1)。格式非法抛 [FormatException]。
  ///
  /// 注意:base45 字母表含空格,只剥离换行类空白,绝不能 trim()
  /// (否则结尾为空格的合法载荷会被截断)。
  static OobBlob decode(String encoded) {
    final text = encoded.replaceAll(RegExp(r'[\r\n\t]'), '');
    if (text.length > 256 * 1024) {
      // 引导包是二维码/粘贴内容,合理上限远小于此;超限直接拒绝,
      // 缓解解压炸弹(LLB3 无解压上限原语,先挡住异常输入)。
      throw const FormatException('引导包超长');
    }
    List<int> jsonBytes;
    if (text.startsWith('LLB3.')) {
      try {
        jsonBytes = lzma.decode(Base45.decode(text.substring(5)));
      } catch (e) {
        throw FormatException('blob decode failed: $e');
      }
    } else if (text.startsWith('LLB2.')) {
      try {
        var b64 = text.substring(5);
        // 容忍缺 '=' 填充(base64url 粘贴场景常见)。
        while (b64.length % 4 != 0) {
          b64 += '=';
        }
        jsonBytes = gzip.decode(base64Url.decode(b64));
      } catch (_) {
        throw const FormatException('引导包内容损坏(gzip 解压失败)');
      }
    } else if (text.startsWith('LLB1.')) {
      try {
        var b64 = text.substring(5);
        while (b64.length % 4 != 0) {
          b64 += '=';
        }
        jsonBytes = base64Url.decode(b64);
      } catch (_) {
        throw const FormatException('引导包内容损坏');
      }
    } else {
      throw const FormatException('不是 LittleLaw 引导包(缺少 LLB 前缀)');
    }
    if (jsonBytes.length > 1024 * 1024) {
      throw const FormatException('引导包解压后超长(疑似解压炸弹)');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('引导包内容损坏');
    }
    if (json['v'] != currentVersion) {
      throw FormatException('引导包版本不兼容: ${json['v']}');
    }
    if (json['device'] is! Map) {
      throw const FormatException('缺少设备信息');
    }
    final device = json['device'] as Map<String, dynamic>;
    final type = json['type'];
    if (type is! String || (type != typeOffer && type != typeAnswer)) {
      throw FormatException('未知类型: $type');
    }
    // 时间戳双向窗口:过老 = 过期重放;明显未来 = 时钟回拨伪造。
    final ts = json['ts'];
    if (ts is! int || ts <= 0) {
      throw const FormatException('缺少时间戳');
    }
    final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
    if (ageMs < -Duration.minutesPerDay * 60 * 1000) {
      throw const FormatException('引导包时间戳异常(未来时间)');
    }
    final rtc = json['rtc'];
    final rtcMap = rtc is Map<String, dynamic> ? rtc : null;
    final addr = json['addr'];
    final tokenStr = json['token'];
    final fpr = device['fpr'];
    if (fpr is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fpr)) {
      throw const FormatException('证书指纹缺失或格式非法');
    }
    if (tokenStr is! String || tokenStr.isEmpty) {
      throw const FormatException('缺少会话令牌');
    }
    final crt = device['crt'];
    List<int> certDer = const [];
    if (crt is String && crt.isNotEmpty) {
      try {
        certDer = base64Url.decode(crt);
      } catch (_) {
        throw const FormatException('证书字段损坏');
      }
    }
    final sdpObj = rtcMap?['sdp'];
    final rvuObj = json['rvu'];
    return OobBlob(
      type: type,
      deviceId: device['id'] is String ? device['id'] as String : '',
      deviceName:
          device['name'] is String ? device['name'] as String : '未知设备',
      platform:
          device['platform'] is String ? device['platform'] as String : 'unknown',
      fingerprint: fpr,
      deviceModel: device['model'] is String ? device['model'] as String : '',
      certDer: certDer,
      token: tokenStr,
      sdp: sdpObj is String ? sdpObj : null,
      candidates: _decodeCandidates(rtcMap?['candidates']),
      rendezvousUrl: rvuObj is String ? rvuObj : null,
      addresses: addr is List ? addr.cast<String>() : const [],
      createdAtMs: ts,
    );
  }

  /// 候选解码:兼容紧凑数组格式 [c, mid, idx] 与旧 JSON 对象字符串,
  /// 统一输出 JSON 对象字符串供上层使用。
  static List<String> _decodeCandidates(Object? raw) {
    if (raw is! List) return const [];
    return raw.map((e) {
      if (e is String) return e; // 旧格式:已是 JSON 字符串
      if (e is List) {
        return jsonEncode({
          'candidate': e.isNotEmpty ? e[0] : '',
          'sdpMid': e.length > 1 ? e[1] : '',
          'sdpMLineIndex': e.length > 2 ? e[2] : 0,
        });
      }
      return '';
    }).where((s) => s.isNotEmpty).toList();
  }

  /// 引导包年龄(防止过期包重放)。
  Duration get age =>
      Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - createdAtMs);
}
