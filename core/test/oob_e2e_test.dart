import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';
import 'package:littlelaw_core/src/generated/littlelaw.pb.dart' as pb;

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 20),
    String description = 'condition'}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('waitFor timeout: $description');
}

void main() {
  group('OobBlob 编解码', () {
    test('往返一致', () {
      final blob = OobBlob(
        type: OobBlob.typeOffer,
        deviceId: 'dev-1',
        deviceName: '测试设备',
        platform: 'android',
        fingerprint: 'ab' * 32,
        token: 'cd' * 32,
        sdp: 'v=0 o=- ...',
        candidates: ['candidate:1 1 udp ...', 'candidate:2 1 udp ...'],
        addresses: ['192.168.1.5:47520'],
      );
      final decoded = OobBlob.decode(blob.encode());
      expect(decoded.type, OobBlob.typeOffer);
      expect(decoded.deviceId, 'dev-1');
      expect(decoded.deviceName, '测试设备');
      expect(decoded.fingerprint, 'ab' * 32);
      expect(decoded.token, 'cd' * 32);
      expect(decoded.sdp, 'v=0 o=- ...');
      expect(decoded.candidates.length, 2);
      expect(decoded.addresses, ['192.168.1.5:47520']);
      expect(decoded.hasRtc, isTrue);
    });

    test('非法输入全部拒绝', () {
      expect(() => OobBlob.decode(''), throwsFormatException);
      expect(() => OobBlob.decode('XX1.aaaa'), throwsFormatException);
      expect(() => OobBlob.decode('LLB1.not-base64!!!'), throwsFormatException);
      expect(() => OobBlob.decode('LLB1.aGVsbG8'), throwsFormatException);
    });
  });

  group('OOB 配对 + 外部链路(WebRTC 形态)端到端', () {
    late Directory dirA;
    late Directory dirB;
    late LittleLawEngine a;
    late LittleLawEngine b;

    // 内存链路对(模拟 WebRTC DataChannel 双工;broadcast 支持断链后重挂)。
    final a2b = StreamController<pb.Envelope>.broadcast();
    final b2a = StreamController<pb.Envelope>.broadcast();
    StreamController<pb.Envelope>? sinkA;
    StreamController<pb.Envelope>? sinkB;

    setUpAll(() async {
      dirA = Directory.systemTemp.createTempSync('ll_oa_');
      dirB = Directory.systemTemp.createTempSync('ll_ob_');
      a = await LittleLawEngine.start(
          dataDir: dirA.path, grpcPort: 0, discoveryPort: 48921, deviceName: '远程A');
      b = await LittleLawEngine.start(
          dataDir: dirB.path, grpcPort: 0, discoveryPort: 48922, deviceName: '远程B');
    });

    tearDownAll(() async {
      await a.dispose();
      await b.dispose();
      try {
        dirA.deleteSync(recursive: true);
        dirB.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('配对→建链→聊天→删除→文件→断链补发', () async {
      final idA = a.identity.deviceId;
      final idB = b.identity.deviceId;

      // ---------- 1. OOB 配对(offer/answer 往返) ----------
      final token = a.beginRemoteOffer();
      final offer = OobBlob(
        type: OobBlob.typeOffer,
        deviceId: idA,
        deviceName: '远程A',
        platform: 'windows',
        fingerprint: a.identity.fingerprint,
        token: token,
      );
      // B 收到 offer(扫码/粘贴/NFC)→ 入账 A → 生成 answer。
      final peerAinB = b.acceptRemoteOffer(OobBlob.decode(offer.encode()));
      expect(peerAinB.token, token);
      final answer = OobBlob(
        type: OobBlob.typeAnswer,
        deviceId: idB,
        deviceName: '远程B',
        platform: 'windows',
        fingerprint: b.identity.fingerprint,
        token: token, // 回显
      );
      // A 收到 answer → 校验回显 → 入账 B。
      final peerBinA = a.acceptRemoteAnswer(OobBlob.decode(answer.encode()));
      expect(peerBinA.token, token);
      expect(a.peerById(idB), isNotNull);
      expect(b.peerById(idA), isNotNull);

      // 伪造应答必须被拒(令牌不回显)。
      expect(
        () => a.acceptRemoteAnswer(OobBlob(
              type: OobBlob.typeAnswer,
              deviceId: 'evil',
              deviceName: 'x',
              platform: 'x',
              fingerprint: 'ff' * 32,
              token: 'wrong',
            )),
        throwsStateError,
      );

      // ---------- 2. 挂载内存链路(模拟 WebRTC) ----------
      sinkA = a.attachExternalTransport(idB, b2a.stream);
      sinkA!.stream.listen(a2b.add);
      sinkB = b.attachExternalTransport(idA, a2b.stream);
      sinkB!.stream.listen(b2a.add);
      await waitFor(() => a.isOnline(idB) && b.isOnline(idA),
          description: '外链路在线');

      // ---------- 3. 聊天(纯外部链路) ----------
      final msg = await a.sendText(idB, 'WebRTC 形态消息');
      await waitFor(
          () => b.loadMessages(idA).any((m) => m.msgId == msg.msgId),
          description: 'B 经外链路收到消息');
      expect(
          b.loadMessages(idA).firstWhere((m) => m.msgId == msg.msgId).text,
          'WebRTC 形态消息');

      // ---------- 4. 双端删除 ----------
      await b.deleteMessages(idA, [msg.msgId]);
      await waitFor(
          () => a.loadMessages(idB).isEmpty && b.loadMessages(idA).isEmpty,
          description: '外链路双端删除');

      // ---------- 5. 文件(信封式拉取,无 gRPC 地址) ----------
      expect(b.peerById(idA)!.lastHost, isNull,
          reason: 'OOB 配对无局域网地址,必须走信封通道');
      final rng = Random(7);
      final srcFile = File('${dirA.path}/oob.bin');
      final srcBytes =
          List<int>.generate(2 * 1024 * 1024 + 77, (_) => rng.nextInt(256));
      await srcFile.writeAsBytes(srcBytes);
      final srcSha = sha256.convert(srcBytes).toString();

      TransferProgress? done;
      final psub = b.transferProgress.listen((p) {
        if (p.state == TransferProgress.stateDone &&
            p.direction == TransferProgress.directionReceive) {
          done = p;
        }
      });
      await a.sendFile(idB, srcFile.path);
      await waitFor(() => done != null,
          description: '信封式文件传输完成', timeout: const Duration(seconds: 60));
      await psub.cancel();
      final gotSha = sha256
          .convert(await File('${dirB.path}/inbox/oob.bin').readAsBytes())
          .toString();
      expect(gotSha, srcSha);

      // ---------- 6. 断链 → 离线队列 → 重链补发 ----------
      b.detachExternalTransport(idA, sinkB!);
      sinkB = null;
      await waitFor(() => !a.isOnline(idB) || !b.isOnline(idA),
          description: '链路断开感知');
      final queued = await a.sendText(idB, '断链期间的消息');

      // 重新挂载。
      sinkB = b.attachExternalTransport(idA, a2b.stream);
      sinkB!.stream.listen(b2a.add);
      await waitFor(
          () => b.loadMessages(idA).any((m) => m.msgId == queued.msgId),
          description: '重链后补发断链期间消息');

      // ---------- 收尾:解绑双端清零 ----------
      await a.unpair(idB);
      expect(a.peerById(idB), isNull);
      // OOB 对端无 gRPC 地址,unpair RPC 不可达,本地清除即生效;
      // 对端令牌随之失效(对方若还在线,其链路鉴权将失败)。
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
