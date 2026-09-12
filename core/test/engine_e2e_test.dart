import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

/// 轮询等待条件成立。
Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 15),
    String description = 'condition'}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('waitFor timeout: $description');
}

class TimeoutException implements Exception {
  TimeoutException(this.message);
  final String message;
  @override
  String toString() => message;
}

void main() {
  late Directory dirA;
  late Directory dirB;
  late LittleLawEngine a;
  late LittleLawEngine b;

  String idA() => a.identity.deviceId;
  String idB() => b.identity.deviceId;

  setUpAll(() async {
    dirA = Directory.systemTemp.createTempSync('ll_a_');
    dirB = Directory.systemTemp.createTempSync('ll_b_');

    // 同机双实例:固定端口错开,发现层通过 extraTargets 互指。
    a = await LittleLawEngine.start(
      dataDir: dirA.path,
      grpcPort: 0,
      discoveryPort: 48901,
      deviceName: '设备A',
      discoveryTargets: ['127.0.0.1:48902'],
    );
    b = await LittleLawEngine.start(
      dataDir: dirB.path,
      grpcPort: 0,
      discoveryPort: 48902,
      deviceName: '设备B',
      discoveryTargets: ['127.0.0.1:48901'],
    );
  });

  tearDownAll(() async {
    await a.dispose();
    await b.dispose();
    try {
      dirA.deleteSync(recursive: true);
      dirB.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('端到端:发现→配对→聊天→双端删除→离线补发→文件→剪贴板→解绑', () async {
    // ---------------------------------------------------------- 1. 发现
    await waitFor(
      () => a.discovery.current.any((d) => d.deviceId == idB()) &&
          b.discovery.current.any((d) => d.deviceId == idA()),
      description: '互相发现',
    );
    final bSeenByA = a.discovery.current.firstWhere((d) => d.deviceId == idB());
    expect(bSeenByA.info.deviceName, '设备B');
    expect(bSeenByA.info.certFingerprint, b.identity.fingerprint);

    // ---------------------------------------------------------- 2. 配对
    String? pinOnB;
    final sub = b.pairRequests.listen((event) {
      pinOnB = event.pin;
      // 模拟用户:核对 PIN 一致后点击同意。
      b.respondPair(event.requestId, true);
    });
    final result = await a.requestPair(bSeenByA);
    await sub.cancel();
    expect(result.accepted, isTrue, reason: '配对应被接受: ${result.message}');

    // SAS 双端同源:A 侧计算的 PIN 必须等于 B 侧弹窗 PIN。
    final pinOnA = a.pinFor(b.identity.fingerprint);
    expect(pinOnA, pinOnB, reason: '两端 PIN(SAS)必须一致');

    // 双端信任记录:同一共享令牌。
    final peerAinB = b.peerById(idA());
    final peerBinA = a.peerById(idB());
    expect(peerAinB, isNotNull);
    expect(peerBinA, isNotNull);
    expect(peerAinB!.token, peerBinA!.token);

    // -------------------------------------------------- 3. 建立会话(双通道)
    a.sync.ensureSession(peerBinA, host: '127.0.0.1', port: b.grpcPort);
    b.sync.ensureSession(peerAinB, host: '127.0.0.1', port: a.grpcPort);
    await waitFor(() => a.isOnline(idB()) && b.isOnline(idA()),
        description: '双方在线');

    // ---------------------------------------------------------- 4. 聊天
    final sent = await a.sendText(idB(), '你好,LittleLaw! hello 123');
    await waitFor(
      () => b.loadMessages(idA()).any((m) => m.msgId == sent.msgId),
      description: 'B 收到消息',
    );
    final onB = b.loadMessages(idA()).firstWhere((m) => m.msgId == sent.msgId);
    expect(onB.text, '你好,LittleLaw! hello 123');
    expect(onB.lamport, sent.lamport);
    expect(onB.senderId, idA());

    // -------------------------------------------------- 5. 双端删除(在线)
    await b.deleteMessages(idA(), [sent.msgId]);
    await waitFor(
      () => a.loadMessages(idB()).isEmpty && b.loadMessages(idA()).isEmpty,
      description: '双端消息已删除',
    );

    // -------------------------------------- 6. 离线队列:B 下线,A 发两条
    final bDataDir = dirB.path;
    final bOldGrpcPort = b.grpcPort;
    final bOldDeviceId = b.identity.deviceId;
    await b.dispose();

    final offline1 = await a.sendText(idB(), '离线消息1');
    final offline2 = await a.sendText(idB(), '离线消息2');
    await waitFor(() => !a.isOnline(idB()), description: 'A 感知 B 离线');

    // B 重启(同数据目录,身份与信任记录保留;新端口)。
    b = await LittleLawEngine.start(
      dataDir: bDataDir,
      grpcPort: 0,
      discoveryPort: 48903,
      deviceName: '设备B',
      discoveryTargets: ['127.0.0.1:48901'],
    );
    expect(b.identity.deviceId, bOldDeviceId, reason: '重启后设备身份不变');

    // B 主动连 A,Hello 触发 A 补发离线期间的 ops。
    final peerAinB2 = b.peerById(idA())!;
    b.sync.ensureSession(peerAinB2, host: '127.0.0.1', port: a.grpcPort);
    await waitFor(
      () => b.loadMessages(idA()).length >= 2,
      description: 'B 收到离线补发消息',
      timeout: const Duration(seconds: 20),
    );
    final texts = b.loadMessages(idA()).map((m) => m.text).toList();
    expect(texts, containsAll(['离线消息1', '离线消息2']));
    expect(
      b.loadMessages(idA()).map((m) => m.msgId).toSet(),
      containsAll([offline1.msgId, offline2.msgId]),
    );

    // 告诉 A:B 的新地址(等价于发现层刷新),恢复双通道。
    a.sync.notePeerAddress(a.peerById(idB())!, '127.0.0.1', b.grpcPort);
    await waitFor(() => a.isOnline(idB()), description: 'A 重连 B');
    expect(bOldGrpcPort == b.grpcPort, isFalse);

    // ---------------------------------------------------------- 7. 文件传输
    final rng = Random(42);
    final srcFile = File('${dirA.path}/test.bin');
    final srcBytes = List<int>.generate(3 * 1024 * 1024 + 123, (_) => rng.nextInt(256));
    await srcFile.writeAsBytes(srcBytes);
    final srcSha = sha256.convert(srcBytes).toString();

    TransferProgress? doneProgress;
    final psub = b.transferProgress.listen((p) {
      if (p.state == TransferProgress.stateDone &&
          p.direction == TransferProgress.directionReceive) {
        doneProgress = p;
      }
    });
    await a.sendFile(idB(), srcFile.path);
    await waitFor(() => doneProgress != null,
        description: 'B 文件接收完成', timeout: const Duration(seconds: 60));
    await psub.cancel();

    final inboxFile = File('${b.dataDir}/inbox/test.bin');
    expect(await inboxFile.exists(), isTrue);
    final gotSha = sha256.convert(await inboxFile.readAsBytes()).toString();
    expect(gotSha, srcSha, reason: '文件 SHA-256 必须一致');

    // 双端消息状态都为 done。
    await waitFor(() {
      final m = b.loadMessages(idA()).where((m) => m.kind == Message.kindFile);
      return m.isNotEmpty && m.first.fileState == Message.fileStateDone;
    }, description: 'B 侧文件消息状态 done');

    // ---------------------------------------------------------- 8. 剪贴板
    ClipboardReceived? clipEvent;
    final csub = b.events.listen((e) {
      if (e is ClipboardReceived) clipEvent = e;
    });
    a.sendClipboard(idB(), '剪贴板内容 test-clip');
    await waitFor(() => clipEvent != null, description: 'B 收到剪贴板');
    await csub.cancel();
    expect(clipEvent!.text, '剪贴板内容 test-clip');

    // ---------------------------------------------------------- 9. 解绑
    await a.unpair(idB());
    await waitFor(
      () => a.peerById(idB()) == null && b.peerById(idA()) == null,
      description: '双端信任记录已清除',
    );
    // 会话消息也已清空(Telegram 模式)。
    expect(a.loadMessages(idB()), isEmpty);
    expect(b.loadMessages(idA()), isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
