import 'dart:convert';
import 'dart:io';

import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:lzma/lzma.dart';

Future<void> main() async {
  final dir = Directory.systemTemp.createTempSync('ll_dbg2_');
  final e = await LittleLawEngine.start(
      dataDir: dir.path, grpcPort: 0, discoveryPort: 48971, deviceName: '调试机');
  final token = e.beginRemoteOffer();
  final offer = OobBlob(
    type: OobBlob.typeOffer,
    deviceId: e.identity.deviceId,
    deviceName: '远程A',
    platform: 'windows',
    fingerprint: e.identity.fingerprint,
    token: token,
  );
  final encoded = offer.encode();
  print('encoded prefix: ${encoded.substring(0, 5)}');
  print('encoded[5..] 全部 base45 合法: ${Base45.isBase45Charset(encoded.substring(5))}');
  final b45 = encoded.substring(5);
  try {
    final packed = Base45.decode(b45);
    print('base45 decode ok: ${packed.length} bytes, 头8: ${packed.sublist(0, 8)}');
    try {
      final plain = lzma.decode(packed);
      print('lzma decode ok: ${plain.length} bytes');
      final blob = OobBlob.decode(encoded);
      print('blob ok: ${blob.deviceId}');
    } catch (e2) {
      print('lzma decode FAIL: $e2');
    }
  } catch (e1) {
    print('base45 decode FAIL: $e1');
  }
  await e.dispose();
  dir.deleteSync(recursive: true);
}
