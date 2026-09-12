import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// 应用层端到端加密(经过服务器/中转的载荷专用)。
///
/// 密钥派生:配对时经带外通道建立的 32B 共享令牌
/// → SHA-256("littlelaw-e2e-v1:" + token) → AES-256-GCM。
/// 输出格式:nonce(12B) || ciphertext || tag(16B)。
/// 服务器/中转只见密文,无法读取亦无法伪造(GCM 认证加密)。
class SecureCodec {
  SecureCodec(String token)
      : _key = SecretKey(
            sha256.convert(utf8.encode('littlelaw-e2e-v1:$token')).bytes);

  static const _nonceLen = 12;
  static const _tagLen = 16;

  final SecretKey _key;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<Uint8List> encrypt(List<int> plaintext) async {
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: _key,
      nonce: nonce,
    );
    final out = BytesBuilder();
    out.add(nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  /// 解密。密文损坏/被篡改抛 [StateError]。
  Future<Uint8List> decrypt(List<int> packed) async {
    if (packed.length < _nonceLen + _tagLen) {
      throw StateError('ciphertext too short');
    }
    final nonce = packed.sublist(0, _nonceLen);
    final cipherText = packed.sublist(_nonceLen, packed.length - _tagLen);
    final tag = packed.sublist(packed.length - _tagLen);
    try {
      final plain = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: _key,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw StateError('ciphertext authentication failed (tampered)');
    }
  }
}
