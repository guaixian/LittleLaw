import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

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
  late Directory dirA;
  late Directory dirB;
  late LittleLawEngine a;
  late LittleLawEngine b;

  setUpAll(() async {
    dirA = Directory.systemTemp.createTempSync('ll_spd_a_');
    dirB = Directory.systemTemp.createTempSync('ll_spd_b_');
    a = await LittleLawEngine.start(
      dataDir: dirA.path,
      grpcPort: 0,
      discoveryPort: 48911,
      deviceName: '设备A',
      discoveryTargets: ['127.0.0.1:48912'],
    );
    b = await LittleLawEngine.start(
      dataDir: dirB.path,
      grpcPort: 0,
      discoveryPort: 48912,
      deviceName: '设备B',
      discoveryTargets: ['127.0.0.1:48911'],
    );
    await waitFor(
      () => a.discovery.current.any((d) => d.deviceId == b.identity.deviceId) &&
          b.discovery.current.any((d) => d.deviceId == a.identity.deviceId),
      description: '互相发现',
    );
    final bSeen = a.discovery.current
        .firstWhere((d) => d.deviceId == b.identity.deviceId);
    final sub = b.pairRequests.listen((e) => b.respondPair(e.requestId, true));
    await a.requestPair(bSeen);
    await sub.cancel();
    a.sync.ensureSession(a.peerById(b.identity.deviceId)!,
        host: '127.0.0.1', port: b.grpcPort);
    b.sync.ensureSession(b.peerById(a.identity.deviceId)!,
        host: '127.0.0.1', port: a.grpcPort);
    await waitFor(
      () => a.isOnline(b.identity.deviceId) &&
          b.isOnline(a.identity.deviceId),
      description: '双端在线',
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

  Future<Duration> xfer(String name, int bytes) async {
    final rng = Random(7);
    final f = File('${dirA.path}/$name.bin');
    final chunk = List<int>.generate(1 << 20, (_) => rng.nextInt(256));
    final sink = f.openSync(mode: FileMode.write);
    for (var i = 0; i < bytes ~/ (1 << 20); i++) {
      sink.writeFromSync(chunk);
    }
    sink.flushSync();
    sink.closeSync();

    TransferProgress? done;
    final sub = b.transferProgress.listen((p) {
      if (p.state == TransferProgress.stateDone &&
          p.direction == TransferProgress.directionReceive) done = p;
    });
    final sw = Stopwatch()..start();
    await a.sendFile(b.identity.deviceId, f.path);
    await waitFor(() => done != null,
        description: '$name 完成', timeout: const Duration(minutes: 8));
    sw.stop();
    await sub.cancel();
    final mbps = (bytes / 1024 / 1024) / (sw.elapsedMilliseconds / 1000);
    // ignore: avoid_print
    print('[$name] ${bytes ~/ 1024 ~/ 1024}MB in '
        '${sw.elapsed.inMilliseconds}ms => ${mbps.toStringAsFixed(1)} MB/s');
    return sw.elapsed;
  }

  test('传输速度:gRPC 直连', () async {
    final t = await xfer('grpc', 16 << 20);
    expect(t.inSeconds, lessThan(30),
        reason: '本机回环 16MB 应秒级完成');
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('传输速度:信封回退(gRPC 地址不可达)', () async {
    // 毒化 B 眼中 A 的 fetch 地址:会话已建立不受影响,
    // 新的 FetchFile 拨号将失败 → 自动回退信封式(64KB 帧+8 帧窗口)。
    b.sync.notePeerAddress(b.peerById(a.identity.deviceId)!, '127.0.0.1', 1);
    final t = await xfer('envelope', 4 << 20);
    expect(t.inSeconds, lessThan(60),
        reason: '信封路径 4MB 不应超过 60s(43KB/s 级别 = 回归)');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
