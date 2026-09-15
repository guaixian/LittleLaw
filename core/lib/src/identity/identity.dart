import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

/// 设备身份:首次启动生成,终身不变。
///
/// 组成:
///  - deviceId: UUID v4
///  - deviceName: 用户可见名称(可改)
///  - EC P-256 密钥对 + 自签 X.509 证书(TLS 传输凭证)
///  - 证书指纹 = SHA-256(cert DER) hex,配对与连接时的信任锚
class Identity {
  Identity._({
    required this.deviceId,
    required this.deviceName,
    required this.deviceModel,
    required this.certPem,
    required this.keyPem,
    required this.fingerprint,
  });

  final String deviceId;
  String deviceName;

  /// 机型(如 "Xiaomi 13" / "iPhone 17 Pro Max" / "Windows 10 Pro"),
  /// 由应用层采集传入,纯引擎环境下回退为主机名。
  String deviceModel;
  final String certPem;
  final String keyPem;

  /// 证书 DER 的 SHA-256,hex 小写。全网唯一信任锚。
  final String fingerprint;

  static const _certFile = 'identity.crt';
  static const _keyFile = 'identity.key';
  static const _metaFile = 'identity.json';

  /// 证书有效期(天)。自签证书,过期不影响指纹校验(按指纹 pinning)。
  /// 注意:X.509 UTCTime 两位年份上限 2049,超出会回绕成非法有效期,
  /// 故取 20 年。
  static const certDays = 7300;

  /// 加载已有身份,不存在则生成。
  ///
  /// [deviceName] 用户自定义名;缺省按 "平台-型号" 生成。
  /// [deviceModel] 应用层采集的机型;缺省回退主机名。老身份文件缺字段时
  /// 自动补写(型号为空则后续启动再补)。
  static Future<Identity> loadOrCreate(String dataDir,
      {String? deviceName, String? deviceModel}) async {
    final dir = Directory(dataDir);
    await dir.create(recursive: true);

    final certFile = File('${dir.path}/$_certFile');
    final keyFile = File('${dir.path}/$_keyFile');
    final metaFile = File('${dir.path}/$_metaFile');

    if (await certFile.exists() &&
        await keyFile.exists() &&
        await metaFile.exists()) {
      final meta =
          jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
      final certPem = await certFile.readAsString();
      final keyPem = await keyFile.readAsString();
      var model = (meta['deviceModel'] as String?) ?? '';
      // 老身份补机型:应用层传入了就更新并落盘。
      if (model.isEmpty && deviceModel != null && deviceModel.isNotEmpty) {
        model = deviceModel;
        await metaFile.writeAsString(jsonEncode({
          'deviceId': meta['deviceId'] as String,
          'deviceName': meta['deviceName'] as String,
          'deviceModel': model,
        }));
      }
      return Identity._(
        deviceId: meta['deviceId'] as String,
        deviceName: meta['deviceName'] as String,
        deviceModel: model,
        certPem: certPem,
        keyPem: keyPem,
        fingerprint: fingerprintOfCertPem(certPem),
      );
    }

    final id = const Uuid().v4();
    final model = (deviceModel == null || deviceModel.isEmpty)
        ? _fallbackModel()
        : deviceModel;
    final name = (deviceName == null || deviceName.isEmpty)
        ? _defaultName(model)
        : deviceName;
    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;

    final csr = X509Utils.generateEccCsrPem(
      {'CN': id, 'O': 'LittleLaw', 'OU': 'LittleLaw Device'},
      priv,
      pub,
    );
    final certPem = X509Utils.generateSelfSignedCertificate(
      priv,
      csr,
      certDays,
      sans: ['littlelaw.local'],
      // 不传 keyUsage:basic_utils 的 KeyUsage 扩展 BIT STRING 编码有 bug,
      // 会被 BoringSSL 严格拒绝。缺省 keyUsage = 不限制用途,满足 TLS。
      extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH, ExtendedKeyUsage.CLIENT_AUTH],
      serialNumber: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    final keyPem = CryptoUtils.encodeEcPrivateKeyToPem(priv);

    await certFile.writeAsString(certPem);
    await keyFile.writeAsString(keyPem);
    await metaFile.writeAsString(jsonEncode(
        {'deviceId': id, 'deviceName': name, 'deviceModel': model}));

    return Identity._(
      deviceId: id,
      deviceName: name,
      deviceModel: model,
      certPem: certPem,
      keyPem: keyPem,
      fingerprint: fingerprintOfCertPem(certPem),
    );
  }

