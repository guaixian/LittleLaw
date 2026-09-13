import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 文件落盘加密:收到的图片/视频/语音/文件以密文形式存放在收件目录,
/// 防止文件被直接拷走(共享目录、网盘同步、备份泄露等场景)。
///
/// 格式 LLF1: "LLF1"(4B) | 1B 版本 | 12B 文件 nonce | 分块:
///   [4B 长度 LE | 密文 | 16B GCM tag],块大小 1 MiB,
///   每块 IV = nonce(8B) || 块序号(4B LE)。
///
/// 主密钥:`<dataDir>/vault.key`,32 字节随机,首用生成。
/// 注意:这是"文件级加密",主密钥与密文同目录存放,防的是文件本体外流,
/// 全盘保护仍应依赖 BitLocker/FileVault 等系统级加密(README 有说明)。
class FileVault {
  FileVault._(this._key, this.cacheDir);

  static const _magic = [0x4C, 0x4C, 0x46, 0x31]; // "LLF1"
  static const _version = 1;
  static const chunkSize = 1024 * 1024; // 1 MiB
  static const _tagLen = 16;
  static const encExt = '.llenc';

  final SecretKey _key;
  final Directory cacheDir;
  final AesGcm _cipher = AesGcm.with256bits();
  final _rand = Random.secure();

  /// 打开(或初始化)数据目录的保险库。
  static Future<FileVault> open(String dataDir) async {
    final dir = Directory('$dataDir/vault-cache');
    final keyFile = File('$dataDir/vault.key');
    Uint8List key;
    if (await keyFile.exists()) {
      key = await keyFile.readAsBytes();
      if (key.length != 32) {
        throw StateError('vault.key corrupted');
      }
    } else {
      key = Uint8List.fromList(
          List<int>.generate(32, (_) => Random.secure().nextInt(256)));
      await keyFile.writeAsBytes(key, flush: true);
    }
    dir.createSync(recursive: true);
    return FileVault._(SecretKey(key), dir);
  }

  /// 明文路径 → 加密文件路径(默认同目录加 .llenc 后缀)。
  /// 完成后删除明文临时文件(除非 [keepPlain])。
  Future<String> encryptFile(String plainPath,
      {String? outPath, bool keepPlain = false}) async {
    final src = File(plainPath);
    final dst = File(outPath ?? '$plainPath$encExt');
    await dst.parent.create(recursive: true);
    final nonce =
        Uint8List.fromList(List<int>.generate(12, (_) => _rand.nextInt(256)));
    final sink = dst.openWrite();
    final header = BytesBuilder();
    header.add(_magic);
    header.addByte(_version);
    header.add(nonce);
    sink.add(header.toBytes());

    final input = src.openRead();
    var index = 0;
    await for (final chunkIn in input) {
      final box = await _cipher.encrypt(
        chunkIn,
        secretKey: _key,
        nonce: _chunkIv(nonce, index),
      );
      final lenBytes = ByteData(4)..setUint32(0, box.cipherText.length, Endian.little);
      sink.add(lenBytes.buffer.asUint8List());
      sink.add(box.cipherText);
      sink.add(box.mac.bytes);
      index++;
    }
    await sink.flush();
    await sink.close();
    if (!keepPlain) {
      await src.delete();
    }
    return dst.path;
  }

  /// 解密到指定路径。
  Future<void> decryptFile(String encPath, String outPath) async {
    final src = File(encPath);
    final raf = await src.open();
    try {
      final header = await raf.read(4);
      for (var i = 0; i < 4; i++) {
        if (header[i] != _magic[i]) {
          throw StateError('not a vault file');
        }
      }
      final ver = await raf.read(1);
      if (ver[0] != _version) throw StateError('unsupported vault version');
      final nonce = await raf.read(12);
      final sink = File(outPath).openWrite();
      var index = 0;
      while (true) {
        final lenBytes = await raf.read(4);
        if (lenBytes.isEmpty) break;
        if (lenBytes.length < 4) throw StateError('truncated vault file');
        final len =
            ByteData.sublistView(lenBytes).getUint32(0, Endian.little);
        if (len > chunkSize) throw StateError('chunk too large (corrupt?)');
        final cipher = await raf.read(len);
        final tag = await raf.read(_tagLen);
        if (cipher.length < len || tag.length < _tagLen) {
          throw StateError('truncated vault file');
        }
        try {
          final plain = await _cipher.decrypt(
            SecretBox(cipher, nonce: _chunkIv(nonce, index), mac: Mac(tag)),
            secretKey: _key,
          );
          sink.add(plain);
        } on SecretBoxAuthenticationError {
          throw StateError('vault integrity check failed');
        }
        index++;
      }
      await sink.flush();
      await sink.close();
    } finally {
      await raf.close();
    }
  }

  /// 解密到缓存(同名复用,打开/查看用)。返回明文临时路径。
  Future<String> decryptToCache(String encPath, String cacheKey) async {
    final safe = cacheKey.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final out = File('${cacheDir.path}/$safe');
    if (await out.exists()) return out.path;
    await decryptFile(encPath, out.path);
    return out.path;
  }

  /// 清理解密缓存(退出时调用)。
  Future<void> clearCache() async {
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      cacheDir.createSync(recursive: true);
    }
  }

  List<int> _chunkIv(Uint8List nonce, int index) {
    final iv = Uint8List(12);
    iv.setRange(0, 8, nonce.sublist(0, 8));
    final b = ByteData(4)..setUint32(0, index, Endian.little);
    iv.setRange(8, 12, b.buffer.asUint8List());
    return iv;
  }
}
