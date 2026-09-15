import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// 文件落盘加密:收到的图片/视频/语音/文件以密文形式存放在收件目录,
/// 防止文件被直接拷走(共享目录、网盘同步、备份泄露等场景)。
///
/// 格式 LLF1: "LLF1"(4B) | 1B 版本 | 12B 文件 nonce | 分块:
///   [4B 长度 LE | 密文 | 16B GCM tag],块大小 1 MiB,
///   每块 IV = nonce 前 8B || 块序号(4B LE)。
///
/// 格式 LLF2(当前写入格式,读取兼容 v1):
///   "LLF2"(4B) | 1B 版本 | 12B nonce | 8B 明文总长(LE) | 分块同 v1,
///   每块 IV = nonce 与块序号 inc32 组合(12B 全量参与);
///   首块 AAD = 全部头部字节 → 头部字段被认证,尾部截断可检测;
///   加密侧显式按 1 MiB 定长切块(不再跟随流缓冲边界)。
///
/// 主密钥:`<dataDir>/vault.key`,32 字节随机,首用生成。
/// 注意:这是"文件级加密",主密钥与密文同目录存放,防的是文件本体外流,
/// 全盘保护仍应依赖 BitLocker/FileVault 等系统级加密(README 有说明)。
class FileVault {
  FileVault._(this._key, this.cacheDir);

  static const _magic = [0x4C, 0x4C, 0x46]; // "LLF"
  static const _version1 = 1;
  static const _version2 = 2;
  static const chunkSize = 1024 * 1024; // 1 MiB
  static const _tagLen = 16;
  static const encExt = '.llenc';

  final SecretKey _key;
  final Directory cacheDir;
  final AesGcm _cipher = AesGcm.with256bits();
  final _rand = Random.secure();

