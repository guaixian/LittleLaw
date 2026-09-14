import 'dart:io';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

Future<void> waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 30),
    String description = 'condition'}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (cond()) return;
    await Future.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('waitFor timeout: $description');
}

void main() {
  test('设备离开:发现列表移除 + 已配对设备标记离线', () async {
    final dirA = Directory.systemTemp.createTempSync('ll_xa_');
    final dirB = Directory.systemTemp.createTempSync('ll_xb_');
    final a = await LittleLawEngine.start(
      dataDir: dirA.path,
      grpcPort: 0,
      discoveryPort: 48941,
      deviceName: '留守A',
      discoveryTargets: ['127.0.0.1:48942'],
    );
    final b = await LittleLawEngine.start(
      dataDir: dirB.path,
      grpcPort: 0,
      discoveryPort: 48942,
      deviceName: '离开B',
      discoveryTargets: ['127.0.0.1:48941'],
    );

    try {
      // 1. 互相发现并配对,建立会话。
      await waitFor(
        () => a.discovery.current.any((d) => d.deviceId == b.identity.deviceId),
        description: 'A 发现 B',
      );
      final bSeen = a.discovery.current
          .firstWhere((d) => d.deviceId == b.identity.deviceId);
      final sub = b.pairRequests.listen((e) => b.respondPair(e.requestId, true));
      final result = await a.requestPair(bSeen);
      await sub.cancel();
      expect(result.accepted, isTrue);

      a.sync.ensureSession(a.peerById(b.identity.deviceId)!,
          host: '127.0.0.1', port: b.grpcPort);
      b.sync.ensureSession(b.peerById(a.identity.deviceId)!,
          host: '127.0.0.1', port: a.grpcPort);
      await waitFor(
          () => a.isOnline(b.identity.deviceId) &&
              b.isOnline(a.identity.deviceId),
          description: '双方在线');

      // 2. B 停发现服务(不再宣告):
      //    新语义:发现超时即强制断开半开 TCP/WebRTC 链路并标记离线——
      //    B 离线后在线徽标必须及时消失,不能长期显示"在线"。
      String? expiredId;
      final esub = a.discovery.expiredDevices.listen((id) => expiredId = id);
      await b.discovery.stop();

      await waitFor(() => expiredId == b.identity.deviceId,
          description: 'A 判定 B 发现超时', timeout: const Duration(seconds: 25));
      await esub.cancel();
      await waitFor(
        () => !a.discovery.current
            .any((d) => d.deviceId == b.identity.deviceId),
        description: '发现列表移除 B',
      );
      await waitFor(
        () => !a.isOnline(b.identity.deviceId),
        description: '发现超时后 A 断开半开链路并标记离线',
        timeout: const Duration(seconds: 15),
      );

      // 3. B 彻底下线(进程级):此时 A 已判定离线(上一步)。
      final bDataDir = dirB.path;
      await b.dispose();
      expect(a.isOnline(b.identity.deviceId), isFalse);

      // 4. B 重新出现(重启)→ 自动恢复在线。
      final b2 = await LittleLawEngine.start(
        dataDir: bDataDir,
        grpcPort: 0,
        discoveryPort: 48942,
        deviceName: '离开B',
        discoveryTargets: ['127.0.0.1:48941'],
      );
      await waitFor(
        () => a.isOnline(b.identity.deviceId),
        description: 'B 回归后自动恢复在线',
        timeout: const Duration(seconds: 30),
      );
      await b2.dispose();
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
