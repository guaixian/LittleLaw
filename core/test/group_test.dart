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

Future<void> pair(LittleLawEngine a, LittleLawEngine b,
    {required String nameA, required String nameB}) async {
  final token = a.beginRemoteOffer();
  final offer = OobBlob(
      type: OobBlob.typeOffer,
      deviceId: a.identity.deviceId,
      deviceName: nameA,
      platform: 'windows',
      fingerprint: a.identity.fingerprint,
      token: token);
  b.acceptRemoteOffer(OobBlob.decode(offer.encode()));
  a.acceptRemoteAnswer(OobBlob.decode(OobBlob(
          type: OobBlob.typeAnswer,
          deviceId: b.identity.deviceId,
          deviceName: nameB,
          platform: 'windows',
          fingerprint: b.identity.fingerprint,
          token: token)
      .encode()));
}

Future<void> connectAll(List<LittleLawEngine> engines) async {
  for (final a in engines) {
    for (final b in engines) {
      if (identical(a, b)) continue;
      if (a.peerById(b.identity.deviceId) == null) continue;
      a.sync.ensureSession(a.peerById(b.identity.deviceId)!,
          host: '127.0.0.1', port: b.grpcPort);
    }
  }
  await waitFor(
      () => engines.every((a) => engines.every((b) =>
          identical(a, b) ||
          a.peerById(b.identity.deviceId) == null ||
          a.isOnline(b.identity.deviceId))),
      description: '全员互联在线');
}

void main() {
  test('群聊:A 建群发消息,B/C 收到且重复到达去重;群删除三端一致', () async {
    final dirs = List.generate(
        3, (_) => Directory.systemTemp.createTempSync('ll_gr_'));
    final a = await LittleLawEngine.start(
        dataDir: dirs[0].path,
        grpcPort: 0,
        discoveryPort: 48991,
        deviceName: '群主A');
    final b = await LittleLawEngine.start(
        dataDir: dirs[1].path,
        grpcPort: 0,
        discoveryPort: 48993,
        deviceName: '成员B');
    final c = await LittleLawEngine.start(
        dataDir: dirs[2].path,
        grpcPort: 0,
        discoveryPort: 48995,
        deviceName: '成员C');

    try {
      // 两两配对 + 全互联。
      await pair(a, b, nameA: '群主A', nameB: '成员B');
      await pair(a, c, nameA: '群主A', nameB: '成员C');
      await pair(b, c, nameA: '成员B', nameB: '成员C');
      await connectAll([a, b, c]);

      // A 建群(A/B/C)。
      final group = a.createGroup('家人群',
          [b.identity.deviceId, c.identity.deviceId]);
      expect(group.memberIds.length, 3);
      // B/C 各自建同 ID 群(演示环境手动同步群定义;正式版走群管理信封)。
      b.store.insertGroup(Group(
          id: group.id,
          name: '家人群',
          createdAtMs: group.createdAtMs,
          memberIds: [a.identity.deviceId, b.identity.deviceId, c.identity.deviceId]));
      b.store.selfDeviceId = b.identity.deviceId;
      c.store.insertGroup(Group(
          id: group.id,
          name: '家人群',
          createdAtMs: group.createdAtMs,
          memberIds: [a.identity.deviceId, b.identity.deviceId, c.identity.deviceId]));
      c.store.selfDeviceId = c.identity.deviceId;

      // A 发群消息。
      final msg = await a.sendGroupText(group.id, '大家好,这是第一条群消息');
      await waitFor(
          () => b.loadGroupMessages(group.id).any((m) => m.msgId == msg.msgId),
          description: 'B 收到群消息');
      await waitFor(
          () => c.loadGroupMessages(group.id).any((m) => m.msgId == msg.msgId),
          description: 'C 收到群消息');
      final atB = b.loadGroupMessages(group.id)
          .firstWhere((m) => m.msgId == msg.msgId);
      expect(atB.text, '大家好,这是第一条群消息');
      expect(atB.senderId, a.identity.deviceId);
      expect(atB.convId, Group.convIdOf(group.id));

      // B 回复,C 与 A 都收到。
      final reply = await b.sendGroupText(group.id, '收到!');
      await waitFor(
          () => a.loadGroupMessages(group.id).any((m) => m.msgId == reply.msgId) &&
              c.loadGroupMessages(group.id).any((m) => m.msgId == reply.msgId),
          description: 'A/C 收到 B 的群回复');
      expect(
          c.loadGroupMessages(group.id)
              .firstWhere((m) => m.msgId == reply.msgId).text,
          '收到!');

      // 重复到达去重:msg_id 主键,同一条从不同成员重复到达只落一条。
      expect(
          b.loadGroupMessages(group.id).where((m) => m.msgId == msg.msgId).length,
          1,
          reason: 'msg_id 幂等去重');

      // 群删除:B 删除自己的回复 → 三端全删。
      await b.deleteGroupMessages(group.id, [reply.msgId]);
      await waitFor(
          () => a.loadGroupMessages(group.id).every((m) => m.msgId != reply.msgId) &&
              c.loadGroupMessages(group.id).every((m) => m.msgId != reply.msgId),
          description: 'A/C 同步删除群消息');
      expect(
          b.loadGroupMessages(group.id).every((m) => m.msgId != reply.msgId),
          isTrue);
    } finally {
      await a.dispose();
      await b.dispose();
      await c.dispose();
      for (final d in dirs) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