  /// 持久化改名(只覆盖名称,型号不变)。
  Future<void> rename(String dataDir, String newName) async {
    deviceName = newName;
    await File('$dataDir/$_metaFile').writeAsString(jsonEncode({
      'deviceId': deviceId,
      'deviceName': newName,
      'deviceModel': deviceModel,
    }));
  }

  /// 从 PEM 计算指纹:剥头尾 → base64 解码 DER → SHA-256 → hex。
  static String fingerprintOfCertPem(String pem) {
    final der = derOfCertPem(pem);
    return sha256.convert(der).toString();
  }

  static List<int> derOfCertPem(String pem) {
    final body = pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s+'), '');
    return base64Decode(body);
  }

  // ------------------------------------------------------------ 签名/验签

  /// 用身份私钥对消息做 ECDSA-P256(SHA-256) 签名,返回 r||s 各 32 字节。
  /// 用于发现层宣告报文签名(防伪造/防重放)。
  Uint8List signMessage(List<int> message) {
    final priv = CryptoUtils.ecPrivateKeyFromPem(keyPem);
    // pointycastle 无默认随机源,必须显式注入。
    final rng = math.Random.secure();
    final seed =
        Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(
          true, ParametersWithRandom(PrivateKeyParameter<ECPrivateKey>(priv),
              FortunaRandom()..seed(KeyParameter(seed))));
    final sig = signer.generateSignature(Uint8List.fromList(message))
        as ECSignature;
    final out = Uint8List(64);
    out.setRange(0, 32, _fixed32(sig.r));
    out.setRange(32, 64, _fixed32(sig.s));
    return out;
  }

  static Uint8List _fixed32(BigInt v) {
    var hex = v.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final raw = Uint8List.fromList(
        List<int>.generate(hex.length ~/ 2,
            (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16)));
    final out = Uint8List(32);
    out.setRange(32 - raw.length, 32, raw);
    return out;
  }

  /// 用证书公钥验证 ECDSA 签名(r||s 64B)。
  static bool verifyWithCertDer(
      List<int> certDer, List<int> message, List<int> sig64) {
    if (sig64.length != 64 || certDer.isEmpty) return false;
    try {
      final b64 = base64Encode(certDer);
      final pem = '-----BEGIN CERTIFICATE-----\n$b64\n'
          '-----END CERTIFICATE-----\n';
      final parsed = X509Utils.x509CertificateFromPem(pem);
      // subjectPublicKeyInfo.bytes 是 SPKI 的 hex 字符串(basic_utils 的
      // 内部约定),转回 DER 再取公钥。
      final spkiHex = parsed.tbsCertificate?.subjectPublicKeyInfo.bytes;
      if (spkiHex == null || spkiHex.isEmpty) return false;
      final spki = Uint8List.fromList([
        for (var i = 0; i + 1 < spkiHex.length; i += 2)
          int.parse(spkiHex.substring(i, i + 2), radix: 16)
      ]);
      final pub = CryptoUtils.ecPublicKeyFromDerBytes(spki);
      final r = _bigFromBytes(sig64.sublist(0, 32));
      final s = _bigFromBytes(sig64.sublist(32));
      final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
        ..init(false, PublicKeyParameter<ECPublicKey>(pub));
      return signer.verifySignature(
          Uint8List.fromList(message), ECSignature(r, s));
    } catch (_) {
      return false;
    }
  }

  static BigInt _bigFromBytes(List<int> bytes) {
    var v = BigInt.zero;
    for (final b in bytes) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  /// 短认证串(SAS):双方各自对两个指纹排序后哈希取 6 位数字。
  /// 不经网络传输,肉眼核对即绑定双方真实证书,主动中间人必现形。
  static String computeSasPin(String fingerprintA, String fingerprintB) {
    final parts = [fingerprintA, fingerprintB]..sort();
    final digest = sha256
        .convert(utf8.encode('littlelaw-sas-v1:${parts[0]}:${parts[1]}'))
        .bytes;
    final n = ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) &
        0x7fffffff;
    return (n % 1000000).toString().padLeft(6, '0');
  }

  /// 引擎层机型回退(无应用层采集时):主机名。
  static String _fallbackModel() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'Unknown';
    }
  }

  /// 缺省设备名:平台-型号。
  static String _defaultName(String model) {
    final platform = platformName();
    final label = switch (platform) {
      'android' => '安卓',
      'ios' => '苹果',
      'windows' => 'Windows',
      'macos' => 'macOS',
      'linux' => 'Linux',
      _ => 'LittleLaw',
    };
    return '$label-$model';
  }

  static String platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
