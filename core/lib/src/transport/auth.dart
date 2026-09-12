import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:grpc/grpc.dart';

import '../store/store.dart';

/// 应用层鉴权:共享会话令牌(配对时经 PIN 验证的通道协商)。
///
/// 传输层已有 TLS + 服务端证书指纹 pinning,令牌用于服务端反向确认
/// 调用方身份(grpc-dart 客户端无法出示客户端证书,故用令牌替代 mTLS)。
class Auth {
  static const metaDeviceId = 'll-device-id';
  static const metaToken = 'll-token';

  /// 生成 32 字节随机令牌,hex 编码。
  static String newToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return sha256.convert(bytes).toString();
  }

  /// 构造调用方元数据。
  static Map<String, String> metadata(String deviceId, String token) =>
      {metaDeviceId: deviceId, metaToken: token};

  /// 服务端校验:令牌必须属于某个已配对设备,且 device_id 与令牌匹配。
  /// 失败抛 unauthenticated。成功返回对应 Peer。
  static Peer verify(ServiceCall call, Store store) {
    final meta = call.clientMetadata ?? {};
    final deviceId = meta[metaDeviceId];
    final token = meta[metaToken];
    if (deviceId == null || token == null) {
      throw GrpcError.unauthenticated('missing auth metadata');
    }
    final peer = store.getPeer(deviceId);
    if (peer == null || peer.token != token) {
      throw GrpcError.unauthenticated('invalid token');
    }
    return peer;
  }

  /// 常量时间比较(令牌比对,防时序侧信道)。
  static bool constantTimeEquals(String a, String b) {
    final ba = utf8.encode(a);
    final bb = utf8.encode(b);
    if (ba.length != bb.length) return false;
    var diff = 0;
    for (var i = 0; i < ba.length; i++) {
      diff |= ba[i] ^ bb[i];
    }
    return diff == 0;
  }
}
