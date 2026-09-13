import 'dart:convert';

/// 局域网 OOB 载荷(二维码 / NFC NDEF 文本):读取方拿到地址与一次性
/// tap 令牌后,直连对方 gRPC 并调 PairWithTap 完成免 PIN 配对。
class LanOobPayload {
  LanOobPayload({
    required this.tapToken,
    required this.addresses,
    required this.deviceId,
    required this.deviceName,
    required this.fingerprint,
    int? createdAtMs,
  }) : createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  static const currentVersion = 1;

  final String tapToken;
  final List<String> addresses; // host:port 候选
  final String deviceId;
  final String deviceName;
  final String fingerprint;
  final int createdAtMs;

  String encode() {
    return 'LLT1.${base64UrlEncode(utf8.encode(jsonEncode({
          'v': currentVersion,
          'tap': tapToken,
          'addr': addresses,
          'id': deviceId,
          'name': deviceName,
          'fpr': fingerprint,
          'ts': createdAtMs,
        })))}';
  }

  static LanOobPayload decode(String encoded) {
    // base45 载荷可能含空格,只剥换行类空白。
    final text = encoded.replaceAll(RegExp(r'[\r\n\t]'), '');
    if (!text.startsWith('LLT1.')) {
      throw const FormatException('不是 LittleLaw 局域网载荷(缺少 LLT1 前缀)');
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(base64Url.decode(text.substring(5))))
          as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('载荷内容损坏');
    }
    if (json['v'] != currentVersion) {
      throw FormatException('载荷版本不兼容: ${json['v']}');
    }
    final tap = json['tap'] as String?;
    final addrs = (json['addr'] as List?)?.cast<String>();
    if (tap == null || tap.isEmpty || addrs == null || addrs.isEmpty) {
      throw const FormatException('载荷缺少令牌或地址');
    }
    return LanOobPayload(
      tapToken: tap,
      addresses: addrs,
      deviceId: json['id'] as String? ?? '',
      deviceName: json['name'] as String? ?? '未知设备',
      fingerprint: json['fpr'] as String? ?? '',
      createdAtMs: json['ts'] as int? ?? 0,
    );
  }
}
