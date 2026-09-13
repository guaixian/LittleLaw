import 'dart:io';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 25),
    String description = 'condition'}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('waitFor timeout: $description');
}

void main() {
  test('多设备镜像:我的手机发消息,我的电脑与好友两端全量同步', () async {
    final dirP = Directory.systemTemp.createTempSync('ll_mp_'); // 我的手机
    final dirC = Directory.systemTemp.createTempSync('ll_mc_'); // 我的电脑
    final dirF = Directory.systemTemp.createTempSync('ll_mf_'); // 好友设备
    final p = await LittleLawEngine.start(
        dataDir: dirP.path, grpcPort: 0, discoveryPort: 48981, deviceName: '我的手机');
    final c = await LittleLawEngine.start(
        dataDir: dirC.path, grpcPort: 0, discoveryPort: 48983, deviceName: '我的电脑');
    final f = await LittleLawEngine.start(
        dataDir: dirF.path, grpcPort: 0, discoveryPort: 48985, deviceName: '好友');

    try {
      // ---------- 配对三对:手机↔好友, 手机↔电脑, 电脑标记为"我的设备" ----------
      // 手机 ↔ 好友
      final token1 = p.beginRemoteOffer();
      final offer1 = OobBlob(
          type: OobBlob.typeOffer,
          deviceId: p.identity.deviceId,
          deviceName: '我的手机',
          platform: 'windows',
          fingerprint: p.identity.fingerprint,
          token: token1);
      f.acceptRemoteOffer(OobBlob.decode(offer1.encode()));
      p.acceptRemoteAnswer(OobBlob.decode(OobBlob(
              type: OobBlob.typeAnswer,
              deviceId: f.identity.deviceId,
              deviceName: '好友',
              platform: 'windows',
              fingerprint: f.identity.fingerprint,
              token: token1)
          .encode()));
      // 手机 ↔ 电脑
      final token2 = p.beginRemoteOffer();
      final offer2 = OobBlob(
          type: OobBlob.typeOffer,
          deviceId: p.identity.deviceId,
          deviceName: '我的手机',
          platform: 'windows',
          fingerprint: p.identity.fingerprint,
          token: token2);
      c.acceptRemoteOffer(OobBlob.decode(offer2.encode()));
      p.acceptRemoteAnswer(OobBlob.decode(OobBlob(
              type: OobBlob.typeAnswer,
              deviceId: c.identity.deviceId,
              deviceName: '我的电脑',
              platform: 'windows',
              fingerprint: c.identity.fingerprint,
              token: token2)
          .encode()));
      // 手机上把电脑标记为"我的设备",电脑上也把手机标记(双向,便于气泡归属识别)。
      p.setSelfDevice(c.identity.deviceId, true);
      c.setSelfDevice(p.identity.deviceId, true);
      expect(p.isSelfDevice(c.identity.deviceId), isTrue);

      // ---------- 建链(手机↔好友, 手机↔电脑,模拟全在线) ----------
      p.sync.ensureSession(p.peerById(f.identity.deviceId)!,
          host: '127.0.0.1', port: f.grpcPort);
      p.sync.ensureSession(p.peerById(c.identity.deviceId)!,
          host: '127.0.0.1', port: c.grpcPort);
      f.sync.ensureSession(f.peerById(p.identity.deviceId)!,
          host: '127.0.0.1', port: p.grpcPort);
      c.sync.ensureSession(c.peerById(p.identity.deviceId)!,
          host: '127.0.0.1', port: p.grpcPort);
      await waitFor(
          () => p.isOnline(f.identity.deviceId) &&
              p.isOnline(c.identity.deviceId) &&
              f.isOnline(p.identity.deviceId) &&
              c.isOnline(p.identity.deviceId),
          description: '三设备互联在线');

      // ---------- 手机发给好友:好友收到,电脑镜像也收到 ----------
      final msg =
          await p.sendText(f.identity.deviceId, '多设备镜像消息');
      await waitFor(
          () => f.loadMessages(p.identity.deviceId)
              .any((m) => m.msgId == msg.msgId),
          description: '好友收到消息');
      await waitFor(
          () => c.loadMessages(f.identity.deviceId)
              .any((m) => m.msgId == msg.msgId),
          description: '我的电脑镜像收到,且落在与好友的会话中');

      // 电脑侧:消息应在 conv(电脑,好友) 里,且 isFromMe 为真(我的手机发的)。
      final mirrored = c.loadMessages(f.identity.deviceId)
          .firstWhere((m) => m.msgId == msg.msgId);
      expect(mirrored.convId, Store.convIdFor(c.identity.deviceId, f.identity.deviceId));
      expect(c.isFromMe(mirrored.senderId), isTrue,
          reason: '我的手机发的镜像消息在电脑上应识别为"我"');
      // 好友侧:内容一致。
      final atFriend =
          f.loadMessages(p.identity.deviceId).firstWhere((m) => m.msgId == msg.msgId);
      expect(atFriend.text, '多设备镜像消息');

      // ---------- 手机删除:好友删除,电脑镜像同步删除 ----------
      await p.deleteMessages(f.identity.deviceId, [msg.msgId]);
      await waitFor(
          () => f.loadMessages(p.identity.deviceId).isEmpty &&
              c.loadMessages(f.identity.deviceId).isEmpty,
          description: '双端+镜像全删除');

      // ---------- 好友发给手机:手机收到,电脑也镜像 ----------
      final reply = await f.sendText(p.identity.deviceId, '好友回复');
      await waitFor(
          () => c.loadMessages(f.identity.deviceId)
              .any((m) => m.msgId == reply.msgId),
          description: '好友消息也镜像到电脑',
          timeout: const Duration(seconds: 20));
      final mirroredReply = c.loadMessages(f.identity.deviceId)
          .firstWhere((m) => m.msgId == reply.msgId);
      expect(mirroredReply.text, '好友回复');
      expect(c.isFromMe(mirroredReply.senderId), isFalse,
          reason: '好友的消息镜像到电脑仍应识别为对方');
    } finally {
      await p.dispose();
      await c.dispose();
      await f.dispose();
      try {
        dirP.deleteSync(recursive: true);
        dirC.deleteSync(recursive: true);
        dirF.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
