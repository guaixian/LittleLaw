import 'dart:convert';

import 'package:test/test.dart';
import 'package:littlelaw_core/littlelaw_core.dart';

void main() {
  group('Base45 (RFC 9285)', () {
    test('编解码往返(偶数字节)', () {
      final data = utf8.encode('Hello World!');
      final encoded = Base45.encode(data);
      expect(Base45.isBase45Charset(encoded), isTrue);
      expect(Base45.decode(encoded), data);
    });

    test('奇数字节与边界', () {
      for (final data in [
        <int>[],
        [0],
        [255],
        [0, 0],
        [255, 255],
        utf8.encode('LLB3 测试中文 ✓'),
      ]) {
        expect(Base45.decode(Base45.encode(data)), data,
            reason: '数据: $data');
      }
    });

    test('非法字符与损坏数据拒绝', () {
      expect(() => Base45.decode('abc!~'), throwsFormatException);
      expect(Base45.isBase45Charset('abc'), isFalse); // 小写不在表内
      expect(Base45.isBase45Charset('AB12 %\$%*+-./:'), isTrue);
    });
  });

  group('OobBlob LLB3(LZMA+Base45)', () {
    final sample = OobBlob(
      type: OobBlob.typeOffer,
      deviceId: 'dev-1',
      deviceName: '测试设备',
      platform: 'android',
      fingerprint: 'ab' * 32,
      token: 'cd' * 32,
      deviceModel: 'Xiaomi 13',
      sdp: 'v=0 o=- 123 2 IN IP4\r\na=group:BUNDLE 0\r\na=fingerprint:sha-256 AA:BB',
      candidates: [
        '{"candidate":"candidate:1 1 udp 1 192.168.1.1 9 typ host","sdpMid":"0","sdpMLineIndex":0}'
      ],
      addresses: ['192.168.1.5:47520'],
    );

    test('LLB3 往返一致且字符集合规', () {
      final encoded = sample.encode();
      expect(encoded.startsWith('LLB3.'), isTrue);
      expect(Base45.isBase45Charset(encoded.substring(5)), isTrue);
      final decoded = OobBlob.decode(encoded);
      expect(decoded.deviceId, sample.deviceId);
      expect(decoded.sdp, sample.sdp);
      expect(decoded.candidates.length, 1);
      expect(decoded.addresses, sample.addresses);
    });

    test('非法输入拒绝', () {
      expect(() => OobBlob.decode('LLB3.!!!!'), throwsFormatException);
      expect(() => OobBlob.decode(''), throwsFormatException);
      expect(() => OobBlob.decode('XX1.aaaa'), throwsFormatException);
    });
  });
}