  /// 打开(或初始化)数据目录的保险库。
  /// 启动即清理解密缓存:上次崩溃/强杀留下的明文残留全部清除
  /// (旧版只在退出钩子清,断电时最多半 GB 明文永久留在磁盘上)。
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
    final vault = FileVault._(SecretKey(key), dir);
    vault.clearCache().catchError((_) {});
    return vault;
  }

  /// 明文路径 → 加密文件路径(默认同目录加 .llenc 后缀)。
  /// 完成后删除明文临时文件(除非 [keepPlain])。
  /// 原子写:先写随机临时文件再改名,崩溃只留 .tmp,不会把半包密文
  /// 留在最终路径被误当完整文件复用。
  Future<String> encryptFile(String plainPath,
      {String? outPath, bool keepPlain = false}) async {
    final src = File(plainPath);
    final dst = File(outPath ?? '$plainPath$encExt');
    await dst.parent.create(recursive: true);
    final nonce =
        Uint8List.fromList(List<int>.generate(12, (_) => _rand.nextInt(256)));
    final tmp = File('${dst.path}.tmp${_rand.nextInt(1 << 30)}');
    IOSink? sink;
    try {
      final total = await src.length();
      final header = BytesBuilder();
      header.add(_magic);
      header.addByte(_version2);
      header.add(nonce);
      final len8 = ByteData(8)..setUint64(0, total, Endian.little);
      header.add(len8.buffer.asUint8List());
      final headerBytes = header.toBytes();
      sink = tmp.openWrite();
      sink.add(headerBytes);

      // 显式定长切块:openRead() 的 chunk 边界跟随平台流缓冲,
      // 未来任何平台单次产出 >1MiB 时,自己加密的文件会被自己
      // 的解密侧判死(len > chunkSize),而明文已删无法恢复。
      final input = src.openRead();
      final buf = BytesBuilder(copy: true);
      var index = 0;
      await for (final chunkIn in input) {
        buf.add(chunkIn);
        while (buf.length >= chunkSize) {
          final block = buf.takeBytes();
          final piece = block.sublist(0, chunkSize);
          buf.add(block.sublist(chunkSize));
          await _writeChunk(sink, piece, nonce, index,
              headerBytes: index == 0 ? headerBytes : const []);
          index++;
        }
      }
      final rest = buf.takeBytes();
      if (rest.isNotEmpty) {
        await _writeChunk(sink, rest, nonce, index,
            headerBytes: index == 0 ? headerBytes : const []);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      await tmp.rename(dst.path);
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        await tmp.delete();
      } catch (_) {}
      rethrow;
    }
    if (!keepPlain) {
      await src.delete();
    }
    return dst.path;
  }

  Future<void> _writeChunk(IOSink sink, List<int> plain, Uint8List nonce,
      int index, {List<int> headerBytes = const []}) async {
    final box = await _cipher.encrypt(
      plain,
      secretKey: _key,
      nonce: _chunkIv(nonce, index),
      aad: headerBytes,
    );
    final lenBytes = ByteData(4)..setUint32(0, box.cipherText.length, Endian.little);
    sink.add(lenBytes.buffer.asUint8List());
    sink.add(box.cipherText);
    sink.add(box.mac.bytes);
  }

  /// 解密到指定路径。
  Future<void> decryptFile(String encPath, String outPath) async {
    final src = File(encPath);
    final raf = await src.open();
    IOSink? sink;
    try {
      final magic = await raf.read(3);
      if (magic.length < 3 ||
          magic[0] != _magic[0] ||
          magic[1] != _magic[1] ||
          magic[2] != _magic[2]) {
        throw StateError('not a vault file');
      }
      final verByte = await raf.read(1);
      if (verByte.isEmpty) throw StateError('truncated vault file');
      final ver = verByte[0];
      Uint8List nonce;
      int expectedTotal = -1;
      List<int>? headerForAad;
      if (ver == _version2) {
        final headerRest = await raf.read(12 + 8);
        if (headerRest.length < 20) throw StateError('truncated vault file');
        nonce = Uint8List.fromList(headerRest.sublist(0, 12));
        expectedTotal =
            ByteData.sublistView(headerRest, 12, 20).getUint64(0, Endian.little);
        // AAD = 完整头(magic+ver+nonce+total):头部被认证,尾部截断
        // 可通过总长核对检测(v1 唯独尾部截断畅通)。
        headerForAad = [
          ..._magic.sublist(0, 3),
          ver,
          ...headerRest.sublist(0, 20),
        ];
      } else if (ver == _version1) {
        final n = await raf.read(12);
        if (n.length < 12) throw StateError('truncated vault file');
        nonce = Uint8List.fromList(n);
      } else {
        throw StateError('unsupported vault version');
      }
      sink = File(outPath).openWrite();
      var index = 0;
      var produced = 0;
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
            SecretBox(cipher,
                nonce: _chunkIv(nonce, index, v1: ver == _version1), mac: Mac(tag)),
            secretKey: _key,
            aad: index == 0 && headerForAad != null ? headerForAad : const [],
          );
          sink.add(plain);
          produced += plain.length;
        } on SecretBoxAuthenticationError {
          throw StateError('vault integrity check failed');
        }
        index++;
      }
      if (expectedTotal >= 0 && produced != expectedTotal) {
        throw StateError('vault file truncated (length mismatch)');
      }
      await sink.flush();
      await sink.close();
      sink = null;
    } finally {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      await raf.close();
    }
  }

  /// 解密到缓存(同名复用,打开/查看用)。返回明文临时路径。
  /// 原子写:先写随机 .tmp 再改名,中断不会留下半包缓存毒化后续复用;
  /// 同 key 并发调用共享同一次解密,避免竞态交错写坏缓存。
  ///
  /// 缓存键:调用方给的语义键(含用户可控文件名)只做 sha256 摘要,
  /// 并混入密文文件的 size+mtime——旧版把非法字符折叠成 `_` 再拿
  /// String.hashCode(32bit 可碰撞)当标识,碰撞时会把 A 会话的文件
  /// 明文当 B 会话的发出去;密文变化(重收)后旧缓存自动失效。
  Future<String> decryptToCache(String encPath, String cacheKey) async {
    final f = File(encPath);
    String stat;
    try {
      final st = f.statSync();
      stat = '${st.size}:${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      stat = '0:0';
    }
    final digest = sha256
        .convert(utf8.encode('$cacheKey|$stat|${f.path.length}'))
        .toString();
    final out = File('${cacheDir.path}/$digest');
    final pending = _cacheInflight[digest];
    if (pending != null) return pending;
    final task = _decryptToCacheInner(encPath, out);
    _cacheInflight[digest] = task;
    try {
      final r = await task;
      _sweepCacheMaybe();
      return r;
    } finally {
      _cacheInflight.remove(digest);
    }
  }

  Future<String> _decryptToCacheInner(String encPath, File out) async {
    if (await out.exists()) {
      // 命中刷新访问时间(TTL 清扫依据)。
      try {
        await out.setLastModified(DateTime.now());
      } catch (_) {}
      return out.path;
    }
    final tmp = File(
        '${cacheDir.path}/tmp${_rand.nextInt(1 << 30)}-${out.uri.pathSegments.last}');
    try {
      await decryptFile(encPath, tmp.path);
      await tmp.rename(out.path);
    } catch (e) {
      // 失败清理,下次重试;同时清掉可能损坏的旧缓存。
      try {
        await tmp.delete();
      } catch (_) {}
      try {
        if (await out.exists()) await out.delete();
      } catch (_) {}
      rethrow;
    }
    return out.path;
  }

  /// 同 key 在途解密任务(并发去重)。
  final _cacheInflight = <String, Future<String>>{};

  /// 缓存总量上限,超过即后台清空。
  static const _cacheCapBytes = 512 * 1024 * 1024;

  /// 单条缓存 TTL:查看后超过此时长未再访问即清除——明文只在
  /// 合理的查看窗口内存在,而不是一直留到退出/超额。
  static const _cacheTtl = Duration(minutes: 30);

  bool _cacheSweeping = false;
  Timer? _cacheTtlTimer;

  void _sweepCacheMaybe() {
    _cacheTtlTimer ??= Timer.periodic(
        const Duration(minutes: 5), (_) => _sweepExpiredCache());
    if (_cacheSweeping) return;
    _cacheSweeping = true;
    Future<void>(() async {
      try {
        var total = 0;
        await for (final f in cacheDir.list()) {
          if (f is File) total += await f.length();
        }
        if (total > _cacheCapBytes) await clearCache();
      } catch (_) {}
      _cacheSweeping = false;
    });
  }

  Future<void> _sweepExpiredCache() async {
    try {
      final cutoff = DateTime.now().subtract(_cacheTtl);
      await for (final f in cacheDir.list()) {
        if (f is File && f.statSync().modified.isBefore(cutoff)) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  /// 清理解密缓存(退出时调用)。
  Future<void> clearCache() async {
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      cacheDir.createSync(recursive: true);
    }
  }

  /// v2:nonce 12B 全量参与,块序号按 inc32 与 nonce 末 4 字节异或。
  /// v1:nonce 前 8B || 块序号(4B LE)——兼容旧密文读取。
  List<int> _chunkIv(Uint8List nonce, int index, {bool v1 = false}) {
    if (v1) {
      final iv = Uint8List(12);
      iv.setRange(0, 8, nonce.sublist(0, 8));
      final b = ByteData(4)..setUint32(0, index, Endian.little);
      iv.setRange(8, 12, b.buffer.asUint8List());
      return iv;
    }
    final iv = Uint8List.fromList(nonce);
    final b = ByteData(4)..setUint32(0, index, Endian.little);
    final counter = b.buffer.asUint8List();
    for (var i = 0; i < 4; i++) {
      iv[8 + i] ^= counter[i];
    }
    return iv;
  }
}
