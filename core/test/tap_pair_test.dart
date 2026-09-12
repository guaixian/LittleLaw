import 'dart:io';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

void main() {
  test('一碰/一扫配对(免PIN):窗口内成功、令牌一次性、伪造拒绝', () async {
    final dirA = Directory.systemTemp.createTempSync('ll_ta_');
    final dirB = Directory.systemTemp.createTempSync('ll_tb_');
    final a = await LittleLawEngine.start(
        dataDir: dirA.path, grpcPort: 0, discoveryPort: 48931, deviceName: 'NFC-A');
    final b = await LittleLawEngine.start(
        dataDir: dirB.path, grpcPort: 0, discoveryPort: 48933, deviceName: 'NFC-B');

    try {
      // A 开启配对窗口,载荷经"物理通道"给 B(测试中直接传递字符串)。
      final payloadText = await a.enableTapPairing();
      final payload = LanOobPayload.decode(payloadText);
      expect(payload.deviceId, a.identity.deviceId);
      expect(payload.addresses, isNotEmpty);

      // B 扫码/触碰后配对。
      final result = await b.pairViaLanOob(payloadText);
      expect(result.accepted, isTrue, reason: result.message);

      // 双端入账,令牌一致。
      expect(a.peerById(b.identity.deviceId), isNotNull);
      expect(b.peerById(a.identity.deviceId), isNotNull);
      expect(a.peerById(b.identity.deviceId)!.token,
          b.peerById(a.identity.deviceId)!.token);

      // 令牌一次性:第二次使用同一载荷必须失败。
      final replay = await b.pairViaLanOob(payloadText);
      expect(replay.accepted, isFalse, reason: '一次性令牌不可重放');

      // 伪造令牌必须被拒。
      final forged = await a.enableTapPairing(); // 开新窗口
      final forgedPayload = LanOobPayload.decode(forged);
      final evil = LanOobPayload(
        tapToken: 'deadbeef' * 8,
        addresses: forgedPayload.addresses,
        deviceId: 'evil',
        deviceName: 'evil',
        fingerprint: 'ff' * 32,
      ).encode();
      final evilResult = await b.pairViaLanOob(evil);
      expect(evilResult.accepted, isFalse, reason: '伪造 tap 令牌必须拒绝');

      // 配对后能正常通讯。
      final pa = a.peerById(b.identity.deviceId)!;
      final pb2 = b.peerById(a.identity.deviceId)!;
      a.sync.ensureSession(pa, host: '127.0.0.1', port: b.grpcPort);
      b.sync.ensureSession(pb2, host: '127.0.0.1', port: a.grpcPort);
      final msg = await a.sendText(b.identity.deviceId, 'tap 配对后的消息');
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        if (b.loadMessages(a.identity.deviceId)
            .any((m) => m.msgId == msg.msgId)) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 100));
      }
      expect(
          b.loadMessages(a.identity.deviceId).any((m) => m.msgId == msg.msgId),
          isTrue);
    } finally {
      await a.dispose();
      await b.dispose();
      try {
        dirA.deleteSync(recursive: true);
        dirB.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
