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
  const serverAddr = '127.0.0.1:47910';
  const serverUrl = 'ws://$serverAddr/ws';
  Process? serverProc;

  setUpAll(() async {
    final dbDir = Directory.systemTemp.createTempSync('ll_pdb_');
    serverProc = await Process.start(
      '../server/rendezvous.exe',
      ['-addr', serverAddr, '-db', '${dbDir.path}/r.db'],
      workingDirectory: '../server',
    );
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
  });

  OobBlob makeOffer(LittleLawEngine a, String token) => OobBlob(
        type: OobBlob.typeOffer,
        deviceId: a.identity.deviceId,
        deviceName: '邀请方A',
        platform: 'windows',
        fingerprint: a.identity.fingerprint,
        token: token,
        deviceModel: 'test',
        rendezvousUrl: serverUrl,
      );

  OobBlob makeAnswer(LittleLawEngine b, String token) => OobBlob(
        type: OobBlob.typeAnswer,
        deviceId: b.identity.deviceId,
        deviceName: '受邀方B',
        platform: 'windows',
        fingerprint: b.identity.fingerprint,
        token: token,
        deviceModel: 'test',
      );

  test('一扫即成:受邀方应答经服务器推回,邀请方免回填', () async {
    final dirA = Directory.systemTemp.createTempSync('ll_pa_');
    final dirB = Directory.systemTemp.createTempSync('ll_pb_');
    final a = await LittleLawEngine.start(
      dataDir: dirA.path,
      grpcPort: 0,
      discoveryPort: 48971,
      deviceName: '邀请方A',
      rendezvousUrl: serverUrl,
    );
    final b = await LittleLawEngine.start(
      dataDir: dirB.path,
      grpcPort: 0,
      discoveryPort: 48973,
      deviceName: '受邀方B',
      rendezvousUrl: serverUrl,
    );

    try {
      await waitFor(
        () => (a.rendezvous?.connected ?? false) &&
            (b.rendezvous?.connected ?? false),
        description: '双方注册到服务器',
      );

      // ---------- 方式一:B 用已连接的服务器客户端推回 ----------
      final token1 = a.beginRemoteOffer();
      final offer1 = makeOffer(a, token1);
      // B 扫码:应用 offer(入账 A)。
      b.acceptRemoteOffer(OobBlob.decode(offer1.encode()));
      final answer1 = makeAnswer(b, token1).encode();

      final delivered = <String>[];
      final sub = a.answerDeliveries.listen(delivered.add);
      await b.rendezvous!.sendPairAnswer(a.identity.deviceId, answer1);

      await waitFor(() => delivered.isNotEmpty,
          description: 'A 经服务器收到配对应答');
      expect(delivered.first, answer1);
      // A 的 WebRTC 层(此处模拟)应用应答 → 入账 B。
      final peerB = a.acceptRemoteAnswer(OobBlob.decode(delivered.first));
      // 令牌已轮换(ECDH 派生),不再是二维码明文的 offer 令牌。
      expect(peerB.token, isNot(token1));
      expect(a.peerById(b.identity.deviceId)!.token, peerB.token);
      expect(
          b.peerById(a.identity.deviceId)!.token, peerB.token,
          reason: '双方各自轮换结果一致');

      // ---------- 方式二:一次性临时连接推回(模拟未配置服务器的设备) ----------
      final token2 = a.beginRemoteOffer();
      final offer2 = makeOffer(a, token2);
      b.acceptRemoteOffer(OobBlob.decode(offer2.encode()));
      final answer2 = makeAnswer(b, token2).encode();

      delivered.clear();
      await b.deliverPairAnswerOnce(serverUrl, a.identity.deviceId, answer2);

      await waitFor(() => delivered.isNotEmpty,
          description: 'A 经一次性连接收到配对应答');
      expect(delivered.first, answer2);
      final peerB2 = a.acceptRemoteAnswer(OobBlob.decode(delivered.first));
      expect(peerB2.token, isNot(token2), reason: '令牌轮换');
      expect(b.peerById(a.identity.deviceId)!.token, peerB2.token);

      await sub.cancel();
    } finally {
      await a.dispose();
      await b.dispose();
      try {
        dirA.deleteSync(recursive: true);
        dirB.deleteSync(recursive: true);
      } catch (_) {}
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
