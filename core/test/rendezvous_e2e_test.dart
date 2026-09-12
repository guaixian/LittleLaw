import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 25),
    String description = 'condition'}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return;
    await Future.delayed(const Duration(milliseconds: 150));
  }
  throw StateError('waitFor timeout: $description');
}

void main() {
  const serverAddr = '127.0.0.1:47900';
  const serverUrl = 'ws://$serverAddr/ws';
  Process? serverProc;
  late File dbFile;

  setUpAll(() async {
    dbFile = File(
        '${Directory.systemTemp.createTempSync('ll_rdb_').path}/rendezvous.db');
    serverProc = await Process.start(
      '../server/rendezvous.exe',
      ['-addr', serverAddr, '-db', dbFile.path],
      workingDirectory: '../server',
    );
    // 等服务器就绪。
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    var up = false;
    while (DateTime.now().isBefore(deadline) && !up) {
      try {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse('http://$serverAddr/healthz'));
        final resp = await req.close();
        up = resp.statusCode == 200;
        client.close();
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    if (!up) throw StateError('rendezvous server 未能就绪');
  });

  tearDownAll(() async {
    serverProc?.kill();
    try {
      dbFile.deleteSync();
    } catch (_) {}
  });

  test('中转服务器:注册认证/presence/离线邮箱跨网送达', () async {
    final dirA = Directory.systemTemp.createTempSync('ll_ra_');
    final dirB = Directory.systemTemp.createTempSync('ll_rb_');

    // 注意:不互配 discoveryTargets,发现端口错开 → 无局域网会话,
    // rendezvous 成为唯一通讯路径(正是要验证的场景)。
    var a = await LittleLawEngine.start(
      dataDir: dirA.path,
      grpcPort: 0,
      discoveryPort: 48961,
      deviceName: '远程A',
      rendezvousUrl: serverUrl,
    );
    var b = await LittleLawEngine.start(
      dataDir: dirB.path,
      grpcPort: 0,
      discoveryPort: 48963,
      deviceName: '远程B',
      rendezvousUrl: serverUrl,
    );

    try {
      // ---------- 1. 双方 ECDSA 认证注册成功 ----------
      await waitFor(
        () => (a.rendezvous?.connected ?? false) &&
            (b.rendezvous?.connected ?? false),
        description: '双方注册到服务器',
      );

      // ---------- 2. OOB 配对(不经服务器,信任仍属设备间) ----------
      final token = a.beginRemoteOffer();
      final offer = OobBlob(
        type: OobBlob.typeOffer,
        deviceId: a.identity.deviceId,
        deviceName: '远程A',
        platform: 'windows',
        fingerprint: a.identity.fingerprint,
        token: token,
      );
      b.acceptRemoteOffer(OobBlob.decode(offer.encode()));
      final answer = OobBlob(
        type: OobBlob.typeAnswer,
        deviceId: b.identity.deviceId,
        deviceName: '远程B',
        platform: 'windows',
        fingerprint: b.identity.fingerprint,
        token: token,
      );
      a.acceptRemoteAnswer(OobBlob.decode(answer.encode()));

      // 配对后订阅刷新,双方互见在线(presence)。
      a.rendezvous!.subscribePeers();
      b.rendezvous!.subscribePeers();
      String? aSeesOnline;
      String? aSeesOffline;
      final aOnlineSub = a.rendezvous!.peerOnline.listen((id) {
        if (id == b.identity.deviceId) aSeesOnline = id;
      });
      final aOfflineSub = a.rendezvous!.peerOffline.listen((id) {
        if (id == b.identity.deviceId) aSeesOffline = id;
      });
      await waitFor(() => aSeesOnline != null,
          description: 'A 看到 B 在线(presence)');

      // ---------- 3. B 下线,A 经服务器邮箱发消息 ----------
      await b.dispose();
      await waitFor(() => aSeesOffline != null,
          description: 'A 感知 B 下线(presence)');

      final m1 = await a.sendText(b.identity.deviceId, '离线消息一(经服务器)');
      final m2 = await a.sendText(b.identity.deviceId, '离线消息二(经服务器)');

      // ---------- 4. B 重启上线,自动拉取离线邮箱 ----------
      b = await LittleLawEngine.start(
        dataDir: dirB.path,
        grpcPort: 0,
        discoveryPort: 48965,
        deviceName: '远程B',
        rendezvousUrl: serverUrl,
      );
      expect(b.identity.deviceId, a.peerById(b.identity.deviceId)!.deviceId,
          reason: '重启后身份不变');

      await waitFor(() => (b.rendezvous?.connected ?? false),
          description: 'B 重新注册');
      await waitFor(
        () => b.loadMessages(a.identity.deviceId).length >= 2,
        description: 'B 收到离线邮箱消息',
        timeout: const Duration(seconds: 30),
      );
      final texts =
          b.loadMessages(a.identity.deviceId).map((m) => m.text).toSet();
      expect(texts, containsAll(['离线消息一(经服务器)', '离线消息二(经服务器)']));
      expect(
        b.loadMessages(a.identity.deviceId).map((m) => m.msgId).toSet(),
        containsAll([m1.msgId, m2.msgId]),
      );

      await aOnlineSub.cancel();
      await aOfflineSub.cancel();
    } finally {
      await a.dispose();
      await b.dispose();
      try {
        dirA.deleteSync(recursive: true);
        dirB.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
