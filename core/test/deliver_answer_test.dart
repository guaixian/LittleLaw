import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

void main() {
  test('DeliverAnswer 自动回传:受邀方推回答,邀请方免粘贴入账', () async {
    final dirA = Directory.systemTemp.createTempSync('ll_da_');
    final dirB = Directory.systemTemp.createTempSync('ll_db_');
    final a = await LittleLawEngine.start(
        dataDir: dirA.path, grpcPort: 0, discoveryPort: 48951, deviceName: '邀请方A');
    final b = await LittleLawEngine.start(
        dataDir: dirB.path, grpcPort: 0, discoveryPort: 48953, deviceName: '受邀方B');

    try {
      // A 创建邀请(生成 pending offer token)。
      final token = a.beginRemoteOffer();
      final offer = OobBlob(
        type: OobBlob.typeOffer,
        deviceId: a.identity.deviceId,
        deviceName: '邀请方A',
        platform: 'windows',
        fingerprint: a.identity.fingerprint,
        token: token,
        deviceModel: 'test',
      );

      // B 应用 offer(入账 A)→ 生成 answer → 直接 RPC 回传给 A。
      b.acceptRemoteOffer(OobBlob.decode(offer.encode()));
      final answer = OobBlob(
        type: OobBlob.typeAnswer,
        deviceId: b.identity.deviceId,
        deviceName: '受邀方B',
        platform: 'windows',
        fingerprint: b.identity.fingerprint,
        token: token, // 回显
        deviceModel: 'test',
      ).encode();

      String? delivered;
      final sub = a.answerDeliveries.listen((s) => delivered = s);
      await b.deliverAnswerTo('127.0.0.1', a.grpcPort, answer);

      // A 应已入账 B,且收到回传事件。
      expect(a.peerById(b.identity.deviceId), isNotNull);
      await Future.delayed(const Duration(milliseconds: 300));
      expect(delivered, answer);
      expect(a.peerById(b.identity.deviceId)!.token, token);
      await sub.cancel();

      // 伪造 offer_token 的投递必须被拒且不入账。
      final evil = OobBlob(
        type: OobBlob.typeAnswer,
        deviceId: 'evil-device',
        deviceName: 'evil',
        platform: 'windows',
        fingerprint: 'ff' * 32,
        token: token,
      ).encode();
      // A 重新开一个邀请窗口。
      final token2 = a.beginRemoteOffer();
      expect(token2, isNot(token));
      // B 用过期的旧 token 投递 → 服务端接受(令牌匹配新窗口?不匹配)→ 抛错。
      var rejected = false;
      try {
        // 伪造场景:offer_token 不是当前 pending 的。
        await a.pairing.deliverAnswerTo('127.0.0.1', a.grpcPort, evil);
      } catch (_) {
        rejected = true;
      }
      expect(rejected, isTrue);
      expect(a.peerById('evil-device'), isNull);
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
