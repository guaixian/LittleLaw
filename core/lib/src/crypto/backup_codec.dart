import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 备份文件加密封装(口令派生密钥)。
///
/// 格式: "LLBK"(4B) + version(1B) + salt(16B) + nonce(12B) + ciphertext||tag。
/// 密钥: PBKDF2-HMAC-SHA256(passphrase, salt, 150k 轮) → AES-256-GCM。
/// 口令错误/文件损坏时解密抛 [StateError]。
class BackupCodec {
  static const version = 1;
  static const _kdfIterations = 150000;

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
      iterations: _kdfIterations,
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
    if (packed[4] != version) {
      throw StateError('不支持的备份版本 ${packed[4]}');
    }
    final salt = packed.sublist(5, 5 + 16);
    final nonce = packed.sublist(21, 21 + 12);
    final cipherText = packed.sublist(33, packed.length - 16);
    final tag = packed.sublist(packed.length - 16);
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _kdfIterations,
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
