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

      // A 建群(A/B/C),群定义自动扇出。
      final group = a.createGroup('家人群',
          [b.identity.deviceId, c.identity.deviceId]);
      expect(group.memberIds.length, 3);
      await waitFor(() => b.groupById(group.id) != null,
          description: 'B 自动收到群定义');
      await waitFor(() => c.groupById(group.id) != null,
          description: 'C 自动收到群定义');

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

      // ---- 已读回执:C 打开会话标记已读 → A 的消息变已读。 ----
      c.markRead(group.id);
      await waitFor(
          () => a.loadGroupMessages(group.id)
              .firstWhere((m) => m.msgId == msg.msgId)
              .read,
          description: 'A 看到 C 的已读回执');
      // B 的消息(他人消息)不应被置已读。
      expect(
          a.loadGroupMessages(group.id)
              .where((m) => m.senderId == b.identity.deviceId)
              .every((m) => !m.read),
          isTrue);

      // ---- 表情回应:B 给 A 的消息点 👍,A/C 都看到。 ----
      b.setReaction(group.id, msg.msgId, '👍');
      await waitFor(
          () => a.loadGroupMessages(group.id)
                  .firstWhere((m) => m.msgId == msg.msgId)
                  .reactions[b.identity.deviceId] ==
              '👍',
          description: 'A 看到 B 的回应');
      await waitFor(
          () => c.loadGroupMessages(group.id)
                  .firstWhere((m) => m.msgId == msg.msgId)
                  .reactions[b.identity.deviceId] ==
              '👍',
          description: 'C 看到 B 的回应');
      // A 也点同一个:C 端聚合为两个回应者。
      a.setReaction(group.id, msg.msgId, '👍');
      await waitFor(
          () => c.loadGroupMessages(group.id)
                  .firstWhere((m) => m.msgId == msg.msgId)
                  .reactions
                  .length ==
              2,
          description: 'C 看到两个回应者');
      // B 取消回应。
      b.setReaction(group.id, msg.msgId, '');
      await waitFor(
          () => a.loadGroupMessages(group.id)
                  .firstWhere((m) => m.msgId == msg.msgId)
                  .reactions
                  .length ==
              1,
          description: 'B 取消回应后 A 只剩一个回应者');

      // ---- 群管理:改群名 → 全端同步。 ----
      a.renameGroup(group.id, '家人群2');
      await waitFor(() => c.groupById(group.id)?.name == '家人群2',
          description: 'C 收到新群名');

      // ---- 踢人:A 把 C 移出群 → C 本地群与消息被删。 ----
      a.removeGroupMembers(group.id, [c.identity.deviceId]);
      await waitFor(() => c.groupById(group.id) == null,
          description: 'C 本地群被删');
      await waitFor(() => c.loadGroupMessages(group.id).isEmpty,
          description: 'C 本地群消息被删');
      // A/B 仍在群内。
      expect(a.groupById(group.id)?.memberIds.length, 2);

      // ---- 拉人:A 重新拉 C 入群 → C 恢复群定义(历史消息已清,重新开始)。 ----
      a.addGroupMembers(group.id, [c.identity.deviceId]);
      await waitFor(() => c.groupById(group.id) != null,
          description: 'C 重新入群');
      expect(c.groupById(group.id)?.memberIds.length, 3);

      // ---- 解散:A 解散 → B/C 群与消息全删。 ----
      final keep = await a.sendGroupText(group.id, '解散前最后一条');
      await waitFor(
          () => b.loadGroupMessages(group.id).any((m) => m.msgId == keep.msgId),
          description: 'B 收到最后一条');
      a.dissolveGroup(group.id);
      await waitFor(
          () => a.groupById(group.id) == null &&
              b.groupById(group.id) == null &&
              c.groupById(group.id) == null,
          description: '三端群定义全删');
      await waitFor(
          () => b.loadGroupMessages(group.id).isEmpty &&
              c.loadGroupMessages(group.id).isEmpty,
          description: 'B/C 群消息全删');
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
