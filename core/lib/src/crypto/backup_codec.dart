import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 备份文件加密封装(口令派生密钥)。
///
/// 格式 v2(当前写入): "LLBK"(4B) + version(2, 1B) + kdf 轮数(4B LE)
///   + salt(16B) + nonce(12B) + ciphertext||tag。
/// 密钥: PBKDF2-HMAC-SHA256(passphrase, salt, 轮数取自头部) → AES-256-GCM。
/// KDF 参数入头:将来调参不会让旧备份全部损坏报"口令错误"。
///
/// 格式 v1(兼容读取): "LLBK" + 1 + salt + nonce + ct||tag,固定 150k 轮。
/// 口令错误/文件损坏时解密抛 [StateError]。
class BackupCodec {
  static const version = 2;
  static const legacyVersion = 1;

  /// 当前写入用的 PBKDF2 轮数(OWASP 2023 对 SHA-256 的建议下限)。
  static const kdfIterations = 600000;
  static const legacyKdfIterations = 150000;

  static const _magic = [0x4C, 0x4C, 0x42, 0x4B]; // "LLBK"

  static final _rand = Random.secure();

  static Future<Uint8List> encrypt(
      List<int> plaintext, String passphrase) async {
    final salt = Uint8List.fromList(
        List<int>.generate(16, (_) => _rand.nextInt(256)));
    final nonce = Uint8List.fromList(
        List<int>.generate(12, (_) => _rand.nextInt(256)));
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: kdfIterations,
      bits: 256,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    final box = await AesGcm.with256bits()
        .encrypt(plaintext, secretKey: key, nonce: nonce);
    final out = BytesBuilder();
    out.add(_magic);
    out.addByte(version);
    final iterBytes = ByteData(4)..setUint32(0, kdfIterations, Endian.little);
    out.add(iterBytes.buffer.asUint8List());
    out.add(salt);
    out.add(nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  static Future<Uint8List> decrypt(
      List<int> packed, String passphrase) async {
    if (packed.length < 4 + 1 + 16 + 12 + 16) {
      throw StateError('不是有效的 LittleLaw 备份文件');
    }
    for (var i = 0; i < 4; i++) {
      if (packed[i] != _magic[i]) {
        throw StateError('不是有效的 LittleLaw 备份文件');
      }
    }
    final ver = packed[4];
    int iterations;
    int saltAt;
    if (ver == version) {
      if (packed.length < 4 + 1 + 4 + 16 + 12 + 16) {
        throw StateError('备份文件头不完整');
      }
      iterations = packed[5] |
          (packed[6] << 8) |
          (packed[7] << 16) |
          (packed[8] << 24);
      if (iterations < 100000 || iterations > 10000000) {
        throw StateError('备份文件 KDF 参数异常');
      }
      saltAt = 9;
    } else if (ver == legacyVersion) {
      iterations = legacyKdfIterations;
      saltAt = 5;
    } else {
      throw StateError('不支持的备份版本 $ver');
    }
    final salt = packed.sublist(saltAt, saltAt + 16);
    final nonce = packed.sublist(saltAt + 16, saltAt + 16 + 12);
    final ctStart = saltAt + 16 + 12;
    final cipherText = packed.sublist(ctStart, packed.length - 16);
    final tag = packed.sublist(packed.length - 16);
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final key = await kdf.deriveKeyFromPassword(
      password: passphrase,
      nonce: salt,
    );
    try {
      final plain = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(tag)),
        secretKey: key,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw StateError('口令错误或备份文件已损坏');
    }
  }
}
