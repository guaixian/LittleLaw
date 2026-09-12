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
    this.sdp,
    this.candidates = const [],
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

  /// 共享会话令牌(hex)。offer 方生成,answer 方必须原样回显(证明往返)。
  final String token;

  // ---- WebRTC 信令(可选;近场扫码直连局域网时为空) ----
  final String? sdp;
  final List<String> candidates;

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
      },
      'token': token,
      if (sdp != null) 'rtc': {'sdp': sdp, 'candidates': compactCandidates},
      if (addresses.isNotEmpty) 'addr': addresses,
      'ts': createdAtMs,
    });
    return 'LLB3.${Base45.encode(lzma.encode(utf8.encode(json)))}';
  }

  /// 解码并校验(兼容 LLB3 / LLB2 / LLB1)。格式非法抛 [FormatException]。
  static OobBlob decode(String encoded) {
    final text = encoded.trim();
    List<int> jsonBytes;
    if (text.startsWith('LLB3.')) {
      try {
        jsonBytes = lzma.decode(Base45.decode(text.substring(5)));
      } catch (_) {
        throw const FormatException('引导包内容损坏(lzma 解压失败)');
      }
    } else if (text.startsWith('LLB2.')) {
      try {
        jsonBytes = gzip.decode(base64Url.decode(text.substring(5)));
      } catch (_) {
        throw const FormatException('引导包内容损坏(gzip 解压失败)');
      }
    } else if (text.startsWith('LLB1.')) {
      try {
        jsonBytes = base64Url.decode(text.substring(5));
      } catch (_) {
        throw const FormatException('引导包内容损坏');
      }
    } else {
      throw const FormatException('不是 LittleLaw 引导包(缺少 LLB 前缀)');
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
    final device = json['device'] as Map<String, dynamic>? ??
        (throw const FormatException('缺少设备信息'));
    final type = json['type'] as String? ?? '';
    if (type != typeOffer && type != typeAnswer) {
      throw FormatException('未知类型: $type');
    }
    final rtc = json['rtc'] as Map<String, dynamic>?;
    return OobBlob(
      type: type,
      deviceId: device['id'] as String? ??
          (throw const FormatException('缺少 deviceId')),
      deviceName: device['name'] as String? ?? '未知设备',
      platform: device['platform'] as String? ?? 'unknown',
      fingerprint: device['fpr'] as String? ??
          (throw const FormatException('缺少证书指纹')),
      deviceModel: device['model'] as String? ?? '',
      token: json['token'] as String? ??
          (throw const FormatException('缺少会话令牌')),
      sdp: rtc?['sdp'] as String?,
      candidates: _decodeCandidates(rtc?['candidates']),
      addresses: (json['addr'] as List?)?.cast<String>() ?? const [],
      createdAtMs: json['ts'] as int? ?? 0,
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
