import 'dart:io';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

void main() {
  test('FileVault:分块加密往返/篡改检测/缓存复用', () async {
    final dir = Directory.systemTemp.createTempSync('ll_vault_');
    try {
      final vault = await FileVault.open(dir.path);
      // 2.5 MiB 随机数据(跨多个 1MiB 块)。
      final plain = File('${dir.path}/big.bin');
      final data = List<int>.generate(
          2 * 1024 * 1024 + 12345, (i) => i % 251);
      await plain.writeAsBytes(data);

      final encPath = await vault.encryptFile(plain.path);
      expect(encPath.endsWith(FileVault.encExt), isTrue);
      expect(await plain.exists(), isFalse, reason: '明文临时文件应删除');
      expect(await File(encPath).length(),
          greaterThan(2 * 1024 * 1024)); // 明显不等于明文长度(头部+每块tag)

      // 解密往返。
      final out = '${dir.path}/out.bin';
      await vault.decryptFile(encPath, out);
      expect(await File(out).readAsBytes(), equals(data));

      // 缓存复用:同 key 第二次直接命中。
      final c1 = await vault.decryptToCache(encPath, 'cache-key');
      final c2 = await vault.decryptToCache(encPath, 'cache-key');
      expect(c1, equals(c2));
      expect(await File(c1).readAsBytes(), equals(data));

      // 篡改检测:翻转一个字节后解密必须失败。
      final bytes = await File(encPath).readAsBytes();
      bytes[bytes.length - 5] ^= 0xFF;
      final tampered = '${dir.path}/tampered.llenc';
      await File(tampered).writeAsBytes(bytes);
      await expectLater(
          vault.decryptFile(tampered, '${dir.path}/t.bin'),
          throwsStateError);

      // 清缓存。
      await vault.clearCache();
      expect(await File(c1).exists(), isFalse);
    } finally {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('FileVault:引擎加密模式 e2e——收到的是 .llenc,按设备分目录,可解密', () async {
    final dirs = List.generate(
        2, (_) => Directory.systemTemp.createTempSync('ll_ve_'));
    final a = await LittleLawEngine.start(
        dataDir: dirs[0].path, grpcPort: 0, discoveryPort: 48971,
        deviceName: '甲');
    final b = await LittleLawEngine.start(
        dataDir: dirs[1].path, grpcPort: 0, discoveryPort: 48973,
        deviceName: '乙乙', encryptFilesAtRest: true);
    try {
      b.transfer.progress.listen((p) {
        if (p.state == TransferProgress.stateFailed) {
          // ignore: avoid_print
          print('PROGRESS FAILED: ${p.error}');
        }
      });
      final token = a.beginRemoteOffer();
      final offer = OobBlob(
          type: OobBlob.typeOffer,
          deviceId: a.identity.deviceId,
          deviceName: '甲',
          platform: 'windows',
          fingerprint: a.identity.fingerprint,
          token: token);
      b.acceptRemoteOffer(OobBlob.decode(offer.encode()));
      a.acceptRemoteAnswer(OobBlob.decode(OobBlob(
              type: OobBlob.typeAnswer,
              deviceId: b.identity.deviceId,
              deviceName: '乙乙',
              platform: 'windows',
              fingerprint: b.identity.fingerprint,
              token: token)
          .encode()));
      a.sync.ensureSession(a.peerById(b.identity.deviceId)!,
          host: '127.0.0.1', port: b.grpcPort);
      b.sync.ensureSession(b.peerById(a.identity.deviceId)!,
          host: '127.0.0.1', port: a.grpcPort);
      while (!a.isOnline(b.identity.deviceId) ||
          !b.isOnline(a.identity.deviceId)) {
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final src = File('${dirs[0].path}/pic.png')
        ..writeAsBytesSync(List<int>.generate(300000, (i) => i % 199));
      final sent = await a.sendFile(b.identity.deviceId, src.path);

      Message? got;
      var lastState = -1;
      while (got == null || got.fileState != Message.fileStateDone) {
        await Future.delayed(const Duration(milliseconds: 50));
        for (final m in b.loadMessages(a.identity.deviceId)) {
          if (m.msgId == sent.msgId) got = m;
        }
        if (got != null && got.fileState != lastState) {
          lastState = got.fileState;
          if (got.fileState == Message.fileStateFailed) {
            fail('接收失败 state=failed');
          }
        }
      }
      // 密文存放 + 按发送方设备分目录 + 类型子目录。
      expect(got.filePath!.endsWith(FileVault.encExt), isTrue);
      expect(got.filePath!, contains('甲_'));
      expect(got.filePath!, contains('images'));
      // 门面解密路径内容一致。
      final plain = await b.plaintextPathFor(got);
      expect(await File(plain).readAsBytes(),
          equals(await src.readAsBytes()));
      // 原始路径确实是密文(非 PNG 头)。
      final raw = await File(got.filePath!).readAsBytes();
      expect(raw[0], isNot(0x89));
    } finally {
      await a.dispose();
      await b.dispose();
      for (final d in dirs) {
        try {
          d.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
