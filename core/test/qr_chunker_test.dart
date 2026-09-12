import 'dart:math';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

void main() {
  group('QrChunker 分片二维码', () {
    test('切分-重组往返一致', () {
      final rng = Random(1);
      final payload = String.fromCharCodes(
          List.generate(5000, (_) => 33 + rng.nextInt(90)));
      final frames = QrChunker.split(payload);
      expect(frames.length, greaterThan(10));
      // 每帧都是合法帧,且体积小。
      for (final f in frames) {
        expect(QrChunker.isChunk(f), isTrue);
        expect(f.length, lessThanOrEqualTo(QrChunker.defaultChunkSize + 20));
      }
      // 乱序喂入也能重组。
      final shuffled = List.of(frames)..shuffle();
      final re = QrReassembler();
      for (final f in shuffled) {
        re.add(f);
      }
      expect(re.complete, isTrue);
      expect(re.payload, payload);
    });

    test('短内容单帧', () {
      final frames = QrChunker.split('hello');
      expect(frames.length, 1);
      final re = QrReassembler();
      expect(re.add(frames.first), isTrue);
      expect(re.payload, 'hello');
    });

    test('重复帧去重、不同批次重置、非法帧拒绝', () {
      final frames = QrChunker.split('x' * 1000);
      final re = QrReassembler();
      expect(re.add(frames[0]), isTrue);
      expect(re.add(frames[0]), isFalse, reason: '重复帧');
      expect(re.received, 1);
      expect(re.add('not-a-chunk'), isFalse);
      expect(re.add('LLQ2.xx.yy.zz'), isFalse);

      // 新批次重置。
      final frames2 = QrChunker.split('y' * 300);
      re.add(frames2[0]);
      expect(re.total, QrChunker.parseFrame(frames2[0])!.total);
      expect(re.received, 1, reason: '批次切换后旧数据清空');
    });
  });
}
