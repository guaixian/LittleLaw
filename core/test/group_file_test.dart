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
  test('群文件多源拉取:A 发文件 B 已下载,A 离线后 C 从 B 拉到', () async {
    final dirs = List.generate(
        3, (_) => Directory.systemTemp.createTempSync('ll_gf_'));
    final a = await LittleLawEngine.start(
        dataDir: dirs[0].path, grpcPort: 0, discoveryPort: 48961,
        deviceName: '发送者A');
    final b = await LittleLawEngine.start(
        dataDir: dirs[1].path, grpcPort: 0, discoveryPort: 48963,
        deviceName: '成员B');
    final c = await LittleLawEngine.start(
        dataDir: dirs[2].path, grpcPort: 0, discoveryPort: 48965,
        deviceName: '成员C');

    try {
      await pair(a, b, nameA: '发送者A', nameB: '成员B');
      await pair(a, c, nameA: '发送者A', nameB: '成员C');
      await pair(b, c, nameA: '成员B', nameB: '成员C');
      await connectAll([a, b, c]);

      final group = a.createGroup('文件群',
          [b.identity.deviceId, c.identity.deviceId]);
      await waitFor(() => c.groupById(group.id) != null, description: 'C 收到群定义');

      // C 关闭自动接收(模拟 C 拉取失败/延迟)。
      c.transfer.autoAcceptFiles = false;

      final tmp = File('${dirs[0].path}/hello.txt')
        ..writeAsStringSync('multi-source pull payload');
      final sent = await a.sendGroupFile(group.id, tmp.path);

      bool msgState(LittleLawEngine e, int state) {
        final list = e.loadGroupMessages(group.id);
        for (final m in list) {
          if (m.msgId == sent.msgId) return m.fileState == state;
        }
        return false;
      }

      // B 自动下载完成。
      await waitFor(() => msgState(b, Message.fileStateDone),
          description: 'B 下载完成');

      // A 下线(发送者不可达)。
      await a.dispose();

      // C 手动拉取:应从 B 多源拉到。
      final cMsg = c.loadGroupMessages(group.id)
          .firstWhere((m) => m.msgId == sent.msgId);
      expect(cMsg.fileState, Message.fileStatePending);
      await c.receiveFile(a.identity.deviceId, cMsg);
      final done = c.loadGroupMessages(group.id)
          .firstWhere((m) => m.msgId == sent.msgId);
      expect(done.fileState, Message.fileStateDone);
      expect(File(done.filePath!).readAsStringSync(), 'multi-source pull payload');

      // B 侧消息状态不受影响。
      expect(msgState(b, Message.fileStateDone), isTrue);
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
