import 'dart:io';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 15),
    String description = 'condition'}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return;
    await Future.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('waitFor timeout: $description');
}

void main() {
  test('配对取消:A 取消请求后 B 再点同意,双方都不入账', () async {
    final dirA = Directory.systemTemp.createTempSync('ll_ca_');
    final dirB = Directory.systemTemp.createTempSync('ll_cb_');
    final a = await LittleLawEngine.start(
      dataDir: dirA.path,
      grpcPort: 0,
      discoveryPort: 48951,
      deviceName: 'A',
      discoveryTargets: ['127.0.0.1:48952'],
    );
    final b = await LittleLawEngine.start(
      dataDir: dirB.path,
      grpcPort: 0,
      discoveryPort: 48952,
      deviceName: 'B',
      discoveryTargets: ['127.0.0.1:48951'],
    );
    try {
      await waitFor(
        () => a.discovery.current.any((d) => d.deviceId == b.identity.deviceId),
        description: 'A 发现 B',
      );
      final bSeen = a.discovery.current
          .firstWhere((d) => d.deviceId == b.identity.deviceId);

      // B 收到请求后先记下 requestId,不立即同意。
      PairRequestEvent? pending;
      final sub = b.pairRequests.listen((e) => pending = e);
      final future = a.requestPair(bSeen);
      await waitFor(() => pending != null, description: 'B 收到配对请求');

      // A 取消。
      await a.cancelPairRequest(b.identity.deviceId);

      // B 之后(用户手慢)才点同意 → 应无效。
      b.respondPair(pending!.requestId, true);
      final result = await future;
      await sub.cancel();

      expect(result.accepted, isFalse, reason: '取消后 B 的同意必须无效');
      expect(a.peerById(b.identity.deviceId), isNull,
          reason: 'A 侧不得入账');
      expect(b.peerById(a.identity.deviceId), isNull,
          reason: 'B 侧不得入账');
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
